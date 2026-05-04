import AppKit
import Foundation

struct MusicAppCurrentTrack {
    let persistentID: String
    let trackID: Int?
    let sourceID: Int?
    let songTitle: String
    let artistName: String
    let albumTitle: String
    let trackNumber: Int?
    let totalTrackCount: Int?
    let playbackPosition: TimeInterval
    let songDuration: TimeInterval?
    let playbackState: PlaybackState
}

struct MusicAppResumeTarget {
    let persistentID: String?
    let trackID: Int?
    let sourceID: Int?
    let appleMusicTrackURL: URL?
    let appleMusicAlbumURL: URL?
    let appleMusicAlbumTrackURLs: [URL]
    let albumTitle: String
    let artistName: String
    let trackTitle: String
    let trackNumber: Int?
    let playbackPosition: TimeInterval
}

enum MusicAppBridgeError: LocalizedError {
    case automationDenied
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            "AlbumMark needs permission to communicate with Music.app. Enable it in System Settings > Privacy & Security > Automation."
        case .scriptFailed(let message):
            message
        }
    }
}

final class MusicAppBridge {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func currentTrack() throws -> MusicAppCurrentTrack? {
        guard musicIsRunning else { return nil }

        let script = """
        tell application id "com.apple.Music"
            if player state is stopped then return {}

            set currentTrackValue to current track
            set persistentIDValue to persistent ID of currentTrackValue as string
            set trackIDValue to 0
            set sourceIDValue to 0

            try
                set trackIDValue to id of currentTrackValue as integer
            end try

            try
                set sourceIDValue to id of container of currentTrackValue as integer
            end try

            set titleValue to name of currentTrackValue as string
            set albumValue to album of currentTrackValue as string
            set artistValue to artist of currentTrackValue as string

            try
                set albumArtistValue to album artist of currentTrackValue as string
                if albumArtistValue is not "" then set artistValue to albumArtistValue
            end try

            set trackNumberValue to 0
            try
                set trackNumberValue to track number of currentTrackValue as integer
            end try

            set trackCountValue to 0
            try
                set trackCountValue to track count of currentTrackValue as integer
            end try

            set positionValue to 0
            try
                set positionValue to player position as real
            end try

            set durationValue to 0
            try
                set durationValue to duration of currentTrackValue as real
            end try

            set stateValue to player state as string

            return {persistentIDValue, trackIDValue, sourceIDValue, titleValue, artistValue, albumValue, trackNumberValue, trackCountValue, positionValue, durationValue, stateValue}
        end tell
        """

        let descriptor = try execute(script)
        guard descriptor.numberOfItems > 0 else { return nil }

        let persistentID = descriptor.string(at: 1)
        let title = descriptor.string(at: 4)
        let artist = descriptor.string(at: 5)
        let album = descriptor.string(at: 6)

        guard !persistentID.isEmpty, !title.isEmpty, !album.isEmpty else { return nil }

        return MusicAppCurrentTrack(
            persistentID: persistentID,
            trackID: descriptor.positiveInt(at: 2),
            sourceID: descriptor.positiveInt(at: 3),
            songTitle: title,
            artistName: artist,
            albumTitle: album,
            trackNumber: descriptor.positiveInt(at: 7),
            totalTrackCount: descriptor.positiveInt(at: 8),
            playbackPosition: descriptor.double(at: 9),
            songDuration: descriptor.positiveDouble(at: 10),
            playbackState: PlaybackState(musicAppState: descriptor.string(at: 11))
        )
    }

    func currentTrackArtworkURL(persistentID: String, artworkDirectory: URL) throws -> URL? {
        guard musicIsRunning else { return nil }

        try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)

        let safeID = safeFilenameComponent(persistentID)
        let jpegURL = artworkDirectory.appendingPathComponent(safeID).appendingPathExtension("jpg")
        let pngURL = artworkDirectory.appendingPathComponent(safeID).appendingPathExtension("png")

