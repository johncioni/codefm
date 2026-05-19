import AppKit
import QuartzCore

private enum Palette {
    static let rust = NSColor(srgbRed: 193/255, green: 80/255, blue: 42/255, alpha: 1)
    static let rustDark = NSColor(srgbRed: 150/255, green: 55/255, blue: 25/255, alpha: 1)
    static let rustLight = NSColor(srgbRed: 217/255, green: 106/255, blue: 64/255, alpha: 1)
    static let mutedGrey = NSColor(srgbRed: 110/255, green: 110/255, blue: 115/255, alpha: 1)
    static let primaryText = NSColor(srgbRed: 29/255, green: 29/255, blue: 31/255, alpha: 1)
    static let secondaryText = NSColor(srgbRed: 60/255, green: 60/255, blue: 67/255, alpha: 0.6)
    static let dotPlaying = NSColor(srgbRed: 94/255, green: 255/255, blue: 142/255, alpha: 1)
    static let dotLoading = NSColor(srgbRed: 255/255, green: 200/255, blue: 80/255, alpha: 1)
    static let dotStopped = NSColor(srgbRed: 255/255, green: 69/255, blue: 58/255, alpha: 1)
    static let dotOffline = NSColor(srgbRed: 255/255, green: 110/255, blue: 90/255, alpha: 1)
    static let systemGreen = NSColor(srgbRed: 52/255, green: 199/255, blue: 89/255, alpha: 1)
}

final class LiquidGlassMenuPanel: NSPanel {
    private let streamPlayer: StreamPlayer

    private let nowPlayingCard = NowPlayingCardView()
    private let volumeRow = GlassVolumeRow()
    private let playAtStartToggle = ToggleRow(icon: "play.fill", label: "Play at Start")
    private let startAtLoginToggle = ToggleRow(icon: "arrow.right.to.line", label: "Start at Login")
    private let enableHotkeyToggle = ToggleRow(icon: "bolt.fill", label: "Enable Global Hotkey")
    private let configureHotkeyRow = MenuRow(icon: "key.fill", label: "Configure Hotkey", trail: .keyHint(""))
    private let aboutRow = MenuRow(icon: "info.circle.fill", label: "About Claude FM")
    private let whatsNewRow = MenuRow(icon: "newspaper.fill", label: "What's New", trail: .pill(""))
    private let quitRow = MenuRow(icon: "power", label: "Quit", trail: .keyHint("⌘Q"))

    private var eventMonitorGlobal: Any?
    private var eventMonitorLocal: Any?
    private var statusItemScreenFrame: NSRect = .zero

    var onShowAbout: (() -> Void)?
    var onShowWhatsNew: (() -> Void)?
    var onConfigureHotkey: (() -> Void)?
    var onHotkeyEnabledChanged: (() -> Void)?

    // Panel geometry
    private static let panelWidth: CGFloat = 320
    private static let glassMargin: CGFloat = 8

    init(streamPlayer: StreamPlayer) {
        self.streamPlayer = streamPlayer
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .utilityWindow

        buildContent()
        wireActions()
        syncState()
    }

    deinit {
        removeEventMonitors()
    }

    // MARK: - Layout

