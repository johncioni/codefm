import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let streamPlayer: StreamPlayer
    private var catalog: StreamCatalog

    private var aboutWindow: AboutWindow?
    private var whatsNewWindow: WhatsNewWindow?
    private var settingsWindowController: SettingsWindow?
    private var spinnerView: NSView?
    private var liquidGlassPanel: LiquidGlassMenuPanel?

    init(streamPlayer: StreamPlayer, catalog: StreamCatalog) {
        self.streamPlayer = streamPlayer
        self.catalog = catalog
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        setupButton()

        streamPlayer.onStateChange = { [weak self] state in
            self?.updateIcon(for: state)
            self?.liquidGlassPanel?.updatePlayerState(state)
        }

        streamPlayer.onCurrentStreamChange = { [weak self] stream in
            self?.liquidGlassPanel?.currentStreamId = stream.id
            self?.updateIcon(for: streamPlayer.state)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyConfigChanged),
            name: .codeFMHotkeyConfigChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettingsLibrary),
            name: .codeFMOpenSettingsLibrary,
            object: nil
        )

        updateIcon(for: .stopped)
    }

    @objc private func handleOpenSettingsLibrary() {
        openSettingsWindow(section: .library)
    }

    @objc private func handleHotkeyConfigChanged() {
        if Settings.shared.globalHotkeyEnabled {
            registerCurrentHotkey()
        } else {
            HotkeyManager.shared.unregister()
        }
        liquidGlassPanel?.syncState()
    }

    func applyUpdatedCatalog(_ updated: StreamCatalog) {
        self.catalog = updated
        liquidGlassPanel?.allStreams = updated.streams
        // If the currently-playing stream is gone after a remote refresh, swap to
        // the resolved default and continue playback if we were already playing.
        if !updated.streams.contains(streamPlayer.currentStream) {
            let newDefault = DefaultStreamResolver.resolve(
                catalog: updated,
                userDefaultId: Settings.shared.defaultStreamId
            )
            let wasPlaying = (streamPlayer.state == .playing)
            streamPlayer.load(stream: newDefault, autoplay: wasPlaying)
        }
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func showLiquidGlassPanel() {
        guard let button = statusItem.button else { return }

        if liquidGlassPanel == nil {
            let panel = LiquidGlassMenuPanel(streamPlayer: streamPlayer)
            panel.allStreams = catalog.streams
            panel.currentStreamId = streamPlayer.currentStream.id
            panel.onSelectStream = { [weak self] stream in
                self?.streamPlayer.load(stream: stream, autoplay: true)
            }
            panel.onSelectRandom = { [weak self] in
                guard let self else { return }
                self.streamPlayer.load(stream: RandomPicker.pick(from: self.catalog), autoplay: true)
            }
            panel.onOpenStreamLibrary = { [weak self] in
                self?.openStreamLibrary()
            }
            panel.onShowAbout = { [weak self] in self?.showAbout() }
            panel.onShowWhatsNew = { [weak self] in self?.showWhatsNew() }
            panel.onConfigureHotkey = { [weak self] in self?.configureHotkey() }
            panel.onHotkeyEnabledChanged = { [weak self] in
                guard let self else { return }
                if Settings.shared.globalHotkeyEnabled {
                    self.registerCurrentHotkey()
                } else {
                    HotkeyManager.shared.unregister()
                }
            }
            liquidGlassPanel = panel
        }

        // The panel's global event monitor ignores clicks on the status item, so the
        // panel stays open if the user clicks elsewhere on the icon — this toggle is
        // what closes it on a subsequent icon click.
        if let panel = liquidGlassPanel, panel.isVisible {
            panel.close()
            return
        }

        liquidGlassPanel?.show(below: button)
    }

    // MARK: - Actions

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showLiquidGlassPanel()
        } else {
            streamPlayer.togglePlayback()
        }
    }

    @objc private func configureHotkey() {
        openSettingsWindow(section: .general)
    }

    private func openStreamLibrary() {
        openSettingsWindow(section: .library)
    }

    func openSettingsWindow(section: SettingsSection) {
        if settingsWindowController == nil {
            let win = SettingsWindow(catalog: catalog, settings: .shared, player: streamPlayer)
            win.onPlayStream = { [weak self] stream in
                self?.streamPlayer.load(stream: stream, autoplay: true)
            }
            win.onSetDefaultStream = { _ in /* persisted by the window directly */ }
            settingsWindowController = win
        }
        settingsWindowController?.scroll(to: section)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        activateApp()
    }

    @objc private func showAbout() {
        if aboutWindow == nil { aboutWindow = AboutWindow() }
        aboutWindow?.makeKeyAndOrderFront(nil)
        activateApp()
    }

    @objc private func showWhatsNew() {
        if whatsNewWindow == nil { whatsNewWindow = WhatsNewWindow() }
        whatsNewWindow?.makeKeyAndOrderFront(nil)
        activateApp()
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @discardableResult
    func registerCurrentHotkey() -> Bool {
        let didRegister = HotkeyManager.shared.register(
            keyCode: Settings.shared.hotkeyKeyCode,
            modifiers: Settings.shared.hotkeyModifiers
        ) { [weak self] in
            self?.streamPlayer.togglePlayback()
        }

        if !didRegister {
            Settings.shared.globalHotkeyEnabled = false
        }

        return didRegister
    }

    // MARK: - Icon

    private func updateIcon(for state: PlayerState) {
        guard let button = statusItem.button else { return }

        // Reset opacity unconditionally — otherwise transitioning from .offline
        // (alpha 0.3) straight to .loading would render the spinner at 30% opacity.
        button.alphaValue = state.opacity

        let label = state.accessibilityLabel(streamName: streamPlayer.currentStream.displayName)

        if state == .loading {
            showSpinner(in: button)
        } else {
            hideSpinner()
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(
                systemSymbolName: state.symbolName,
                accessibilityDescription: label
            )?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
        }

        button.toolTip = label
    }

    private func showSpinner(in button: NSStatusBarButton) {
        button.image = nil

        if spinnerView == nil {
            spinnerView = Self.makeSpinnerView(in: button.bounds)
        }
        guard let spinner = spinnerView else { return }
        if spinner.superview !== button {
            button.addSubview(spinner)
        }
        spinner.isHidden = false
    }

    private func hideSpinner() {
        spinnerView?.isHidden = true
    }

    private static func makeSpinnerView(in bounds: NSRect) -> NSView {
        let size: CGFloat = 17
        let view = NSView(frame: bounds)
        view.wantsLayer = true

        let container = CALayer()
        container.bounds = NSRect(x: 0, y: 0, width: size, height: size)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY + 2.5)

        let dotCount = 8
        let dotSize: CGFloat = 2.5
        let radius: CGFloat = (size - dotSize) / 2.2

        for i in 0..<dotCount {
            let angle = (CGFloat(i) / CGFloat(dotCount)) * .pi * 2 - .pi / 2
            let x = size / 2 + cos(angle) * radius - dotSize / 2
            let y = size / 2 + sin(angle) * radius - dotSize / 2

            let dot = CALayer()
            dot.frame = NSRect(x: x, y: y, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
            dot.backgroundColor = NSColor.white.cgColor
            dot.opacity = Float(1.0 - (CGFloat(i) / CGFloat(dotCount)) * 0.75)
            container.addSublayer(dot)
        }

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -Double.pi * 2
        rotation.duration = 0.8
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        container.add(rotation, forKey: "spin")

        view.layer?.addSublayer(container)
        return view
    }
}
