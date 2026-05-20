import Foundation

/// Abstracts a single playable audio source. Implementations own all transport state
/// for one stream; `StreamPlayer` instantiates a new source whenever the user switches
/// stream and disposes the old one.
protocol StreamSource: AnyObject {
    var state: PlayerState { get }
    var onStateChange: ((PlayerState) -> Void)? { get set }
    var volume: Float { get set }
    func play()
    func stop()
    func dispose()
}
