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

        startupStack = makeSectionStack(header: "Startup")
        populateStartup()

        generalStack = makeSectionStack(header: "General")  // populated in T17

        contentStack.addArrangedSubview(libraryStack)
        contentStack.addArrangedSubview(startupStack)
        contentStack.addArrangedSubview(generalStack)

        let documentView = NSView()
        documentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalToConstant: 520),
        ])
        scroll.documentView = documentView
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

        let playButton = NSButton(title: "▶︎", target: self, action: #selector(handlePlayStream(_:)))
        playButton.bezelStyle = .rounded
        playButton.identifier = NSUserInterfaceItemIdentifier(stream.id)

        let title = NSTextField(labelWithString: stream.displayName)
        title.font = .systemFont(ofSize: 13, weight: .medium)

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
        let label = NSTextField(labelWithString: "Stream Library")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        libraryStack.addArrangedSubview(label)

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
}
