import Foundation

enum PlaybackState: String, Codable, Equatable {
    case stopped
    case playing
    case paused
    case interrupted
    case seekingForward
    case seekingBackward
    case unknown

    var displayName: String {
        switch self {
        case .stopped:
            "Stopped"
        case .playing:
            "Playing"
        case .paused:
            "Paused"
        case .interrupted:
            "Interrupted"
        case .seekingForward:
            "Seeking"
        case .seekingBackward:
            "Seeking"
        case .unknown:
            "Unknown"
        }
    }
}
