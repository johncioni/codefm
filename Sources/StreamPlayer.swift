import AppKit
import Foundation

/// Coordinator that owns the currently-selected `Stream` and its concrete `StreamSource`.
/// All UI talks to `StreamPlayer`; switching streams disposes the old source and creates
/// the appropriate concrete one (YouTube vs direct audio).
final class StreamPlayer {
    var onStateChange: ((PlayerState) -> Void)?
    var onCurrentStreamChange: ((Stream) -> Void)?

    private(set) var currentStream: Stream
    private(set) var isPlaybackRequested = false
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
        case .stopped, .offline:
            isPlaybackRequested = true
            currentSource?.play()
        case .loading: break
        case .playing:
            isPlaybackRequested = false
            currentSource?.stop()
        }
    }

    func stop() {
        isPlaybackRequested = false
        currentSource?.stop()
    }

    /// Switch to a new stream. Disposes the old source. If the player was playing,
    /// starts the new source playing immediately.
    func load(stream: Stream, autoplay: Bool? = nil) {
        let wasPlaying = (state == .playing || state == .loading)
        let shouldAutoplay = autoplay ?? wasPlaying
        isPlaybackRequested = shouldAutoplay

        currentStream = stream
        rebuildSource(for: stream)
        onCurrentStreamChange?(stream)

        if shouldAutoplay { currentSource?.play() }
    }

    /// Apply a refreshed catalog entry for the loaded station. A new playback
    /// definition rebuilds the source and keeps the app's play request; other
    /// changes only replace the stream's details.
    func refresh(with stream: Stream) {
        guard stream.id == currentStream.id else { return }
        switch CatalogRefreshAction.decide(loaded: currentStream, refreshed: stream, isPlaybackRequested: isPlaybackRequested) {
        case .unchanged:
            break
        case .updateDetails:
            currentStream = stream
            onCurrentStreamChange?(stream)
        case let .reload(autoplay):
            load(stream: stream, autoplay: autoplay)
            if !autoplay { prefetch() }
        }
    }

    private func rebuildSource(for stream: Stream) {
        currentSource?.onStateChange = nil
        currentSource?.dispose()
        let source: StreamSource
        switch stream.type {
        case let .youtubeLive(videoId, channelLiveUrl, liveFallback):
            source = YouTubeStreamSource(videoId: videoId, channelLiveUrl: channelLiveUrl, liveFallback: liveFallback)
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

/// What a refreshed catalog entry for the loaded station means for the player.
/// `Stream ==` compares ids only, so the fields are compared here.
enum CatalogRefreshAction: Equatable {
    case unchanged, updateDetails
    case reload(autoplay: Bool)

    static func decide(loaded: Stream, refreshed: Stream, isPlaybackRequested: Bool) -> CatalogRefreshAction {
        if refreshed.type != loaded.type { return .reload(autoplay: isPlaybackRequested) }
        let sameDetails = refreshed.displayName == loaded.displayName
            && refreshed.subgenre == loaded.subgenre
            && refreshed.attribution == loaded.attribution
            && refreshed.description == loaded.description
            && refreshed.providerLabel == loaded.providerLabel
        return sameDetails ? .unchanged : .updateDetails
    }
}
