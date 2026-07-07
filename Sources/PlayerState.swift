import AppKit

enum PlayerState {
    case stopped
    case loading
    case playing
    case offline

    var symbolName: String {
        switch self {
        case .stopped, .loading, .offline:
            return "play.circle.fill"
        case .playing:
            return "pause.circle.fill"
        }
    }

    var opacity: CGFloat {
        switch self {
        case .offline:
            return 0.3
        default:
            return 1.0
        }
    }

    func accessibilityLabel(streamName: String) -> String {
        switch self {
        case .stopped: return "\(streamName) — Stopped"
        case .loading: return "\(streamName) — Loading"
        case .playing: return "\(streamName) — Playing"
        case .offline: return "\(streamName) — Offline"
        }
    }
}
