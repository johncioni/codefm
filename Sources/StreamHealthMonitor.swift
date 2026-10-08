import Foundation
import os

/// In-memory tracker of which streams are currently unavailable.
/// - Proactive: probes every stream at launch (and on demand) over URLSession.
/// - Reactive: callers report runtime failures via `markUnavailable(_:)` and
///   recoveries via `markAvailable(_:)`.
/// Posts `.codeFMStreamHealthChanged` whenever the set changes so the menu and
/// Settings library refresh and a provisional random launch can replace an offline
/// station. Random picks consult known availability, with a fallback if all are offline.
final class StreamHealthMonitor {
    static let shared = StreamHealthMonitor()

    private let logger = Logger(subsystem: "com.johncioni.codefm", category: "StreamHealth")
    private let queue = DispatchQueue(label: "com.johncioni.codefm.streamhealth", attributes: .concurrent)
    private var unavailable: Set<String> = []
    // Latest definition checkAll saw for each station id.
    private var definitions: [String: StreamType] = [:]

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
    /// Records each station's definition so a probe of an older one still in flight is ignored.
    func checkAll(catalog: StreamCatalog) {
        queue.sync(flags: .barrier) {
            for stream in catalog.streams {
                definitions[stream.id] = stream.type
            }
        }
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
        case let .youtubeLive(videoId, channelLiveUrl, liveFallback):
            probeYouTube(stream: stream, videoId: videoId, channelLiveUrl: channelLiveUrl, liveFallback: liveFallback)
        case let .directAudio(url):
            probeDirectAudio(stream: stream, url: url)
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

    /// A channel's /live page can serve a past stream or upload, where
    /// isLiveContent alone would incorrectly read as a current broadcast.
    static func htmlShowsLiveBroadcast(_ html: String) -> Bool {
        html.contains(#""status":"OK""#) && html.contains(#""isLive":true"#)
    }

    private func probeYouTube(stream: Stream, videoId: String, channelLiveUrl: URL, liveFallback: Bool) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else {
            // Pinned videoId is malformed — use the channel only when allowed.
            if liveFallback {
                probeChannelLive(stream: stream, channelLiveUrl: channelLiveUrl)
            } else {
                applyResult(stream, available: false)
            }
            return
        }
        fetchIndicatesLive(url: url) { [weak self] live in
            guard let self else { return }
            if live {
                self.applyResult(stream, available: true)
            } else if liveFallback {
                // A stale/ended pinned video can recover through the channel's
                // current broadcast only when the catalog allows that fallback,
                // mirroring YouTubeStreamSource.resolveCurrentLiveVideoId.
                self.probeChannelLive(stream: stream, channelLiveUrl: channelLiveUrl)
            } else {
                self.applyResult(stream, available: false)
            }
        }
    }

    private func probeChannelLive(stream: Stream, channelLiveUrl: URL) {
        fetchIndicatesLive(url: channelLiveUrl, predicate: Self.htmlShowsLiveBroadcast) { [weak self] live in
            self?.applyResult(stream, available: live)
        }
    }

    /// Fetch `url` with the Safari UA and report whether its HTML indicates a live stream.
    private func fetchIndicatesLive(url: URL, predicate: @escaping (String) -> Bool = StreamHealthMonitor.htmlIndicatesLive, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let live = data
                .flatMap { String(data: $0, encoding: .utf8) }
                .map(predicate) ?? false
            completion(live)
        }.resume()
    }

    private func probeDirectAudio(stream: Stream, url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
                && (data.map { String(data: $0, encoding: .utf8)?.contains("File1=") ?? false } ?? false)
            self.applyResult(stream, available: ok)
        }.resume()
    }

    private func applyResult(_ stream: Stream, available: Bool) {
        let current = queue.sync { definitions[stream.id] }
        guard ProbeResultPolicy.shouldApply(probed: stream.type, current: current) else {
            logger.info("Ignored a probe of a replaced definition: \(stream.id, privacy: .public)")
            return
        }
        if available { markAvailable(stream.id) } else { markUnavailable(stream.id) }
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

/// Whether a finished probe may change a station's health. Health is kept
/// by station id, so a probe of a definition the catalog has since replaced
/// (a re-pinned video, say) must not overwrite the current one's result.
enum ProbeResultPolicy {
    static func shouldApply(probed: StreamType, current: StreamType?) -> Bool {
        current == nil || current == probed
    }
}
