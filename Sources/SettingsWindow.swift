import AppKit

enum SettingsSection {
    case library
    case startup
    case general
}

final class SettingsWindow: NSWindowController {
    private let catalog: StreamCatalog
    private let settings: Settings
    private weak var player: StreamPlayer?

    private var contentStack: NSStackView!
    private var libraryStack: NSStackView!
    private var startupStack: NSStackView!
    private var generalStack: NSStackView!

    private var randomOnLaunchCheckbox: NSButton!
    private var defaultStreamSummary: NSTextField!
    private var hotkeyEnabledCheckbox: NSButton!
    private var loginItemCheckbox: NSButton!
    private var playAtStartCheckbox: NSButton!
    private var hotkeyRecorder: HotkeyRecorderView!

    var onSetDefaultStream: ((String?) -> Void)?       // nil = clear (use catalog default)
    var onPlayStream: ((Stream) -> Void)?

    init(catalog: StreamCatalog, settings: Settings, player: StreamPlayer) {
        self.catalog = catalog
        self.settings = settings
        self.player = player

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Code FM — Settings"
        window.minSize = NSSize(width: 480, height: 480)
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func scroll(to section: SettingsSection) {
        // v1: window fits on screen — no-op. T15+ may anchor sections individually.
    }

    private func buildUI() {
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 24
        contentStack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        libraryStack = makeSectionStack(header: "Stream Library")
        populateLibrary()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStreamHealthChanged),
            name: .codeFMStreamHealthChanged,
            object: nil
        )

        startupStack = makeSectionStack(header: "Startup")
        populateStartup()

        generalStack = makeSectionStack(header: "General")
        populateGeneral()