    private func buildContent() {
        let width = Self.panelWidth
        let margin = Self.glassMargin

        // Outer shadow-bearing container is the panel itself (hasShadow = true on NSPanel).
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 420))
        root.wantsLayer = true
        root.layer?.backgroundColor = .clear

        let glassRect = NSRect(x: margin, y: margin, width: width - margin * 2, height: 0)

        // Frosted backdrop — system blur of whatever is behind the window
        let glassEffect = NSVisualEffectView(frame: glassRect)
        glassEffect.material = .popover
        glassEffect.blendingMode = .behindWindow
        glassEffect.state = .active
        glassEffect.wantsLayer = true
        glassEffect.layer?.cornerRadius = 14
        glassEffect.layer?.cornerCurve = .continuous
        glassEffect.layer?.borderWidth = 0.5
        glassEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        glassEffect.layer?.masksToBounds = true
        glassEffect.autoresizingMask = [.width]
        root.addSubview(glassEffect)

        // Faint white wash on top of the system blur to bias it lighter (matches the design's rgba(245,245,250,0.78))
        let wash = NSView(frame: glassEffect.bounds)
        wash.wantsLayer = true
        wash.layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 0.45).cgColor
        wash.layer?.cornerRadius = 14
        wash.layer?.cornerCurve = .continuous
        wash.autoresizingMask = [.width, .height]
        glassEffect.addSubview(wash)

        // Inner highlight (1px top inset)
        let topHighlight = NSView(frame: NSRect(x: 0, y: 0, width: glassEffect.bounds.width, height: 1))
        topHighlight.wantsLayer = true
        topHighlight.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        topHighlight.autoresizingMask = [.width]
        glassEffect.addSubview(topHighlight)

        // Stack content inside the glass with padding 8
        let pad: CGFloat = 8
        let stack = FlippedView(frame: NSRect(x: pad, y: pad, width: glassEffect.bounds.width - pad * 2, height: 0))
        stack.autoresizingMask = [.width]
        glassEffect.addSubview(stack)

        var cursor: CGFloat = 0
        let gap: CGFloat = 6

        // Now Playing card
        nowPlayingCard.frame = NSRect(x: 0, y: cursor, width: stack.bounds.width, height: 60)
        nowPlayingCard.autoresizingMask = [.width]
        stack.addSubview(nowPlayingCard)
        cursor += nowPlayingCard.frame.height + gap

        // Volume row
        volumeRow.frame = NSRect(x: 0, y: cursor, width: stack.bounds.width, height: 34)
        volumeRow.autoresizingMask = [.width]
        stack.addSubview(volumeRow)
        cursor += volumeRow.frame.height + gap

        // Settings group
        let settings = GroupContainer()
        let toggles: [NSView] = [
            playAtStartToggle, startAtLoginToggle, enableHotkeyToggle, configureHotkeyRow
        ]
        settings.set(rows: toggles)
        settings.frame = NSRect(x: 0, y: cursor, width: stack.bounds.width, height: settings.fittingHeight)
        settings.autoresizingMask = [.width]
        stack.addSubview(settings)
        cursor += settings.frame.height + gap

        // About / What's New group
        let aboutGroup = GroupContainer()
        aboutGroup.set(rows: [aboutRow, whatsNewRow])
        aboutGroup.frame = NSRect(x: 0, y: cursor, width: stack.bounds.width, height: aboutGroup.fittingHeight)
        aboutGroup.autoresizingMask = [.width]
        stack.addSubview(aboutGroup)
        cursor += aboutGroup.frame.height + gap

        // Quit row — standalone "flat" panel
        let quitContainer = GroupContainer()
        quitContainer.set(rows: [quitRow])
        quitContainer.frame = NSRect(x: 0, y: cursor, width: stack.bounds.width, height: quitContainer.fittingHeight)
        quitContainer.autoresizingMask = [.width]
        stack.addSubview(quitContainer)
        cursor += quitContainer.frame.height

        // Finalize sizes
        stack.frame.size.height = cursor
        let glassHeight = cursor + pad * 2
        glassEffect.frame = NSRect(x: margin, y: margin, width: glassEffect.bounds.width, height: glassHeight)
        let panelHeight = glassHeight + margin * 2
        root.frame.size.height = panelHeight
        setContentSize(NSSize(width: width, height: panelHeight))

        contentView = root
    }

    private func wireActions() {
        nowPlayingCard.onTogglePlayPause = { [weak self] in
            self?.streamPlayer.togglePlayback()
        }

        volumeRow.onVolumeChanged = { [weak self] value in
            self?.streamPlayer.volume = value
            Settings.shared.volume = value
        }

        playAtStartToggle.onToggle = { _ in
            Settings.shared.playAtStart.toggle()
        }

        startAtLoginToggle.onToggle = { [weak self] _ in
            let newState = !LoginItemManager.shared.isEnabled
            LoginItemManager.shared.setEnabled(newState)
            // Re-sync the pill from the real SMAppService status — if register()
            // failed (e.g. user denied the prompt), the optimistic toggle would
            // otherwise lie about being on.
            self?.startAtLoginToggle.isOn = LoginItemManager.shared.isEnabled
        }

        enableHotkeyToggle.onToggle = { [weak self] _ in
            Settings.shared.globalHotkeyEnabled.toggle()
            self?.onHotkeyEnabledChanged?()
            // Re-sync the pill from settings in case the controller failed to
            // register the hotkey and flipped the setting back off.
            self?.enableHotkeyToggle.isOn = Settings.shared.globalHotkeyEnabled
        }

        configureHotkeyRow.onClick = { [weak self] in
            self?.close()
            self?.onConfigureHotkey?()
        }

        aboutRow.onClick = { [weak self] in
            self?.close()
            self?.onShowAbout?()
        }

        whatsNewRow.onClick = { [weak self] in
            self?.close()
            self?.onShowWhatsNew?()
        }

        quitRow.onClick = {
            NSApp.terminate(nil)
        }
    }

    // MARK: - State sync

    func syncState() {
        nowPlayingCard.apply(state: streamPlayer.state)
        volumeRow.setValue(Settings.shared.volume)
        playAtStartToggle.isOn = Settings.shared.playAtStart
        startAtLoginToggle.isOn = LoginItemManager.shared.isEnabled
        enableHotkeyToggle.isOn = Settings.shared.globalHotkeyEnabled

        let mods = Settings.shared.hotkeyModifiers
        let key = Settings.shared.hotkeyKeyCode
        let desc = HotkeyManager.modifierFlagsDescription(for: mods) + HotkeyManager.keyCodeDescription(for: key)
        configureHotkeyRow.setTrail(.keyHint(desc))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        whatsNewRow.setTrail(.pill(version))
    }

    func updatePlayerState(_ state: PlayerState) {
        nowPlayingCard.apply(state: state)
    }

    // MARK: - Show / close

    func show(below button: NSStatusBarButton) {
        guard let buttonFrame = button.window?.frame else { return }
        statusItemScreenFrame = buttonFrame

        syncState()

        let width = frame.width
        let height = frame.height

        // Native menubar dropdowns sit flush against the menubar (no gap) with the
        // menu's left edge under the icon, extending rightward. If that would bleed
        // past the right edge of the screen, flip so the menu's right edge aligns
        // with the icon's right edge and the menu extends leftward instead.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonFrame.origin) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let edgePadding: CGFloat = 6

        var originX = buttonFrame.minX
        if originX + width > visible.maxX - edgePadding {
            originX = buttonFrame.maxX - width
        }
        originX = max(visible.minX + edgePadding, min(originX, visible.maxX - width - edgePadding))

        // Anchor the top of the panel to the bottom of the menu bar (the top of the
        // visible frame) — this keeps the panel flush even when the status item's
        // window extends a few points below the menu bar.
        var origin = NSPoint(x: originX, y: visible.maxY - height)
        if origin.y < visible.minY + 4 {
            origin.y = visible.minY + 4
        }

        setFrameOrigin(origin)
        alphaValue = 0
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            animator().alphaValue = 1
        }

        installEventMonitors()
    }

    override func close() {
        removeEventMonitors()
        super.close()
    }

    override func orderOut(_ sender: Any?) {
        removeEventMonitors()
        super.orderOut(sender)
    }

    private func installEventMonitors() {
        removeEventMonitors()
        eventMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self else { return }
            // Don't close on clicks that land on the status item itself — let the
            // status item's own click handler toggle the panel.
            if self.statusItemScreenFrame.contains(NSEvent.mouseLocation) { return }
            self.close()
        }
        eventMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // escape
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = eventMonitorGlobal {
            NSEvent.removeMonitor(m)
            eventMonitorGlobal = nil
        }
        if let m = eventMonitorLocal {
            NSEvent.removeMonitor(m)
            eventMonitorLocal = nil
        }
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Now Playing card -----------------------------------------------------

