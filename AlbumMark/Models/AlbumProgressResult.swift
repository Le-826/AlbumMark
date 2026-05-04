import Foundation

struct AlbumProgressResult: Equatable {
    enum Method: String, Equatable {
        case fullAlbumDurations
        case trackCountAndSongProgress
        case currentTrackOnly
        case unavailable
    }

    let percentage: Double
    let method: Method
    let statusLine: String
    let resumeLine: String
    let totalAlbumDuration: TimeInterval?

    var percentageText: String {
        "\(Int((percentage * 100).rounded()))% complete"
    }
}