        if fileManager.fileExists(atPath: jpegURL.path) {
            return jpegURL
        }

        if fileManager.fileExists(atPath: pngURL.path) {
            return pngURL
        }

        let script = artworkScript(
            persistentID: persistentID,
            jpegPath: jpegURL.path,
            pngPath: pngURL.path
        )
        let descriptor = try execute(script)
        let artworkPath = descriptor.stringValue ?? ""

        guard !artworkPath.isEmpty, fileManager.fileExists(atPath: artworkPath) else {
            return nil
        }

        return URL(fileURLWithPath: artworkPath)
    }

    func artworkScript(persistentID: String, jpegPath: String, pngPath: String) -> String {
        """
        tell application id "com.apple.Music"
            if player state is stopped then return ""

            set currentTrackValue to current track
            set currentPersistentID to persistent ID of currentTrackValue as string
            if currentPersistentID is not \(appleScriptString(persistentID)) then return ""
            if (count of (artworks of currentTrackValue)) is 0 then return ""

            set artworkValue to artwork 1 of currentTrackValue
            set artworkFormatValue to ""
            try
                set artworkFormatValue to format of artworkValue as string
            end try

            set outputPath to \(appleScriptString(jpegPath))
            if artworkFormatValue contains "PNG" then set outputPath to \(appleScriptString(pngPath))
            set artworkData to raw data of artworkValue
        end tell

        set outputFile to POSIX file outputPath
        set fileRef to open for access outputFile with write permission
        try
            set eof fileRef to 0
            write artworkData to fileRef
            close access fileRef
        on error errorMessage
            try
                close access fileRef
            end try
            error errorMessage
        end try

        return outputPath
        """
    }

    func albumTracks(albumTitle: String, artistName: String, totalTrackCount: Int?) throws -> [AlbumTrackInfo] {
        guard musicIsRunning else { return [] }

        let script = """
        tell application id "com.apple.Music"
            set albumNameValue to \(appleScriptString(albumTitle))
            set artistNameValue to \(appleScriptString(artistName))
            set expectedTrackCount to \(totalTrackCount ?? 0)
            set foundTracks to {}

            try
                set candidateTracks to (tracks of library playlist 1 whose album is albumNameValue and album artist is artistNameValue)
                if (count of candidateTracks) is 0 then
                    set candidateTracks to (tracks of library playlist 1 whose album is albumNameValue and artist is artistNameValue)
                end if

                repeat with candidateTrack in candidateTracks
                    set candidateTrackCount to 0
                    try
                        set candidateTrackCount to track count of candidateTrack as integer
                    end try

                    if expectedTrackCount is 0 or candidateTrackCount is expectedTrackCount then
                        set persistentIDValue to persistent ID of candidateTrack as string
                        set titleValue to name of candidateTrack as string
                        set artistValue to artist of candidateTrack as string
                        set trackNumberValue to 0
                        set durationValue to 0

                        try
                            set trackNumberValue to track number of candidateTrack as integer
                        end try

                        try
                            set durationValue to duration of candidateTrack as real
                        end try

                        set end of foundTracks to {persistentIDValue, titleValue, artistValue, trackNumberValue, durationValue}
                    end if
                end repeat
            end try

            return foundTracks
        end tell
        """

        let descriptor = try execute(script)
        guard descriptor.numberOfItems > 0 else { return [] }

        var tracks: [AlbumTrackInfo] = []
        var seenIDs = Set<String>()

        for index in 1...descriptor.numberOfItems {
            guard let item = descriptor.atIndex(index) else { continue }
            let id = item.string(at: 1)
            guard !id.isEmpty, !seenIDs.contains(id) else { continue }
            seenIDs.insert(id)

            tracks.append(
                AlbumTrackInfo(
                    id: id,
                    title: item.string(at: 2),
                    artistName: item.string(at: 3),
                    trackNumber: item.positiveInt(at: 4),
                    duration: item.positiveDouble(at: 5)
                )
            )
        }

        return tracks.sorted { left, right in
            switch (left.trackNumber, right.trackNumber) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
        }
    }

    func resume(_ target: MusicAppResumeTarget) throws {
        if !musicIsRunning {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Music.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
            waitForMusicToLaunch()
        }

        let script = resumeScript(for: target)
        _ = try execute(script)
    }

    func resumeScript(for target: MusicAppResumeTarget) -> String {
        let persistentID = target.persistentID ?? ""
        let trackID = target.trackID ?? 0
        let sourceID = target.sourceID ?? 0
        let trackNumber = target.trackNumber ?? 0
        let playbackPosition = max(target.playbackPosition, 0)

        return """
        tell application id "com.apple.Music"
            set targetPersistentID to \(appleScriptString(persistentID))
            set targetAlbum to \(appleScriptString(target.albumTitle))
            set targetArtist to \(appleScriptString(target.artistName))
            set targetTitle to \(appleScriptString(target.trackTitle))
            set targetMusicTrackID to \(trackID)
            set targetSourceID to \(sourceID)
            set targetTrackNumber to \(trackNumber)
            set targetTrack to missing value

            if targetMusicTrackID is not 0 and targetSourceID is not 0 then
                try
                    set directTrack to track id targetMusicTrackID of source id targetSourceID
                    if my trackMatches(directTrack, targetAlbum, targetArtist, targetTitle, targetTrackNumber) then
                        set targetTrack to directTrack
                    end if
                end try
            end if

            if targetPersistentID is not "" then
                try
                    set idMatches to (tracks of library playlist 1 whose persistent ID is targetPersistentID)
                    repeat with candidateTrack in idMatches
                        if my trackMatches(candidateTrack, targetAlbum, targetArtist, targetTitle, targetTrackNumber) then
                            set targetTrack to candidateTrack
                            exit repeat
                        end if
                    end repeat
                end try
            end if

            if targetTrack is missing value then
                try
                    set titleMatches to (search library playlist 1 for targetTitle only songs)
                    repeat with candidateTrack in titleMatches
                        if my trackMatches(candidateTrack, targetAlbum, targetArtist, targetTitle, targetTrackNumber) then
                            set targetTrack to candidateTrack
                            exit repeat
                        end if
                    end repeat
                end try
            end if

            if targetTrack is missing value then
                try
                    set albumMatches to (tracks of library playlist 1 whose album is targetAlbum and album artist is targetArtist)
                    if (count of albumMatches) is 0 then set albumMatches to (tracks of library playlist 1 whose album is targetAlbum and artist is targetArtist)

                    repeat with candidateTrack in albumMatches
                        if my trackMatches(candidateTrack, targetAlbum, targetArtist, targetTitle, targetTrackNumber) then
                            set targetTrack to candidateTrack
                            exit repeat
                        end if
                    end repeat
                end try
            end if

            if targetTrack is missing value then error "Saved track “" & targetTitle & "” from “" & targetAlbum & "” was not found in Music.app. AlbumMark will not resume the currently playing album as a fallback."

            set albumQueue to my albumQueueStartingAt(targetAlbum, targetArtist, targetTrackNumber)
            if (count of albumQueue) is greater than 1 then
                try
                    set queuePlaylist to my rebuildAlbumMarkQueue(albumQueue)
                    play queuePlaylist
                on error
                    play targetTrack
                end try
            else
                play targetTrack
            end if

            delay 1.4
            set player position to \(playbackPosition)
            delay 0.25
            set player position to \(playbackPosition)
            return persistent ID of targetTrack as string
        end tell

        on trackMatches(candidateTrack, targetAlbum, targetArtist, targetTitle, targetTrackNumber)
            tell application id "com.apple.Music"
                set candidateTitle to ""
                set candidateAlbum to ""
                set candidateArtist to ""
                set candidateAlbumArtist to ""
                set candidateTrackNumber to 0

                try
                    set candidateTitle to name of candidateTrack as string
                end try
                try
                    set candidateAlbum to album of candidateTrack as string
                end try
                try
                    set candidateArtist to artist of candidateTrack as string
                end try
                try
                    set candidateAlbumArtist to album artist of candidateTrack as string
                end try
                try
                    set candidateTrackNumber to track number of candidateTrack as integer
                end try
            end tell

            if candidateAlbum is not targetAlbum then return false
            if candidateArtist is not targetArtist and candidateAlbumArtist is not targetArtist then return false
            if targetTrackNumber is not 0 and candidateTrackNumber is not targetTrackNumber then return false
            if candidateTitle is not targetTitle then return false

            return true
        end trackMatches

        on albumQueueStartingAt(targetAlbum, targetArtist, targetTrackNumber)
            if targetTrackNumber is 0 then return {}

            tell application id "com.apple.Music"
                set candidateTracks to {}
                try
                    set candidateTracks to (tracks of library playlist 1 whose album is targetAlbum and album artist is targetArtist)
                end try

                if (count of candidateTracks) is 0 then
                    try
                        set candidateTracks to (tracks of library playlist 1 whose album is targetAlbum and artist is targetArtist)
                    end try
                end if

                set queuedTracks to {}
                repeat with displayTrackNumber from targetTrackNumber to 200
                    repeat with candidateTrack in candidateTracks
                        set candidateTrackNumber to 0
                        try
                            set candidateTrackNumber to track number of candidateTrack as integer
                        end try

                        if candidateTrackNumber is displayTrackNumber then
                            set end of queuedTracks to candidateTrack
                            exit repeat
                        end if
                    end repeat
                end repeat

                return queuedTracks
            end tell
        end albumQueueStartingAt

        on rebuildAlbumMarkQueue(queuedTracks)
            tell application id "com.apple.Music"
                -- Music.app scripting can play an album-like queue reliably when
                -- it is represented as a playlist. AlbumMark owns this temporary
                -- playlist and replaces its contents on each resume.
                set queueName to "AlbumMark Resume Queue"
                set queuePlaylist to missing value

                try
                    set queuePlaylist to user playlist queueName
                    delete every track of queuePlaylist
                on error
                    set queuePlaylist to make new user playlist with properties {name:queueName}
                end try

                repeat with queuedTrack in queuedTracks
                    try
                        duplicate queuedTrack to queuePlaylist
                    end try
                end repeat

                return queuePlaylist
            end tell
        end rebuildAlbumMarkQueue

        """
    }

    private var musicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == "com.apple.Music"
        }
    }

    private func waitForMusicToLaunch() {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if musicIsRunning { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw MusicAppBridgeError.scriptFailed("AppleScript could not be compiled.")
        }

        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
            if errorNumber == -1743 {
                throw MusicAppBridgeError.automationDenied
            }

            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Music.app scripting failed."
            throw MusicAppBridgeError.scriptFailed(message)
        }

        return descriptor
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func safeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filename = value.unicodeScalars
            .map { scalar in allowed.contains(scalar) ? String(scalar) : "_" }
            .joined()
        return filename.isEmpty ? UUID().uuidString : filename
    }
}

private extension PlaybackState {
    init(musicAppState: String) {
        switch musicAppState.lowercased() {
        case "playing":
            self = .playing
        case "paused":
            self = .paused
        case "stopped":
            self = .stopped
        case "fast forwarding":
            self = .seekingForward
        case "rewinding":
            self = .seekingBackward
        default:
            self = .unknown
        }
    }
}

private extension NSAppleEventDescriptor {
    func string(at index: Int) -> String {
        atIndex(index)?.stringValue ?? ""
    }

    func positiveInt(at index: Int) -> Int? {
        let value = atIndex(index)?.int32Value ?? 0
        return value > 0 ? Int(value) : nil
    }

    func double(at index: Int) -> Double {
        atIndex(index)?.doubleValue ?? 0
    }

    func positiveDouble(at index: Int) -> Double? {
        let value = double(at: index)
        return value > 0 ? value : nil
    }
}
