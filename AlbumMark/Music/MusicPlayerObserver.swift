import Combine
import Foundation
import MusicKit

@MainActor
final class MusicPlayerObserver: ObservableObject {
    #if LOCAL_DEBUG_WITHOUT_MUSICKIT
    @Published private(set) var authorizationStatus: MusicAuthorization.Status = .authorized
    #else
    @Published private(set) var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    #endif
    @Published private(set) var nowPlaying: NowPlayingSnapshot?
    @Published private(set) var progress: AlbumProgressResult?
    @Published var statusMessage: String?
    @Published var actionMessage: String?

    private let musicAppBridge = MusicAppBridge()
    #if !LOCAL_DEBUG_WITHOUT_MUSICKIT
    private let musicKitPlayer = ApplicationMusicPlayer.shared
    #endif
    private let store: AlbumProgressStore
    private let settings: AppSettings
    private let artworkCacheDirectory: URL
    private var checkpointTimer: Timer?
    private var lastSaveDate: Date = .distantPast
    private var lastObservedTrackIdentifier: String?
    private var musicAppAlbumTrackCache: [String: [AlbumTrackInfo]] = [:]
    private var appleMusicLinkCache: [String: AppleMusicLinkMetadata] = [:]
    #if !LOCAL_DEBUG_WITHOUT_MUSICKIT
    private var catalogAlbumCache: [String: CatalogAlbumMetadata] = [:]
    #endif

    init(store: AlbumProgressStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        artworkCacheDirectory = supportDirectory
            .appendingPathComponent("AlbumMark", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMusicPlayerNotification),
            name: Notification.Name("com.apple.Music.playerInfo"),
            object: nil
        )

