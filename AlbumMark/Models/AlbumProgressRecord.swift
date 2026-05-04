import Foundation

struct AlbumProgressRecord: Codable, Equatable, Identifiable {
    var id: String { albumIdentifier }

    var albumIdentifier: String
    var albumTitle: String
    var artistName: String
    var artworkURLString: String?
    var appleMusicTrackURLString: String?
    var appleMusicAlbumURLString: String?
    var appleMusicCollectionID: Int64?
    var appleMusicCatalogTrackID: Int64?
    var currentTrackTitle: String
    var currentTrackNumber: Int?
    var totalTrackCount: Int?
    var trackIdentifier: String
    var musicAppPersistentID: String?
    var musicAppTrackID: Int?
    var musicAppSourceID: Int?
    var playbackPosition: TimeInterval
    var trackDuration: TimeInterval?
    var albumProgressPercentage: Double
    var lastPlayedAt: Date
    var isFinished: Bool

    var artworkURL: URL? {
        guard let artworkURLString else { return nil }
        return URL(string: artworkURLString)
    }

    var appleMusicTrackURL: URL? {
        guard let appleMusicTrackURLString else { return nil }
        return URL(string: appleMusicTrackURLString)
    }

    var appleMusicAlbumURL: URL? {
        guard let appleMusicAlbumURLString else { return nil }
        return URL(string: appleMusicAlbumURLString)
    }

    var progressFraction: Double {
        min(max(albumProgressPercentage, 0), 1)
    }

    var trackStatus: String {
        if let currentTrackNumber, let totalTrackCount {
            return "Track \(currentTrackNumber) of \(totalTrackCount)"
        }

        if let currentTrackNumber {
            return "Track \(currentTrackNumber)"
        }

        return "Current track"
    }

    static func make(from snapshot: NowPlayingSnapshot, progress: AlbumProgressResult) -> AlbumProgressRecord {
        AlbumProgressRecord(
            albumIdentifier: snapshot.albumIdentifier,
            albumTitle: snapshot.albumTitle,
            artistName: snapshot.artistName,
            artworkURLString: snapshot.artworkURL?.absoluteString,
            appleMusicTrackURLString: snapshot.appleMusicTrackURL?.absoluteString,
            appleMusicAlbumURLString: snapshot.appleMusicAlbumURL?.absoluteString,
            appleMusicCollectionID: snapshot.appleMusicCollectionID,
            appleMusicCatalogTrackID: snapshot.appleMusicCatalogTrackID,
            currentTrackTitle: snapshot.songTitle,
            currentTrackNumber: snapshot.trackNumber,
            totalTrackCount: snapshot.totalTrackCount,
            trackIdentifier: snapshot.trackIdentifier,
            musicAppPersistentID: snapshot.musicAppPersistentID,
            musicAppTrackID: snapshot.musicAppTrackID,
            musicAppSourceID: snapshot.musicAppSourceID,
            playbackPosition: snapshot.playbackPosition,
            trackDuration: snapshot.songDuration,
            albumProgressPercentage: progress.percentage,
            lastPlayedAt: snapshot.capturedAt,
            isFinished: false
        )
    }
}
