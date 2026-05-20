import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var streamPlayer: StreamPlayer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.shared.registerDefaults()

        let catalog = StreamCatalog.loadAtLaunch { [weak self] refreshed in
            self?.statusBarController?.applyUpdatedCatalog(refreshed)
        }

        let initialStream = DefaultStreamResolver.resolve(
            catalog: catalog,
            userDefaultId: Settings.shared.defaultStreamId
        )

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
