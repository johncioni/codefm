import AppKit
import Foundation

/// Coordinator that owns the currently-selected `Stream` and its concrete `StreamSource`.
/// All UI talks to `StreamPlayer`; switching streams disposes the old source and creates
/// the appropriate concrete one (YouTube vs direct audio).
final class StreamPlayer {
    var onStateChange: ((PlayerState) -> Void)?
    var onCurrentStreamChange: ((Stream) -> Void)?

    private(set) var currentStream: Stream
    private var currentSource: StreamSource?

    var volume: Float = 1.0 {
        didSet {
            let clamped = Settings.clampedVolume(volume)
            currentSource?.volume = clamped
            if volume != clamped { volume = clamped }
        }
    }

    var state: PlayerState { currentSource?.state ?? .stopped }

    init(initialStream: Stream) {
        self.currentStream = initialStream
        rebuildSource(for: initialStream)
    }

    /// Warm up the source so the first user click feels instant. Sources that have
    /// no meaningful work to do before `play()` default to a no-op.
    func prefetch() {
        currentSource?.prefetch()
    }

    func togglePlayback() {
        switch state {
        case .stopped, .offline: currentSource?.play()
        case .loading: break
        case .playing: currentSource?.stop()
        }
    }

    func stop() { currentSource?.stop() }

    /// Switch to a new stream. Disposes the old source. If the player was playing,
    /// starts the new source playing immediately.
    func load(stream: Stream, autoplay: Bool? = nil) {
        let wasPlaying = (state == .playing || state == .loading)
        let shouldAutoplay = autoplay ?? wasPlaying

        currentStream = stream
        rebuildSource(for: stream)
        onCurrentStreamChange?(stream)

        if shouldAutoplay { currentSource?.play() }
    }

    private func rebuildSource(for stream: Stream) {
        currentSource?.dispose()
        let source: StreamSource
        switch stream.type {
        case let .youtubeLive(videoId, channelLiveUrl):
            source = YouTubeStreamSource(videoId: videoId, channelLiveUrl: channelLiveUrl)
        case let .directAudio(url):
            source = DirectAudioStreamSource(url: url)
        }
        source.volume = Settings.clampedVolume(volume)
        source.onStateChange = { [weak self] newState in
            self?.onStateChange?(newState)
        }
        currentSource = source
    }
}
