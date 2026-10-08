import AppKit
import Foundation
import WebKit

final class YouTubeStreamSource: NSObject, StreamSource, WKNavigationDelegate, WKScriptMessageHandler {
    private static let playerOrigin = "https://codefm.app"
    private static let playbackStartTimeout: TimeInterval = 25
    private static let bufferingHangTimeout: TimeInterval = 15
    private static let playerSize: CGFloat = 200

    private var videoId: String
    private let channelLiveUrl: URL

    private var webView: WKWebView?
    private var playerWindow: NSWindow?
    private var isPlayerReady = false
    private var isPlayRequested = false
    private var shouldPlayWhenReady = false
    private var loadFailed = false
    private var fallbackGate = LiveFallbackGate()
    private var playbackTimer: Timer?
    private var bufferTimer: Timer?

    var volume: Float = 1.0 {
        didSet { sendVolumeToPlayer() }
    }

    var onStateChange: ((PlayerState) -> Void)?

    private(set) var state: PlayerState = .stopped {
        didSet { if oldValue != state { onStateChange?(state) } }
    }

    init(videoId: String, channelLiveUrl: URL) {
        self.videoId = videoId
        self.channelLiveUrl = channelLiveUrl
        super.init()
    }

    deinit { teardownWebView() }

    func play() {
        fallbackGate.reset()
        isPlayRequested = true
        if webView != nil && loadFailed { teardownWebView() }
        shouldPlayWhenReady = true
        state = .loading
        startPlaybackTimer()
        loadPlayerIfNeeded()
        if isPlayerReady { playLoadedPlayer() }
    }

    func stop() {
        isPlayRequested = false
        shouldPlayWhenReady = false
        cancelPlaybackTimer()
        cancelBufferTimer()
        guard webView != nil else { state = .stopped; return }
        evaluatePlayerScript("window.CodeFMPlayer && window.CodeFMPlayer.stop();")
        state = .stopped
    }

    func dispose() { teardownWebView() }

    /// Warm up the WebKit + iframe-API + cueVideoById pipeline without auto-playing.
    /// Called at launch when playAtStart is false so the first click feels instant.
    func prefetch() {
        guard webView == nil else { return }
        loadPlayerIfNeeded()
    }

    // MARK: - Internal player wiring (moved from old StreamPlayer.swift)

    private func playLoadedPlayer() {
        guard let webView else { return }
        shouldPlayWhenReady = false
        sendVolumeToPlayer()
        evaluatePlayerScript("window.CodeFMPlayer && window.CodeFMPlayer.play();") { [weak self] ok in
            guard let self, self.webView === webView, !ok else { return }
            self.loadFailed = true
            self.shouldPlayWhenReady = false
            self.cancelPlaybackTimer()
            self.cancelBufferTimer()
            guard self.state == .loading else { return }
            self.handleLoadFailure()
        }
    }

    private func loadPlayerIfNeeded() {
        guard webView == nil else { return }
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(self), name: "codeFM")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let playerFrame = NSRect(x: 0, y: 0, width: Self.playerSize, height: Self.playerSize)
        let webView = WKWebView(frame: playerFrame, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.playerSize, height: Self.playerSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = webView
        window.orderFront(nil)
        playerWindow = window

        webView.loadHTMLString(playerHTML(), baseURL: URL(string: Self.playerOrigin))
    }

    private func handleLoadFailure() {
        switch fallbackGate.failure() {
        case .ignore:
            return
        case .goOffline:
            state = .offline
        case let .resolve(token):
            resolveCurrentLiveVideoId { [weak self] newId in
                guard let self, self.fallbackGate.complete(token: token) else { return }
                if let newId, newId != self.videoId {
                    // Reload the iframe player with the resolved videoId so our
                    // CodeFMPlayer JS shim is still in place.
                    self.videoId = newId
                    self.loadFailed = false
                    self.isPlayerReady = false
                    self.cancelPlaybackTimer()
                    self.cancelBufferTimer()
                    self.teardownWebView()
                    if self.isPlayRequested {
                        self.shouldPlayWhenReady = true
                        self.state = .loading
                        self.startPlaybackTimer()
                    } else {
                        self.shouldPlayWhenReady = false
                        // A silent reload never reaches "playing", so keep the fallback available for the next play attempt.
                        self.fallbackGate.rearm()
                    }
                    self.loadPlayerIfNeeded()
                } else {
                    self.state = .offline
                }
            }
        }
    }