private final class NowPlayingCardView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Claude FM")
    private let stateDot = NSView()
    private let stateLabel = NSTextField(labelWithString: "Now Playing")
    private let playButton = CircularPlayButton()
    private let gradientLayer = CAGradientLayer()

    var onTogglePlayPause: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        gradientLayer.colors = [
            Palette.rust.withAlphaComponent(0.97).cgColor,
            Palette.rustDark.withAlphaComponent(0.97).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = 10
        gradientLayer.cornerCurve = .continuous
        layer?.addSublayer(gradientLayer)

        // Inset top highlight
        let highlight = CALayer()
        highlight.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(highlight)
        self.highlightLayer = highlight

        // Icon (app icon)
        if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
            iconView.image = icon
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.cornerCurve = .continuous
        iconView.layer?.masksToBounds = true
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        stateDot.wantsLayer = true
        stateDot.layer?.cornerRadius = 3
        stateDot.layer?.backgroundColor = Palette.dotPlaying.cgColor
        stateDot.layer?.shadowColor = Palette.dotPlaying.cgColor
        stateDot.layer?.shadowOpacity = 0.9
        stateDot.layer?.shadowRadius = 3
        stateDot.layer?.shadowOffset = .zero
        addSubview(stateDot)

        stateLabel.font = .systemFont(ofSize: 11, weight: .regular)
        stateLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        addSubview(stateLabel)

        playButton.target = self
        playButton.action = #selector(playPauseTapped)
        addSubview(playButton)
    }

    private var highlightLayer: CALayer?

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        highlightLayer?.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)

        let padX: CGFloat = 10
        let iconSize: CGFloat = 40
        iconView.frame = NSRect(x: padX, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

        let buttonSize: CGFloat = 36
        playButton.frame = NSRect(x: bounds.width - padX - buttonSize, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)

        let textX = iconView.frame.maxX + 10
        let textW = playButton.frame.minX - 8 - textX
        titleLabel.frame = NSRect(x: textX, y: bounds.height / 2 + 1, width: textW, height: 16)

        let dotSize: CGFloat = 6
        stateDot.frame = NSRect(x: textX, y: bounds.height / 2 - 13, width: dotSize, height: dotSize)
        stateLabel.frame = NSRect(x: textX + dotSize + 6, y: bounds.height / 2 - 17, width: textW - dotSize - 6, height: 14)
    }

    func apply(state: PlayerState) {
        switch state {
        case .playing:
            playButton.setSymbol("pause.fill")
            stateLabel.stringValue = "Now Playing"
            setStateDotColor(Palette.dotPlaying)
        case .loading:
            playButton.setSymbol("play.fill")
            stateLabel.stringValue = "Loading…"
            setStateDotColor(Palette.dotLoading)
        case .stopped:
            playButton.setSymbol("play.fill")
            stateLabel.stringValue = "Stopped"
            setStateDotColor(Palette.dotStopped)
        case .offline:
            playButton.setSymbol("play.fill")
            stateLabel.stringValue = "Offline"
            setStateDotColor(Palette.dotOffline)
        }
    }

    private func setStateDotColor(_ color: NSColor) {
        stateDot.layer?.backgroundColor = color.cgColor
        stateDot.layer?.shadowColor = color.cgColor
    }

    @objc private func playPauseTapped() {
        onTogglePlayPause?()
    }
}

