import AppKit
import Foundation
import WebKit

final class StreamPlayer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let videoID = "YmQ7jRgf4f0"
    private static let playerOrigin = "https://claudefm.app"
    private static let playbackStartTimeout: TimeInterval = 25
    private static let bufferingHangTimeout: TimeInterval = 15
    private static let playerSize: CGFloat = 200

    private var webView: WKWebView?
    private var playerWindow: NSWindow?
    private var isPlayerReady = false
    private var shouldPlayWhenReady = false
    private var loadFailed = false
    private var playbackTimer: Timer?
    private var bufferTimer: Timer?

    var volume: Float = 1.0 {
        didSet { sendVolumeToPlayer() }
    }

    var onStateChange: ((PlayerState) -> Void)?

    private(set) var state: PlayerState = .stopped {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }

    deinit {
        teardownWebView()
    }

    func prefetch() {
        loadPlayerIfNeeded()
    }

    func togglePlayback() {
        switch state {
        case .stopped, .offline:
            play()
        case .loading:
            break
        case .playing:
            stop()
        }
    }

    func stop() {
        shouldPlayWhenReady = false
        cancelPlaybackTimer()
        cancelBufferTimer()

        guard webView != nil else {
            state = .stopped
            return
        }

        evaluatePlayerScript("window.ClaudeFMPlayer && window.ClaudeFMPlayer.stop();")
        state = .stopped
    }

    private func play() {
        if webView != nil && loadFailed {
            // Prior load reached a confirmed failure (nav error, JS error, or initial timeout);
            // tear down so loadPlayerIfNeeded() can build a fresh webview below.
            teardownWebView()
        }

        shouldPlayWhenReady = true
        state = .loading
        startPlaybackTimer()
        loadPlayerIfNeeded()

        if isPlayerReady {
            playLoadedPlayer()
        }
    }

    private func playLoadedPlayer() {
        shouldPlayWhenReady = false
        sendVolumeToPlayer()

        evaluatePlayerScript("window.ClaudeFMPlayer && window.ClaudeFMPlayer.play();") { [weak self] didSucceed in
            guard let self, !didSucceed else { return }
            // JS eval failed — the webview is likely dead (content process crashed
            // or never reached `ready`). Mark the session failed so the next play()
            // tears down and rebuilds; reusing this webview would loop the failure.
            self.loadFailed = true
            self.shouldPlayWhenReady = false
            self.cancelPlaybackTimer()
            self.cancelBufferTimer()
            guard self.state == .loading else { return }
            self.state = .offline
        }
    }

    private func loadPlayerIfNeeded() {
        guard webView == nil else { return }

        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(self), name: "claudeFM")

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

        // Host the WKWebView in a real, on-screen NSWindow but make it visually
        // absent (alpha 0, mouse-transparent). Parking the window off-screen
        // instead invites AppKit's constrainFrameRect to "rescue" it back onto
        // the active display after display sleep/wake or geometry changes,
        // which made the player surface visible after idle periods.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.playerSize, height: Self.playerSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
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

        webView.loadHTMLString(Self.playerHTML, baseURL: URL(string: Self.playerOrigin))
    }

    private func startPlaybackTimer() {
        cancelPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: Self.playbackStartTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.playbackTimer = nil
            guard self.state == .loading else { return }
            if !self.isPlayerReady {
                self.loadFailed = true
            }
            // Clear the auto-play intent: if the iframe API eventually loads after
            // we've already marked the session offline, the `ready` handler must
            // not silently kick off playback the user is no longer waiting for.
            self.shouldPlayWhenReady = false
            self.state = .offline
        }
    }

    private func startBufferTimer() {
        cancelBufferTimer()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: Self.bufferingHangTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.bufferTimer = nil
            guard self.state == .playing else { return }
            // Mark the session as failed so the next play() rebuilds the webview —
            // if buffering hung for 15s, the YT player is likely stuck and reusing
            // the same webview would just loop through the same failure.
            self.loadFailed = true
            self.state = .offline
        }
    }

    private func cancelBufferTimer() {
        bufferTimer?.invalidate()
        bufferTimer = nil
    }

    private func teardownWebView() {
        cancelPlaybackTimer()
        cancelBufferTimer()
        // Stop in-flight loads and drop the delegate so the old webview's nav
        // callbacks can't fire against `self` after a new session is built.
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "claudeFM")
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
        evaluatePlayerScript("window.ClaudeFMPlayer && window.ClaudeFMPlayer.setVolume(\(percentage));")
    }

    private func evaluatePlayerScript(_ script: String, completion: ((Bool) -> Void)? = nil) {
        webView?.evaluateJavaScript(script) { _, error in
            completion?(error == nil)
        }
    }

    private func handlePlayerMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "ready":
            // After we've given up (state == .offline), discard a late `ready` —
            // don't silently clear loadFailed or restart auto-play. Other states
            // (.stopped from prefetch, .loading from a play click, .playing from
            // a reload) must process `ready` normally so `isPlayerReady` gets set.
            guard state != .offline else { return }
            isPlayerReady = true
            loadFailed = false
            sendVolumeToPlayer()
            if shouldPlayWhenReady {
                playLoadedPlayer()
            }
        case "state":
            guard let stateName = message["state"] as? String else { return }
            updateState(named: stateName)
        case "error":
            isPlayerReady = false
            loadFailed = true
            updateState(named: "offline")
        default:
            break
        }
    }

    private func cancelPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updateState(named stateName: String) {
        switch stateName {
        case "playing":
            cancelPlaybackTimer()
            cancelBufferTimer()
            // Reaching .playing proves the webview is alive — clear any stale
            // failure flag set by the buffer timer in case YT auto-recovered.
            loadFailed = false
            state = .playing
        case "loading":
            if state == .playing {
                // Mid-playback buffering — suppress flicker but watch for a prolonged hang.
                startBufferTimer()
            } else {
                state = .loading
            }
        case "stopped":
            cancelPlaybackTimer()
            cancelBufferTimer()
            state = .stopped
        case "offline":
            cancelPlaybackTimer()
            cancelBufferTimer()
            state = .offline
        default:
            break
        }
    }

    private static let playerHTML: String = {
        let playerSize = Int(StreamPlayer.playerSize)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body, #player {
              width: \(playerSize)px;
              height: \(playerSize)px;
              margin: 0;
              overflow: hidden;
              background: #000;
            }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script>
            const videoId = "\(videoID)";
            const origin = "\(playerOrigin)";
            var player = null;
            var isReady = false;
            var isCued = false;
            var pendingPlay = false;
            var targetVolume = 100;

            function post(message) {
              try {
                window.webkit.messageHandlers.claudeFM.postMessage(message);
              } catch (_) {}
            }

            function cuePlayer() {
              if (!isReady || !player || isCued) { return; }
              player.cueVideoById(videoId);
              isCued = true;
            }

            window.ClaudeFMPlayer = {
              play: function() {
                pendingPlay = true;
                post({ type: "state", state: "loading" });
                if (!isReady || !player) { return; }
                pendingPlay = false;
                player.setVolume(targetVolume);
                if (!isCued) {
                  player.cueVideoById(videoId);
                  isCued = true;
                }
                player.playVideo();
              },
              stop: function() {
                pendingPlay = false;
                if (isReady && player) {
                  player.stopVideo();
                  isCued = false;
                  cuePlayer();
                }
                post({ type: "state", state: "stopped" });
              },
              setVolume: function(percentage) {
                targetVolume = Math.max(0, Math.min(100, Math.round(percentage)));
                if (isReady && player) {
                  player.setVolume(targetVolume);
                }
              }
            };

            window.onYouTubeIframeAPIReady = function() {
              player = new YT.Player("player", {
                width: \(playerSize),
                height: \(playerSize),
                videoId: videoId,
                playerVars: {
                  autoplay: 0,
                  controls: 0,
                  disablekb: 1,
                  fs: 0,
                  playsinline: 1,
                  rel: 0,
                  origin: origin
                },
                events: {
                  onReady: function() {
                    isReady = true;
                    player.setVolume(targetVolume);
                    isCued = true;
                    post({ type: "ready" });
                    if (pendingPlay) {
                      window.ClaudeFMPlayer.play();
                    }
                  },
                  onStateChange: function(event) {
                    switch (event.data) {
                    case YT.PlayerState.PLAYING:
                      post({ type: "state", state: "playing" });
                      break;
                    case YT.PlayerState.BUFFERING:
                      post({ type: "state", state: "loading" });
                      break;
                    case YT.PlayerState.ENDED:
                      isCued = false;
                      post({ type: "state", state: "offline" });
                      break;
                    case YT.PlayerState.PAUSED:
                      isCued = true;
                      post({ type: "state", state: "stopped" });
                      break;
                    case YT.PlayerState.CUED:
                      isCued = true;
                      if (!pendingPlay) {
                        post({ type: "state", state: "stopped" });
                      }
                      break;
                    }
                  },
                  onError: function(event) {
                    isCued = false;
                    post({ type: "error", code: event.data });
                  }
                }
              });
            };
          </script>
          <script src="https://www.youtube.com/iframe_api"></script>
        </body>
        </html>
        """
    }()

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed = true
        updateState(named: "offline")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed = true
        updateState(named: "offline")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The WKWebView's content process was killed (jetsam, crash, etc.). The
        // webview is now a zombie — JS eval will silently no-op forever. Mark
        // failed so the next play() rebuilds from scratch.
        loadFailed = true
        shouldPlayWhenReady = false
        cancelPlaybackTimer()
        cancelBufferTimer()
        updateState(named: "offline")
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "claudeFM",
              message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        handlePlayerMessage(body)
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
