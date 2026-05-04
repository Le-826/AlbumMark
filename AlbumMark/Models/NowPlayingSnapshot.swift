import Foundation

struct NowPlayingSnapshot: Identifiable {
    var id: String { trackIdentifier }

    let trackIdentifier: String
    let musicAppPersistentID: String?
    let musicAppTrackID: Int?
    let musicAppSourceID: Int?
    let albumIdentifier: String
    let songTitle: String
    let artistName: String
    let albumTitle: String
    let artworkURL: URL?
    let appleMusicTrackURL: URL?
    let appleMusicAlbumURL: URL?
    let appleMusicCollectionID: Int64?
    let appleMusicCatalogTrackID: Int64?
    let trackNumber: Int?
    let totalTrackCount: Int?
    let playbackPosition: TimeInterval
    let songDuration: TimeInterval?
    let playbackState: PlaybackState
    let albumTracks: [AlbumTrackInfo]
    let albumContextIsReliable: Bool
    let capturedAt: Date
}