        Task {
            await refreshAuthorizationStatus()
            await refreshNowPlaying(reason: .playerChange)
        }
    }

    func requestAuthorization() {
        #if LOCAL_DEBUG_WITHOUT_MUSICKIT
        authorizationStatus = .authorized
        #else
        Task {
            authorizationStatus = await MusicAuthorization.request()
            await refreshNowPlaying(reason: .playerChange)
        }
        #endif
    }

    func resume(_ record: AlbumProgressRecord) {
        Task {
            await resumePlayback(from: record)
        }
    }

    @objc private func handleMusicPlayerNotification() {
        checkpointTimer?.invalidate()
        Task {
            await refreshNowPlaying(reason: .trackChange)
        }
    }

    private func refreshAuthorizationStatus() async {
        #if LOCAL_DEBUG_WITHOUT_MUSICKIT
        authorizationStatus = .authorized
        #else
        authorizationStatus = MusicAuthorization.currentStatus
        #endif
    }

    private enum RefreshReason {
        case checkpoint
        case playerChange
        case trackChange
    }

    private func refreshNowPlaying(reason: RefreshReason) async {
        #if LOCAL_DEBUG_WITHOUT_MUSICKIT
        authorizationStatus = .authorized
        #else
        authorizationStatus = MusicAuthorization.currentStatus

        guard authorizationStatus == .authorized else {
            nowPlaying = nil
            progress = nil
            statusMessage = nil
            checkpointTimer?.invalidate()
            return
        }
        #endif

        do {
            guard let snapshot = try await captureSnapshot() else {
                nowPlaying = nil
                progress = nil
                checkpointTimer?.invalidate()
                return
            }

            let calculatedProgress = AlbumProgressCalculator.calculate(for: snapshot)
            nowPlaying = snapshot
            progress = calculatedProgress
            statusMessage = nil
            maybeSave(snapshot: snapshot, progress: calculatedProgress, reason: reason)
            scheduleNextCheckpointIfNeeded(for: snapshot)
        } catch {
            nowPlaying = nil
            progress = nil
            statusMessage = error.localizedDescription
            checkpointTimer?.invalidate()
        }
    }

    private func scheduleNextCheckpointIfNeeded(for snapshot: NowPlayingSnapshot) {
        checkpointTimer?.invalidate()
        guard snapshot.playbackState == .playing else { return }

        checkpointTimer = Timer.scheduledTimer(withTimeInterval: settings.saveInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshNowPlaying(reason: .checkpoint)
            }
        }
    }

    private func captureSnapshot() async throws -> NowPlayingSnapshot? {
        guard let currentTrack = try musicAppBridge.currentTrack() else {
            statusMessage = "No Apple Music track is active."
            return nil
        }

        guard !currentTrack.albumTitle.isEmpty else {
            statusMessage = "This track does not expose album metadata."
            return nil
        }

        let musicAppCacheKey = musicAppAlbumCacheKey(for: currentTrack)
        let musicAppTracks = try cachedMusicAppAlbumTracks(for: currentTrack, cacheKey: musicAppCacheKey)
        #if LOCAL_DEBUG_WITHOUT_MUSICKIT
        let catalogMetadata: CatalogAlbumMetadata? = nil
        #else
        let catalogMetadata = try? await catalogAlbumMetadata(for: currentTrack)
        #endif

        let albumTracks = catalogMetadata?.tracks.isEmpty == false ? catalogMetadata?.tracks ?? [] : musicAppTracks
        let albumIdentifier = catalogMetadata?.albumIdentifier
            ?? stableMusicAppAlbumIdentifier(for: currentTrack, tracks: musicAppTracks)
        let trackIdentifier = catalogTrackIdentifier(for: currentTrack, metadata: catalogMetadata)
            ?? currentTrack.persistentID
        let musicAppArtworkURL = try? musicAppBridge.currentTrackArtworkURL(
            persistentID: currentTrack.persistentID,
            artworkDirectory: artworkCacheDirectory
        )
        let totalTrackCount = catalogMetadata?.trackCount
            ?? currentTrack.totalTrackCount
            ?? albumTracks.count.nonZero
        let appleMusicLinks = await appleMusicLinkMetadata(for: currentTrack)

        return NowPlayingSnapshot(
            trackIdentifier: trackIdentifier,
            musicAppPersistentID: currentTrack.persistentID,
            musicAppTrackID: currentTrack.trackID,
            musicAppSourceID: currentTrack.sourceID,
            albumIdentifier: albumIdentifier,
            songTitle: currentTrack.songTitle,
            artistName: catalogMetadata?.artistName ?? currentTrack.artistName,
            albumTitle: catalogMetadata?.albumTitle ?? currentTrack.albumTitle,
            artworkURL: catalogMetadata?.artworkURL ?? musicAppArtworkURL,
            appleMusicTrackURL: appleMusicLinks?.trackURL,
            appleMusicAlbumURL: appleMusicLinks?.albumURL,
            appleMusicCollectionID: appleMusicLinks?.collectionID,
            appleMusicCatalogTrackID: appleMusicLinks?.trackID,
            trackNumber: currentTrack.trackNumber,
            totalTrackCount: totalTrackCount,
            playbackPosition: currentTrack.playbackPosition,
            songDuration: currentTrack.songDuration,
            playbackState: currentTrack.playbackState,
            albumTracks: albumTracks,
            albumContextIsReliable: currentTrack.trackNumber != nil || totalTrackCount != nil,
            capturedAt: Date()
        )
    }

    private func cachedMusicAppAlbumTracks(
        for currentTrack: MusicAppCurrentTrack,
        cacheKey: String
    ) throws -> [AlbumTrackInfo] {
        if let cached = musicAppAlbumTrackCache[cacheKey] {
            return cached
        }

        let tracks = try musicAppBridge.albumTracks(
            albumTitle: currentTrack.albumTitle,
            artistName: currentTrack.artistName,
            totalTrackCount: currentTrack.totalTrackCount
        )
        musicAppAlbumTrackCache[cacheKey] = tracks
        return tracks
    }

    private func appleMusicLinkMetadata(for currentTrack: MusicAppCurrentTrack) async -> AppleMusicLinkMetadata? {
        await appleMusicLinkMetadata(
            songTitle: currentTrack.songTitle,
            albumTitle: currentTrack.albumTitle,
            artistName: currentTrack.artistName,
            trackNumber: currentTrack.trackNumber,
            country: nil
        )
    }

    private func appleMusicLinkMetadata(
        songTitle: String,
        albumTitle: String,
        artistName: String,
        trackNumber: Int?,
        country: String?
    ) async -> AppleMusicLinkMetadata? {
        let storefront = country ?? Locale.current.region?.identifier ?? "US"
        let cacheKey = [
            storefront.uppercased(),
            normalized(songTitle),
            normalized(albumTitle),
            normalized(artistName),
            "\(trackNumber ?? 0)"
        ].joined(separator: "|")

        if let cached = appleMusicLinkCache[cacheKey] {
            return cached
        }

        guard var components = URLComponents(string: "https://itunes.apple.com/search") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artistName) \(albumTitle) \(songTitle)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: storefront)
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppleMusicSearchResponse.self, from: data)
            let result = response.results.first { result in
                metadataMatches(
                    result,
                    songTitle: songTitle,
                    albumTitle: albumTitle,
                    artistName: artistName,
                    trackNumber: trackNumber,
                    requireTrackNumber: true
                )
            } ?? response.results.first { result in
                metadataMatches(
                    result,
                    songTitle: songTitle,
                    albumTitle: albumTitle,
                    artistName: artistName,
                    trackNumber: trackNumber,
                    requireTrackNumber: false
                )
            }

            guard let result else { return nil }

            let metadata = AppleMusicLinkMetadata(
                trackURL: result.trackViewURL.flatMap(URL.init(string:)),
                albumURL: result.collectionViewURL.flatMap(URL.init(string:)),
                collectionID: result.collectionID,
                trackID: result.trackID
            )
            appleMusicLinkCache[cacheKey] = metadata
            return metadata
        } catch {
            return nil
        }
    }

    private func metadataMatches(
        _ result: AppleMusicSearchResponse.Result,
        songTitle: String,
        albumTitle: String,
        artistName: String,
        trackNumber: Int?,
        requireTrackNumber: Bool
    ) -> Bool {
        if requireTrackNumber, let trackNumber, result.trackNumber != trackNumber {
            return false
        }

        return normalized(result.trackName) == normalized(songTitle)
            && normalized(result.collectionName) == normalized(albumTitle)
            && artistNamesAreClose(result.artistName, artistName)
    }

    #if !LOCAL_DEBUG_WITHOUT_MUSICKIT
    private func catalogAlbumMetadata(for currentTrack: MusicAppCurrentTrack) async throws -> CatalogAlbumMetadata? {
        let cacheKey = musicAppAlbumCacheKey(for: currentTrack)
        if let cached = catalogAlbumCache[cacheKey] {
            return cached
        }

        var request = MusicCatalogSearchRequest(
            term: "\(currentTrack.albumTitle) \(currentTrack.artistName)",
            types: [Album.self]
        )
        request.limit = 5

        let response = try await request.response()
        let matchingAlbum = response.albums.first { album in
            album.title.caseInsensitiveCompare(currentTrack.albumTitle) == .orderedSame
                && artistNamesAreClose(album.artistName, currentTrack.artistName)
        } ?? response.albums.first { album in
            album.title.caseInsensitiveCompare(currentTrack.albumTitle) == .orderedSame
        }

        guard let matchingAlbum else { return nil }
        let expandedAlbum = try await matchingAlbum.with([.tracks])
        let tracks = expandedAlbum.tracks?.map { track in
            AlbumTrackInfo(
                id: track.id.rawValue,
                title: track.title,
                artistName: track.artistName,
                trackNumber: track.trackNumber,
                duration: track.duration
            )
        } ?? []

        let metadata = CatalogAlbumMetadata(
            albumIdentifier: expandedAlbum.id.rawValue,
            albumTitle: expandedAlbum.title,
            artistName: expandedAlbum.artistName,
            artworkURL: expandedAlbum.artwork?.url(width: 160, height: 160),
            trackCount: expandedAlbum.trackCount,
            tracks: tracks
        )

        catalogAlbumCache[cacheKey] = metadata
        return metadata
    }
    #endif

    private func catalogTrackIdentifier(
        for currentTrack: MusicAppCurrentTrack,
        metadata: CatalogAlbumMetadata?
    ) -> String? {
        guard let metadata else { return nil }

        return metadata.tracks.first { track in
            track.trackNumber == currentTrack.trackNumber
                && track.title.caseInsensitiveCompare(currentTrack.songTitle) == .orderedSame
        }?.id ?? metadata.tracks.first { track in
            track.trackNumber == currentTrack.trackNumber
        }?.id
    }

    private func maybeSave(
        snapshot: NowPlayingSnapshot,
        progress: AlbumProgressResult,
        reason: RefreshReason
    ) {
        guard snapshot.albumContextIsReliable else { return }

        let existingRecord = store.records.first { $0.albumIdentifier == snapshot.albumIdentifier }
        let shouldBackfillArtwork = existingRecord?.artworkURLString == nil && snapshot.artworkURL != nil
        guard snapshot.playbackState == .playing || reason == .trackChange || shouldBackfillArtwork else { return }

        let trackChanged = snapshot.trackIdentifier != lastObservedTrackIdentifier
        if trackChanged {
            lastObservedTrackIdentifier = snapshot.trackIdentifier
        }

        let now = Date()
        let dueForSave = now.timeIntervalSince(lastSaveDate) >= settings.saveInterval
        let shouldSave = trackChanged || dueForSave || reason == .trackChange || shouldBackfillArtwork

        guard shouldSave else { return }

        let record = AlbumProgressRecord.make(from: snapshot, progress: progress)
        store.upsert(record, hideCompletedThreshold: settings.hideCompletedThreshold)
        lastSaveDate = now
    }

    private func resumePlayback(from record: AlbumProgressRecord) async {
        #if LOCAL_DEBUG_WITHOUT_MUSICKIT
        do {
            let persistentID = musicAppPersistentID(for: record)
            try musicAppBridge.resume(resumeTarget(for: record, persistentID: persistentID, albumTrackURLs: []))
            actionMessage = "Resuming \(record.albumTitle) from \(TimeFormatter.positionString(from: record.playbackPosition))."
        } catch {
            actionMessage = "Could not resume \(record.albumTitle): \(error.localizedDescription)"
        }
        #else
        guard MusicAuthorization.currentStatus == .authorized else {
            requestAuthorization()
            return
        }

        do {
            if !record.albumIdentifier.hasPrefix("musicapp:"),
               try await resumeWithMusicKit(record) {
                return
            }

            let persistentID = musicAppPersistentID(for: record)
            try musicAppBridge.resume(resumeTarget(for: record, persistentID: persistentID, albumTrackURLs: []))
            actionMessage = "Resuming \(record.albumTitle) from \(TimeFormatter.positionString(from: record.playbackPosition))."
        } catch {
            actionMessage = "Could not resume \(record.albumTitle): \(error.localizedDescription)"
        }
        #endif
    }

    #if !LOCAL_DEBUG_WITHOUT_MUSICKIT
    private func resumeWithMusicKit(_ record: AlbumProgressRecord) async throws -> Bool {
        var request = MusicCatalogResourceRequest<Album>(
            matching: \.id,
            equalTo: MusicItemID(record.albumIdentifier)
        )
        request.properties = [.tracks]

        guard let album = try await request.response().items.first else { return false }
        let expandedAlbum = try await album.with([.tracks])

        if let tracks = expandedAlbum.tracks, !tracks.isEmpty {
            let startTrack = tracks.first { $0.id.rawValue == record.trackIdentifier }
                ?? tracks.first { $0.trackNumber == record.currentTrackNumber }

            if let startTrack {
                musicKitPlayer.queue = ApplicationMusicPlayer.Queue(album: expandedAlbum, startingAt: startTrack)
            } else {
                musicKitPlayer.queue = ApplicationMusicPlayer.Queue(for: [expandedAlbum])
            }
        } else {
            musicKitPlayer.queue = ApplicationMusicPlayer.Queue(for: [expandedAlbum])
        }

        try await playAndSeekWithMusicKit(to: record.playbackPosition)
        return true
    }

    private func playAndSeekWithMusicKit(to position: TimeInterval) async throws {
        try await musicKitPlayer.prepareToPlay()
        try await musicKitPlayer.play()

        // Native macOS MusicKit does not expose SystemMusicPlayer in this SDK, so
        // this path uses ApplicationMusicPlayer. Exact seeking can still be
        // timing-sensitive; set playbackTime after playback starts and retry once.
        musicKitPlayer.playbackTime = max(position, 0)
        try? await Task.sleep(for: .milliseconds(350))
        musicKitPlayer.playbackTime = max(position, 0)
    }
    #endif

    private func resumeTarget(
        for record: AlbumProgressRecord,
        persistentID: String?,
        albumTrackURLs: [URL]
    ) -> MusicAppResumeTarget {
        MusicAppResumeTarget(
            persistentID: persistentID,
            trackID: record.musicAppTrackID,
            sourceID: record.musicAppSourceID,
            appleMusicTrackURL: record.appleMusicTrackURL,
            appleMusicAlbumURL: record.appleMusicAlbumURL,
            appleMusicAlbumTrackURLs: albumTrackURLs,
            albumTitle: record.albumTitle,
            artistName: record.artistName,
            trackTitle: record.currentTrackTitle,
            trackNumber: record.currentTrackNumber,
            playbackPosition: record.playbackPosition
        )
    }

    private func musicAppAlbumCacheKey(for currentTrack: MusicAppCurrentTrack) -> String {
        "\(normalized(currentTrack.artistName))|\(normalized(currentTrack.albumTitle))|\(currentTrack.totalTrackCount ?? 0)"
    }

    private func stableMusicAppAlbumIdentifier(
        for currentTrack: MusicAppCurrentTrack,
        tracks: [AlbumTrackInfo]
    ) -> String {
        if let firstTrackID = tracks.first?.id {
            return "musicapp:\(firstTrackID)|\(normalized(currentTrack.albumTitle))"
        }

        return "musicapp:\(musicAppAlbumCacheKey(for: currentTrack))"
    }

    private func musicAppPersistentID(from identifier: String) -> String? {
        guard identifier.hasPrefix("musicapp:") else { return nil }
        let trimmed = String(identifier.dropFirst("musicapp:".count))
        return trimmed.split(separator: "|").first.map(String.init)
    }

    private func musicAppPersistentID(for record: AlbumProgressRecord) -> String? {
        if let persistentID = record.musicAppPersistentID, !persistentID.isEmpty {
            return persistentID
        }

        if let persistentID = musicAppPersistentID(from: record.trackIdentifier), !persistentID.isEmpty {
            return persistentID
        }

        // Records saved before musicAppPersistentID existed used the Music.app
        // persistent id directly as trackIdentifier. Keep those records resumable.
        if looksLikeMusicAppPersistentID(record.trackIdentifier) {
            return record.trackIdentifier
        }

        return nil
    }

    private func looksLikeMusicAppPersistentID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        return trimmed.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character.lowercased())
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func artistNamesAreClose(_ left: String, _ right: String) -> Bool {
        let normalizedLeft = normalized(left)
        let normalizedRight = normalized(right)
        return normalizedLeft == normalizedRight
            || normalizedLeft.contains(normalizedRight)
            || normalizedRight.contains(normalizedLeft)
    }
}

