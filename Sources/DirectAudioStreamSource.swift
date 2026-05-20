import AVFoundation
import Foundation
import os

final class DirectAudioStreamSource: NSObject, StreamSource {
    private static let logger = Logger(subsystem: "com.johncioni.codefm", category: "DirectAudio")
    private static let bufferingHangTimeout: TimeInterval = 15

    private let url: URL

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeControlObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var resolveTask: URLSessionDataTask?
    private var bufferTimer: Timer?

    var onStateChange: ((PlayerState) -> Void)?

    private(set) var state: PlayerState = .stopped {
        didSet { if oldValue != state { onStateChange?(state) } }
    }

    var volume: Float = 1.0 {
        didSet { player?.volume = Settings.clampedVolume(volume) }
    }

    init(url: URL) {
        self.url = url
        super.init()
    }

    deinit { dispose() }

    func play() {
        state = .loading
        if isPlaylistURL(url) {
            resolveAndPlay()
        } else {
            startPlayback(with: url)
        }
    }

    func stop() {
        player?.pause()
        cancelBufferTimer()
        state = .stopped
    }

    func dispose() {
        resolveTask?.cancel()
        resolveTask = nil
        timeControlObservation?.invalidate()
        statusObservation?.invalidate()
        timeControlObservation = nil
        statusObservation = nil
        cancelBufferTimer()
        player?.pause()
        player = nil
        playerItem = nil
    }

    // MARK: - Playlist resolution

    private func isPlaylistURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".pls") || path.hasSuffix(".m3u") || path.hasSuffix(".m3u8")
    }

    private func resolveAndPlay() {
        resolveTask?.cancel()
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            self.resolveTask = nil

            if let error {
                Self.logger.warning("Playlist fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self.state = .offline }
                return
            }
            guard
                let data,
                let body = String(data: data, encoding: .utf8),
                let resolved = PLSParser.firstStreamURL(in: body)
            else {
                Self.logger.warning("Could not parse playlist from \(self.url)")
                DispatchQueue.main.async { self.state = .offline }
                return
            }

            DispatchQueue.main.async { self.startPlayback(with: resolved) }
        }
        self.resolveTask = task
        task.resume()
    }

    // MARK: - AVPlayer

    private func startPlayback(with url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = Settings.clampedVolume(volume)
        self.player = player
        self.playerItem = item

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async { self?.handleTimeControlChange(player.timeControlStatus) }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .failed {
                    self?.state = .offline
                }
            }
        }

        player.play()
    }

    private func handleTimeControlChange(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            cancelBufferTimer()
            state = .playing
        case .waitingToPlayAtSpecifiedRate:
            startBufferTimer()
            state = .loading
        case .paused:
            cancelBufferTimer()
            if state != .stopped { state = .stopped }
        @unknown default: break
        }
    }

    private func startBufferTimer() {
        cancelBufferTimer()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: Self.bufferingHangTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.bufferTimer = nil
            if self.state == .loading { self.state = .offline }
        }
    }

    private func cancelBufferTimer() {
        bufferTimer?.invalidate()
        bufferTimer = nil
    }
}

enum PLSParser {
    /// Returns the first usable stream URL from a PLS or M3U playlist body.
    static func firstStreamURL(in body: String) -> URL? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("[playlist]") || trimmed.lowercased().contains("file1=") {
            for line in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
                let s = line.trimmingCharacters(in: .whitespaces)
                if let range = s.range(of: "^File\\d+=", options: .regularExpression) {
                    let urlString = String(s[range.upperBound...])
                    if let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
                        return url
                    }
                }
            }
        }
        // Treat as M3U / plain list: first non-comment, non-empty line that parses as URL.
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            if let url = URL(string: s), url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        return nil
    }
}
