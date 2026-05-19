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

    var accessibilityLabel: String {
        switch self {
        case .stopped:
            return "Code FM — Stopped"
        case .loading:
            return "Code FM — Loading"
        case .playing:
            return "Code FM — Playing"
        case .offline:
            return "Code FM — Offline"
        }
    }
}