private final class CircularPlayButton: NSControl {
    private let imageView = NSImageView()
    private var currentSymbol: String = "play.fill"
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = frameRect.height / 2
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        layer?.shadowRadius = 3

        imageView.contentTintColor = Palette.rust
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)
        setSymbol("play.fill")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func setSymbol(_ name: String) {
        guard name != currentSymbol || imageView.image == nil else { return }
        currentSymbol = name
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(Self.symbolConfig)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let size: CGFloat = 16
        // Optical centering: the play triangle's visual mass sits to its left, so nudge it 1pt right.
        let nudge: CGFloat = currentSymbol == "pause.fill" ? 0 : 1
        imageView.frame = NSRect(x: (bounds.width - size) / 2 + nudge, y: (bounds.height - size) / 2, width: size, height: size)
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

// MARK: - Volume row -----------------------------------------------------------

private final class GlassVolumeRow: NSView {
    private let speakerIcon = NSImageView()
    private let slider = NSSlider()
    private let percentLabel = NSTextField(labelWithString: "0%")
    private var currentSpeakerName: String?
    private static let speakerConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)

    var onVolumeChanged: ((Float) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor

        speakerIcon.contentTintColor = Palette.mutedGrey
        speakerIcon.imageScaling = .scaleProportionallyDown
        addSubview(speakerIcon)

        slider.cell = LiquidGlassSliderCell()
        slider.minValue = 0
        slider.maxValue = 1
        slider.floatValue = 1
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        addSubview(slider)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percentLabel.textColor = Palette.mutedGrey
        percentLabel.alignment = .right
        addSubview(percentLabel)

        updateSpeakerIcon()
        updatePercentLabel()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let padX: CGFloat = 12
        let iconSize: CGFloat = 14
        speakerIcon.frame = NSRect(x: padX, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

        let labelW: CGFloat = 36
        percentLabel.frame = NSRect(x: bounds.width - padX - labelW, y: (bounds.height - 14) / 2, width: labelW, height: 14)

        let sliderX = speakerIcon.frame.maxX + 10
        let sliderW = percentLabel.frame.minX - 8 - sliderX
        slider.frame = NSRect(x: sliderX, y: (bounds.height - 18) / 2, width: sliderW, height: 18)
    }

    func setValue(_ value: Float) {
        slider.floatValue = value
        updatePercentLabel()
        updateSpeakerIcon()
    }

    @objc private func sliderChanged() {
        updatePercentLabel()
        updateSpeakerIcon()
        onVolumeChanged?(slider.floatValue)
    }

    private func updatePercentLabel() {
        let pct = Int((slider.floatValue * 100).rounded())
        percentLabel.stringValue = "\(pct)%"
    }

    private func updateSpeakerIcon() {
        let vol = slider.floatValue
        let name: String
        if vol == 0 { name = "speaker.slash.fill" }
        else if vol < 0.33 { name = "speaker.wave.1.fill" }
        else if vol < 0.66 { name = "speaker.wave.2.fill" }
        else { name = "speaker.wave.3.fill" }
        guard name != currentSpeakerName else { return }
        currentSpeakerName = name
        speakerIcon.image = NSImage(systemSymbolName: name, accessibilityDescription: "Volume")?
            .withSymbolConfiguration(Self.speakerConfig)
    }
}

private final class LiquidGlassSliderCell: NSSliderCell {
    private static let knobSize: CGFloat = 14
    private static let trackHeight: CGFloat = 4

    private func progressFraction() -> CGFloat {
        let range = Float(maxValue - minValue)
        guard range > 0 else { return 0 }
        return CGFloat((floatValue - Float(minValue)) / range)
    }

    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        // Anchor the track to the slider's own bounds so it lines up with the
        // knob's vertical centerline; inset by half the knob's width on each
        // side so the track endpoints meet the knob's center at 0% / 100%.
        guard let bounds = controlView?.bounds else { return }
        let knobHalf = Self.knobSize / 2
        let track = NSRect(
            x: knobHalf,
            y: bounds.midY - Self.trackHeight / 2,
            width: max(0, bounds.width - Self.knobSize),
            height: Self.trackHeight
        )
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
        NSColor.black.withAlphaComponent(0.12).setFill()
        trackPath.fill()

        let fraction = progressFraction()
        if fraction > 0 {
            let progressRect = NSRect(
                x: track.minX,
                y: track.minY,
                width: track.width * fraction,
                height: track.height
            )
            let path = NSBezierPath(roundedRect: progressRect, xRadius: 2, yRadius: 2)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let gradient = NSGradient(colors: [Palette.rust, Palette.rustLight])
            gradient?.draw(in: progressRect, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        let path = NSBezierPath(ovalIn: knobRect)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.1).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    override func knobRect(flipped: Bool) -> NSRect {
        // Position the knob so its left edge is at 0 at 0% and its right edge
        // is at bounds.width at 100% — the knob travels the full width.
        guard let bounds = controlView?.bounds else {
            return super.knobRect(flipped: flipped)
        }
        let travel = max(0, bounds.width - Self.knobSize)
        let x = progressFraction() * travel
        let y = bounds.midY - Self.knobSize / 2
        return NSRect(x: x, y: y, width: Self.knobSize, height: Self.knobSize)
    }

    override func drawTickMarks() {}
}

// MARK: - Group container ------------------------------------------------------

private final class GroupContainer: NSView {
    private var rows: [NSView] = []
    private let rowHeight: CGFloat = 34

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        layer?.masksToBounds = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func set(rows: [NSView]) {
        self.rows.forEach { $0.removeFromSuperview() }
        self.rows = rows
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: bounds.width, height: rowHeight)
            row.autoresizingMask = [.width]
            addSubview(row)

            if index > 0 {
                let divider = NSView(frame: NSRect(x: 12, y: CGFloat(index) * rowHeight, width: bounds.width - 24, height: 0.5))
                divider.wantsLayer = true
                divider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
                divider.autoresizingMask = [.width]
                addSubview(divider)
            }
        }
    }

    var fittingHeight: CGFloat { CGFloat(rows.count) * rowHeight }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: bounds.width, height: rowHeight)
        }
    }
}