        contentStack.addArrangedSubview(libraryStack)
        contentStack.addArrangedSubview(startupStack)
        contentStack.addArrangedSubview(generalStack)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
        scroll.documentView = documentView
        // Track the clip view's width so the document always fills the scroll
        // view horizontally — without this the documentView is 0pt wide and the
        // whole window looks blank.
        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        window?.contentView = scroll
    }

    private func makeSectionStack(header: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let label = NSTextField(labelWithString: header)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        stack.addArrangedSubview(label)
        return stack
    }

    private func makeStreamRow(_ stream: Stream) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12

        let unavailable = !StreamHealthMonitor.shared.isAvailable(stream)

        let playButton = NSButton(title: "▶︎", target: self, action: #selector(handlePlayStream(_:)))
        playButton.bezelStyle = .rounded
        playButton.identifier = NSUserInterfaceItemIdentifier(stream.id)
        playButton.isEnabled = !unavailable

        let title = NSTextField(labelWithString: stream.displayName + (unavailable ? "  •  Unavailable" : ""))
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = unavailable ? .tertiaryLabelColor : .labelColor

        let sub = NSTextField(labelWithString: "\(stream.subgenre.displayName)  •  \(stream.providerLabel)")
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor

        let desc = NSTextField(labelWithString: stream.description)
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor

        let creditButton = NSButton(
            title: "\(stream.attribution.artist) — \(stream.attribution.website.host ?? "")",
            target: self,
            action: #selector(handleOpenAttribution(_:))
        )
        creditButton.bezelStyle = .inline
        creditButton.identifier = NSUserInterfaceItemIdentifier(stream.id)

        let setDefaultButton = NSButton(
            title: isCurrentDefault(stream) ? "★ Default" : "☆ Set as default",
            target: self,
            action: #selector(handleSetDefault(_:))
        )
        setDefaultButton.bezelStyle = .inline
        setDefaultButton.identifier = NSUserInterfaceItemIdentifier(stream.id)

        let textCol = NSStackView()
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        textCol.addArrangedSubview(title)
        textCol.addArrangedSubview(sub)
        textCol.addArrangedSubview(desc)
        textCol.addArrangedSubview(creditButton)
        textCol.addArrangedSubview(setDefaultButton)

        row.addArrangedSubview(playButton)
        row.addArrangedSubview(textCol)
        return row
    }

    private func isCurrentDefault(_ stream: Stream) -> Bool {
        let resolved = settings.defaultStreamId ?? catalog.defaultStreamId
        return resolved == stream.id
    }

    @objc private func handlePlayStream(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let stream = catalog.stream(withId: id) else { return }
        onPlayStream?(stream)
    }

    @objc private func handleOpenAttribution(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let stream = catalog.stream(withId: id) else { return }
        NSWorkspace.shared.open(stream.attribution.website)
    }

    @objc private func handleSetDefault(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        settings.defaultStreamId = id
        onSetDefaultStream?(id)
        populateLibrary()
        refreshDefaultStreamSummary()
        randomOnLaunchCheckbox?.state = .off
    }

    private func populateStartup() {
        startupStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(labelWithString: "Startup")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        startupStack.addArrangedSubview(label)

        randomOnLaunchCheckbox = NSButton(
            checkboxWithTitle: "Play a random stream on launch",
            target: self,
            action: #selector(handleRandomOnLaunchToggled(_:))
        )
        randomOnLaunchCheckbox.state =
            (settings.defaultStreamId == DefaultStreamResolver.randomSentinel) ? .on : .off
        startupStack.addArrangedSubview(randomOnLaunchCheckbox)

        defaultStreamSummary = NSTextField(labelWithString: "")
        defaultStreamSummary.font = .systemFont(ofSize: 11)
        defaultStreamSummary.textColor = .secondaryLabelColor
        startupStack.addArrangedSubview(defaultStreamSummary)

        refreshDefaultStreamSummary()
    }

    @objc private func handleRandomOnLaunchToggled(_ sender: NSButton) {
        if sender.state == .on {
            settings.defaultStreamId = DefaultStreamResolver.randomSentinel
        } else if settings.defaultStreamId == DefaultStreamResolver.randomSentinel {
            // Was "random" — revert to catalog default by clearing the override.
            settings.defaultStreamId = nil
        }
        refreshDefaultStreamSummary()
        populateLibrary()
    }

    private func populateGeneral() {
        generalStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(labelWithString: "General")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        generalStack.addArrangedSubview(label)

        playAtStartCheckbox = NSButton(
            checkboxWithTitle: "Start playing when Code FM launches",
            target: self,
            action: #selector(handlePlayAtStartToggled(_:))
        )
        playAtStartCheckbox.state = settings.playAtStart ? .on : .off
        generalStack.addArrangedSubview(playAtStartCheckbox)

        loginItemCheckbox = NSButton(
            checkboxWithTitle: "Launch Code FM at login",
            target: self,
            action: #selector(handleLoginItemToggled(_:))
        )
        loginItemCheckbox.state = LoginItemManager.shared.isEnabled ? .on : .off
        generalStack.addArrangedSubview(loginItemCheckbox)

        hotkeyEnabledCheckbox = NSButton(
            checkboxWithTitle: "Enable global play/pause hotkey",
            target: self,
            action: #selector(handleHotkeyEnabledToggled(_:))
        )
        hotkeyEnabledCheckbox.state = settings.globalHotkeyEnabled ? .on : .off
        generalStack.addArrangedSubview(hotkeyEnabledCheckbox)

        hotkeyRecorder = HotkeyRecorderView(settings: settings)
        hotkeyRecorder.isEnabled = settings.globalHotkeyEnabled
        generalStack.addArrangedSubview(hotkeyRecorder)
    }

    @objc private func handlePlayAtStartToggled(_ sender: NSButton) {
        settings.playAtStart = (sender.state == .on)
    }

    @objc private func handleLoginItemToggled(_ sender: NSButton) {
        LoginItemManager.shared.setEnabled(sender.state == .on)
        // SMAppService may refuse (denied prompt); reflect actual state.
        sender.state = LoginItemManager.shared.isEnabled ? .on : .off
    }

    @objc private func handleHotkeyEnabledToggled(_ sender: NSButton) {
        settings.globalHotkeyEnabled = (sender.state == .on)
        hotkeyRecorder.isEnabled = settings.globalHotkeyEnabled
        NotificationCenter.default.post(name: .codeFMHotkeyConfigChanged, object: nil)
        // The controller may flip it back off if registration failed — mirror that.
        sender.state = settings.globalHotkeyEnabled ? .on : .off
        hotkeyRecorder.isEnabled = settings.globalHotkeyEnabled
    }

    private func refreshDefaultStreamSummary() {
        let userId = settings.defaultStreamId
        if userId == DefaultStreamResolver.randomSentinel {
            defaultStreamSummary.stringValue = "On launch, a random stream will be picked."
        } else {
            let resolved = DefaultStreamResolver.resolve(catalog: catalog, userDefaultId: userId)
            defaultStreamSummary.stringValue = "On launch: \(resolved.displayName)"
        }
    }

    private func populateLibrary() {
        libraryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12

        let label = NSTextField(labelWithString: "Stream Library")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        headerRow.addArrangedSubview(label)

        let refresh = NSButton(
            title: "Refresh availability",
            target: self,
            action: #selector(handleRefreshAvailability)
        )
        refresh.bezelStyle = .inline
        refresh.font = .systemFont(ofSize: 11)
        headerRow.addArrangedSubview(refresh)
        libraryStack.addArrangedSubview(headerRow)

        let order: [Subgenre] = [.lofi, .jazzhop, .synthwave, .ambient, .brand, .other]
        let grouped = Dictionary(grouping: catalog.streams, by: \.subgenre)
        for genre in order {
            guard let entries = grouped[genre], !entries.isEmpty else { continue }
            let header = NSTextField(labelWithString: genre.displayName)
            header.font = .systemFont(ofSize: 12, weight: .semibold)
            header.textColor = .secondaryLabelColor
            libraryStack.addArrangedSubview(header)
            for stream in entries.sorted(by: { $0.displayName < $1.displayName }) {
                libraryStack.addArrangedSubview(makeStreamRow(stream))
            }
        }
    }

    @objc private func handleRefreshAvailability() {
        for stream in catalog.streams { StreamHealthMonitor.shared.recheck(stream) }
    }

    @objc private func handleStreamHealthChanged() {
        populateLibrary()
    }
}