    /// Fetch the channel/live page and extract the currently-broadcasting videoId.
    /// Lightweight regex over the HTML — avoids loading the watch page in WKWebView
    /// (which would lose our CodeFMPlayer JS shim).
    private func resolveCurrentLiveVideoId(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: channelLiveUrl)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let resolved: String? = {
                guard
                    let data,
                    let html = String(data: data, encoding: .utf8)
                else { return nil }
                // The current live videoId appears as `"videoId":"XXXXXXXXXXX"` in
                // the YouTube watch player's initial data blob.
                let pattern = #""videoId":"([A-Za-z0-9_-]{11})""#
                guard
                    let regex = try? NSRegularExpression(pattern: pattern),
                    let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                    let range = Range(match.range(at: 1), in: html)
                else { return nil }
                return String(html[range])
            }()
            DispatchQueue.main.async { completion(resolved) }
        }.resume()
    }

    private func startPlaybackTimer() {
        cancelPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: Self.playbackStartTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.playbackTimer = nil
            guard self.state == .loading else { return }
            if !self.isPlayerReady { self.loadFailed = true }
            self.shouldPlayWhenReady = false
            self.handleLoadFailure()
        }
    }

    private func startBufferTimer() {
        cancelBufferTimer()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: Self.bufferingHangTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.bufferTimer = nil
            guard self.state == .playing else { return }
            self.loadFailed = true
            self.handleLoadFailure()
        }
    }

    private func cancelBufferTimer() { bufferTimer?.invalidate(); bufferTimer = nil }
    private func cancelPlaybackTimer() { playbackTimer?.invalidate(); playbackTimer = nil }

    private func teardownWebView() {
        cancelPlaybackTimer()
        cancelBufferTimer()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "codeFM")
        playerWindow?.orderOut(nil)
        playerWindow?.contentView = nil
        webView = nil
        playerWindow = nil
        isPlayerReady = false
        loadFailed = false
    }

    private func sendVolumeToPlayer() {
        guard webView != nil else { return }
        let percentage = Int((Settings.clampedVolume(volume) * 100).rounded())
        evaluatePlayerScript("window.CodeFMPlayer && window.CodeFMPlayer.setVolume(\(percentage));")
    }

    private func evaluatePlayerScript(_ script: String, completion: ((Bool) -> Void)? = nil) {
        webView?.evaluateJavaScript(script) { _, error in completion?(error == nil) }
    }

    private func handlePlayerMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            guard state != .offline else { return }
            isPlayerReady = true
            loadFailed = false
            sendVolumeToPlayer()
            if shouldPlayWhenReady { playLoadedPlayer() }
        case "state":
            guard let stateName = message["state"] as? String else { return }
            updateState(named: stateName)
        case "error", "ended":
            isPlayerReady = false
            loadFailed = true
            handleLoadFailure()
        default: break
        }
    }

    private func updateState(named stateName: String) {
        switch stateName {
        case "playing":
            cancelPlaybackTimer()
            cancelBufferTimer()
            loadFailed = false
            fallbackGate.reset()
            state = .playing
        case "loading":
            if state == .playing { startBufferTimer() } else { state = .loading }
        case "stopped":
            cancelPlaybackTimer(); cancelBufferTimer(); state = .stopped
        default: break
        }
    }

    private func playerHTML() -> String {
        let playerSize = Int(Self.playerSize)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body, #player {
              width: \(playerSize)px; height: \(playerSize)px;
              margin: 0; overflow: hidden; background: #000;
            }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script>
            const videoId = "\(videoId)";
            const origin = "\(Self.playerOrigin)";
            var player = null;
            var isReady = false;
            var isCued = false;
            var pendingPlay = false;
            var targetVolume = 100;

            function post(message) {
              try { window.webkit.messageHandlers.codeFM.postMessage(message); } catch (_) {}
            }

            function cuePlayer() {
              if (!isReady || !player || isCued) { return; }
              player.cueVideoById(videoId);
              isCued = true;
            }

            window.CodeFMPlayer = {
              play: function() {
                pendingPlay = true;
                post({ type: "state", state: "loading" });
                if (!isReady || !player) { return; }
                pendingPlay = false;
                player.setVolume(targetVolume);
                if (!isCued) { player.cueVideoById(videoId); isCued = true; }
                player.playVideo();
              },
              stop: function() {
                pendingPlay = false;
                if (isReady && player) { player.stopVideo(); isCued = false; cuePlayer(); }
                post({ type: "state", state: "stopped" });
              },
              setVolume: function(percentage) {
                targetVolume = Math.max(0, Math.min(100, Math.round(percentage)));
                if (isReady && player) { player.setVolume(targetVolume); }
              }
            };

            window.onYouTubeIframeAPIReady = function() {
              player = new YT.Player("player", {
                width: \(playerSize), height: \(playerSize),
                videoId: videoId,
                playerVars: { autoplay: 0, controls: 0, disablekb: 1, fs: 0, playsinline: 1, rel: 0, origin: origin },
                events: {
                  onReady: function() {
                    isReady = true;
                    player.setVolume(targetVolume);
                    isCued = true;
                    post({ type: "ready" });
                    if (pendingPlay) { window.CodeFMPlayer.play(); }
                  },
                  onStateChange: function(event) {
                    switch (event.data) {
                    case YT.PlayerState.PLAYING: post({ type: "state", state: "playing" }); break;
                    case YT.PlayerState.BUFFERING: post({ type: "state", state: "loading" }); break;
                    case YT.PlayerState.ENDED: isCued = false; post({ type: "ended" }); break;
                    case YT.PlayerState.PAUSED: isCued = true; post({ type: "state", state: "stopped" }); break;
                    case YT.PlayerState.CUED:
                      isCued = true;
                      if (!pendingPlay) { post({ type: "state", state: "stopped" }); }
                      break;
                    }
                  },
                  onError: function(event) { isCued = false; post({ type: "error", code: event.data }); }
                }
              });
            };
          </script>
          <script src="https://www.youtube.com/iframe_api"></script>
        </body>
        </html>
        """
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed = true
        handleLoadFailure()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed = true
        handleLoadFailure()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isPlayRequested else {
            teardownWebView()
            return
        }
        loadFailed = true
        shouldPlayWhenReady = false
        cancelPlaybackTimer()
        cancelBufferTimer()
        handleLoadFailure()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "codeFM",
              message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        handlePlayerMessage(body)
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(ucc, didReceive: message)
    }
}

/// Bookkeeping for the one-shot channel-live fallback: at most one resolve in
/// flight, and a resolve's result is used only if nothing superseded it.
struct LiveFallbackGate {
    enum FailureAction: Equatable { case resolve(token: Int), ignore, goOffline }

    private var didUseFallback = false
    private var nextToken = 0
    private var inFlightToken: Int?

    mutating func failure() -> FailureAction {
        guard inFlightToken == nil else { return .ignore }
        guard !didUseFallback else { return .goOffline }
        didUseFallback = true
        nextToken += 1
        inFlightToken = nextToken
        return .resolve(token: nextToken)
    }

    mutating func complete(token: Int) -> Bool {
        guard inFlightToken == token else { return false }
        inFlightToken = nil
        return true
    }

    /// Called when playback reaches "playing" or a new play attempt starts:
    /// supersede any resolve in flight and make the fallback available again.
    mutating func reset() {
        inFlightToken = nil
        rearm()
    }

    mutating func rearm() {
        didUseFallback = false
    }
}
