import Foundation

struct AlbumTrackInfo: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let artistName: String
    let trackNumber: Int?
    let duration: TimeInterval?
}
