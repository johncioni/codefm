import Foundation
import os

/// In-memory tracker of which streams are currently unavailable.
/// - Proactive: probes every stream at launch (and on demand) over URLSession.
/// - Reactive: callers report runtime failures via `markUnavailable(_:)` and
///   recoveries via `markAvailable(_:)`.
/// Posts `.codeFMStreamHealthChanged` whenever the set changes so UI surfaces
/// (menubar submenu, Settings library, random picker) can refresh.
final class StreamHealthMonitor {
    static let shared = StreamHealthMonitor()

    private let logger = Logger(subsystem: "com.johncioni.codefm", category: "StreamHealth")
    private let queue = DispatchQueue(label: "com.johncioni.codefm.streamhealth", attributes: .concurrent)
    private var unavailable: Set<String> = []

    /// User agent string used by all probes. Some YouTube edge servers serve a
    /// JS-less HTML body when the request looks like a bot, which trips our
    /// regex check; a real Safari UA avoids that.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private init() {}

    var unavailableIds: Set<String> {
        queue.sync { unavailable }
    }

    func isAvailable(_ stream: Stream) -> Bool {
        queue.sync { !unavailable.contains(stream.id) }
    }

    func available(in streams: [Stream]) -> [Stream] {
        let blocked = unavailableIds
        return streams.filter { !blocked.contains($0.id) }
    }

    func markUnavailable(_ id: String) {
        let didChange: Bool = queue.sync(flags: .barrier) {
            let inserted = unavailable.insert(id).inserted
            return inserted
        }
        if didChange {
            logger.info("Marked stream unavailable: \(id, privacy: .public)")
            postChange()
        }
    }

    func markAvailable(_ id: String) {
        let didChange: Bool = queue.sync(flags: .barrier) {
            unavailable.remove(id) != nil
        }
        if didChange {
            logger.info("Recovered stream: \(id, privacy: .public)")
            postChange()
        }
    }

    /// Probe every stream in the catalog. Each probe runs independently; the
    /// change notification fires at most once per stream as results come in.
    func checkAll(catalog: StreamCatalog) {
        for stream in catalog.streams {
            probe(stream)
        }
    }

    /// Re-probe a single stream — used by the Settings "Refresh availability" button.
    func recheck(_ stream: Stream) {
        probe(stream)
    }

    private func probe(_ stream: Stream) {
        switch stream.type {
        case let .youtubeLive(videoId, channelLiveUrl):
            probeYouTube(streamId: stream.id, videoId: videoId, channelLiveUrl: channelLiveUrl)
        case let .directAudio(url):
            probeDirectAudio(streamId: stream.id, url: url)
        }
    }

    /// True when a YouTube watch/live HTML body describes a currently-live,
    /// playable broadcast (`"status":"OK"`).
    ///
    /// `"isLive":true` is the authoritative "currently broadcasting" signal and
    /// wins outright. An explicit `"isLive":false` is an ended broadcast and is
    /// never live — even though YouTube keeps `"isLiveContent":true` on ended
    /// streams (it's a persistent classification, not a live flag). Without that
    /// guard a stale/rotated videoId reads as healthy and the channel-live
    /// fallback in `probeYouTube` never runs. Only when `isLive` is absent
    /// entirely do we fall back to `isLiveContent` — some edge responses omit
    /// `isLive` for an active broadcast.
    static func htmlIndicatesLive(_ html: String) -> Bool {
        guard html.contains(#""status":"OK""#) else { return false }
        if html.contains(#""isLive":true"#) { return true }
        if html.contains(#""isLive":false"#) { return false }
        return html.contains(#""isLiveContent":true"#)
    }

    private func probeYouTube(streamId: String, videoId: String, channelLiveUrl: URL) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else {
            // Pinned videoId is malformed — go straight to the channel's live endpoint.
            probeChannelLive(streamId: streamId, channelLiveUrl: channelLiveUrl)
            return
        }
        fetchIndicatesLive(url: url) { [weak self] live in
            guard let self else { return }
            if live {
                self.applyResult(streamId, available: true)
            } else {
                // The pinned videoId is stale/ended (a 24/7 channel rotates its
                // videoId on every restart, so the id baked into streams.json goes
                // dead). Before hiding the stream, check the channel's *current*
                // live broadcast — mirroring the playback-time recovery in
                // YouTubeStreamSource.resolveCurrentLiveVideoId. Without this, a
                // live-but-rotated stream disappears from the menu entirely.
                self.probeChannelLive(streamId: streamId, channelLiveUrl: channelLiveUrl)
            }
        }
    }

    private func probeChannelLive(streamId: String, channelLiveUrl: URL) {
        fetchIndicatesLive(url: channelLiveUrl) { [weak self] live in
            self?.applyResult(streamId, available: live)
        }
    }

    /// Fetch `url` with the Safari UA and report whether its HTML indicates a live stream.
    private func fetchIndicatesLive(url: URL, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let live = data
                .flatMap { String(data: $0, encoding: .utf8) }
                .map(Self.htmlIndicatesLive) ?? false
            completion(live)
        }.resume()
    }

    private func probeDirectAudio(streamId: String, url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
                && (data.map { String(data: $0, encoding: .utf8)?.contains("File1=") ?? false } ?? false)
            self.applyResult(streamId, available: ok)
        }.resume()
    }

    private func applyResult(_ id: String, available: Bool) {
        if available { markAvailable(id) } else { markUnavailable(id) }
    }

    private func postChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .codeFMStreamHealthChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let codeFMStreamHealthChanged = Notification.Name("CodeFMStreamHealthChanged")
}
