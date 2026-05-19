import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var streamPlayer: StreamPlayer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.shared.registerDefaults()

        let streamPlayer = StreamPlayer()
        streamPlayer.volume = Settings.shared.volume
        self.streamPlayer = streamPlayer

        let controller = StatusBarController(streamPlayer: streamPlayer)
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