// MARK: - Row base class -------------------------------------------------------

private class GlassRow: NSView {
    fileprivate let iconView = NSImageView()
    fileprivate let labelField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private static let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)

    init(icon: String, label: String) {
        super.init(frame: .zero)
        wantsLayer = true

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(Self.iconConfig)
        iconView.contentTintColor = Palette.mutedGrey
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        labelField.stringValue = label
        labelField.font = .systemFont(ofSize: 13)
        labelField.textColor = Palette.primaryText
        labelField.maximumNumberOfLines = 1
        labelField.lineBreakMode = .byTruncatingTail
        addSubview(labelField)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let padX: CGFloat = 12
        let iconSize: CGFloat = 14
        iconView.frame = NSRect(x: padX, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        let labelX = iconView.frame.maxX + 10
        layoutTrail()
        let labelW = max(0, trailMinX - 8 - labelX)
        labelField.frame = NSRect(x: labelX, y: (bounds.height - 16) / 2, width: labelW, height: 16)
    }

    fileprivate func layoutTrail() {}
    fileprivate var trailMinX: CGFloat { bounds.width - 12 }

    // Route all clicks within the row to the row itself — NSTextField / NSImageView
    // descendants would otherwise swallow mouse events and leave dead zones.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.05).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }
}

// MARK: - Toggle row -----------------------------------------------------------

