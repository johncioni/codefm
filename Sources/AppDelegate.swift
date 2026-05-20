import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var streamPlayer: StreamPlayer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.shared.registerDefaults()

        // T11 temporary wiring — T19 will replace this with full loadAtLaunch +
        // user-default-resolution (cache/remote precedence and persisted choice).
        let catalog = try! StreamCatalog.loadBundled()
        let initialStream = catalog.stream(withId: catalog.defaultStreamId) ?? catalog.streams.first!

        let streamPlayer = StreamPlayer(initialStream: initialStream)
        streamPlayer.volume = Settings.shared.volume
        self.streamPlayer = streamPlayer

        let controller = StatusBarController(streamPlayer: streamPlayer, catalog: catalog)
        statusBarController = controller

        if Settings.shared.playAtStart {
            streamPlayer.togglePlayback()
        } else {
            streamPlayer.prefetch()
        }

        if Settings.shared.globalHotkeyEnabled {
            controller.registerCurrentHotkey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        streamPlayer?.stop()
        HotkeyManager.shared.unregister()
    }
}