private struct CatalogAlbumMetadata {
    let albumIdentifier: String
    let albumTitle: String
    let artistName: String
    let artworkURL: URL?
    let trackCount: Int?
    let tracks: [AlbumTrackInfo]
}

private struct AppleMusicLinkMetadata {
    let trackURL: URL?
    let albumURL: URL?
    let collectionID: Int64?
    let trackID: Int64?
}

private struct AppleMusicSearchResponse: Decodable {
    let results: [Result]

    struct Result: Decodable {
        let artistName: String
        let collectionName: String
        let trackName: String
        let collectionID: Int64?
        let trackID: Int64?
        let trackNumber: Int?
        let trackViewURL: String?
        let collectionViewURL: String?

        private enum CodingKeys: String, CodingKey {
            case artistName
            case collectionName
            case trackName
            case collectionID = "collectionId"
            case trackID = "trackId"
            case trackNumber
            case trackViewURL = "trackViewUrl"
            case collectionViewURL = "collectionViewUrl"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            artistName = try container.decodeIfPresent(String.self, forKey: .artistName) ?? ""
            collectionName = try container.decodeIfPresent(String.self, forKey: .collectionName) ?? ""
            trackName = try container.decodeIfPresent(String.self, forKey: .trackName) ?? ""
            collectionID = try container.decodeIfPresent(Int64.self, forKey: .collectionID)
            trackID = try container.decodeIfPresent(Int64.self, forKey: .trackID)
            trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
            trackViewURL = try container.decodeIfPresent(String.self, forKey: .trackViewURL)
            collectionViewURL = try container.decodeIfPresent(String.self, forKey: .collectionViewURL)
        }
    }
}

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}