private final class ToggleRow: GlassRow {
    private let pill = TogglePill()
    var onToggle: ((Bool) -> Void)?

    var isOn: Bool {
        get { pill.isOn }
        set {
            pill.isOn = newValue
            needsLayout = true
        }
    }

    override init(icon: String, label: String) {
        super.init(icon: icon, label: label)
        addSubview(pill)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        pill.isOn.toggle()
        needsLayout = true
        onToggle?(pill.isOn)
    }

    override var trailMinX: CGFloat { pill.frame.minX }

    override fileprivate func layoutTrail() {
        let pillSize = NSSize(width: 30, height: 18)
        pill.frame = NSRect(x: bounds.width - 12 - pillSize.width, y: (bounds.height - pillSize.height) / 2, width: pillSize.width, height: pillSize.height)
    }
}

private final class TogglePill: NSView {
    private let knob = NSView()
    var isOn: Bool = false {
        didSet {
            guard oldValue != isOn else { return }
            applyState(animated: true)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        knob.wantsLayer = true
        knob.layer?.cornerRadius = 8
        knob.layer?.backgroundColor = NSColor.white.cgColor
        knob.layer?.shadowColor = NSColor.black.cgColor
        knob.layer?.shadowOpacity = 0.25
        knob.layer?.shadowOffset = NSSize(width: 0, height: -1)
        knob.layer?.shadowRadius = 2
        addSubview(knob)
        applyState(animated: false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    private func applyState(animated: Bool) {
        let bg = isOn ? Palette.systemGreen.cgColor : NSColor.black.withAlphaComponent(0.18).cgColor
        let knobX: CGFloat = isOn ? 13 : 1
        let knobRect = NSRect(x: knobX, y: 1, width: 16, height: 16)
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            layer?.backgroundColor = bg
            knob.frame = knobRect
            CATransaction.commit()
        } else {
            layer?.backgroundColor = bg
            knob.frame = knobRect
        }
    }
}

// MARK: - Menu row -------------------------------------------------------------

private enum MenuRowTrail {
    case none
    case keyHint(String)
    case pill(String)
}

private final class MenuRow: GlassRow {
    private var trail: MenuRowTrail = .none
    private let trailLabel = NSTextField(labelWithString: "")
    private let pillLabel = NSTextField(labelWithString: "")
    private let pillView = NSView()
    var onClick: (() -> Void)?

    init(icon: String, label: String, trail: MenuRowTrail = .none) {
        super.init(icon: icon, label: label)
        self.trail = trail

        // Native macOS menus use the system font at menu-item size with a muted color for shortcuts.
        trailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        trailLabel.textColor = Palette.secondaryText
        trailLabel.alignment = .right
        addSubview(trailLabel)

        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 8
        pillView.layer?.backgroundColor = Palette.rust.withAlphaComponent(0.15).cgColor
        addSubview(pillView)

        pillLabel.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        pillLabel.textColor = Palette.rust
        pillLabel.alignment = .center
        pillView.addSubview(pillLabel)

        setTrail(trail)
    }

    func setTrail(_ trail: MenuRowTrail) {
        self.trail = trail
        switch trail {
        case .none:
            trailLabel.isHidden = true
            pillView.isHidden = true
        case .keyHint(let text):
            trailLabel.stringValue = text
            trailLabel.isHidden = text.isEmpty
            pillView.isHidden = true
        case .pill(let text):
            pillLabel.stringValue = text
            pillView.isHidden = text.isEmpty
            trailLabel.isHidden = true
        }
        needsLayout = true
    }

    override var trailMinX: CGFloat {
        switch trail {
        case .none: return bounds.width - 12
        case .keyHint: return trailLabel.frame.minX
        case .pill: return pillView.frame.minX
        }
    }

    override fileprivate func layoutTrail() {
        let padX: CGFloat = 12
        switch trail {
        case .none:
            break
        case .keyHint(let text):
            let size = (text as NSString).size(withAttributes: [.font: trailLabel.font as Any])
            let w = ceil(size.width) + 4
            let h: CGFloat = 16
            trailLabel.frame = NSRect(x: bounds.width - padX - w, y: (bounds.height - h) / 2, width: w, height: h)
        case .pill(let text):
            let size = (text as NSString).size(withAttributes: [.font: pillLabel.font as Any])
            let w = ceil(size.width) + 12
            let h: CGFloat = 16
            pillView.frame = NSRect(x: bounds.width - padX - w, y: (bounds.height - h) / 2, width: w, height: h)
            pillView.layer?.cornerRadius = h / 2
            pillLabel.frame = pillView.bounds
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        onClick?()
    }
}
