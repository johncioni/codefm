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
        case let .youtubeLive(videoId, _):
            probeYouTube(streamId: stream.id, videoId: videoId)
        case let .directAudio(url):
            probeDirectAudio(streamId: stream.id, url: url)
        }
    }

    private func probeYouTube(streamId: String, videoId: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else {
            applyResult(streamId, available: false)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            let isHealthy: Bool = {
                guard
                    let data,
                    let html = String(data: data, encoding: .utf8)
                else { return false }
                // Live streams report `"isLive":true` AND `"status":"OK"`. Recorded
                // videos that happen to be playable would have only the second; we
                // require both so we don't surface a non-live recording as healthy.
                return html.contains(#""status":"OK""#)
                    && (html.contains(#""isLive":true"#) || html.contains(#""isLiveContent":true"#))
            }()
            self.applyResult(streamId, available: isHealthy)
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
