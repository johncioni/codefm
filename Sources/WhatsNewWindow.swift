import AppKit

final class WhatsNewWindow: NSWindow {
    private struct Release {
        let version: String
        let date: String
        let isLatest: Bool
        let entries: [(tag: String, tagColor: NSColor, items: [String])]
    }

    private static let releases: [Release] = [
        Release(version: "1.3.2", date: "5/13/26", isLatest: true, entries: [
            (tag: "FIXED", tagColor: .systemGreen, items: [
                "The hidden audio player no longer flashes into view after your Mac wakes from sleep.",
            ]),
        ]),
        Release(version: "1.3.1", date: "5/13/26", isLatest: false, entries: [
            (tag: "FIXED", tagColor: .systemGreen, items: [
                "The loading spinner no longer gets stuck on the first play after launch.",
                "Long buffering hangs now reset cleanly so the next play tries fresh.",
            ]),
        ]),
        Release(version: "1.3", date: "5/12/26", isLatest: false, entries: [
            (tag: "IMPROVED", tagColor: .systemBlue, items: [
                "New Liquid Glass design — frosted menu with an inline volume slider, modern toggles, and clearer keyboard shortcut hints.",
                "Menu bar icon scaled up to feel more at home next to other system icons.",
            ]),
        ]),
        Release(version: "1.2.2", date: "5/11/26", isLatest: false, entries: [
            (tag: "FIXED", tagColor: .systemGreen, items: [
                "Clicking play while the stream is still warming up no longer cancels the load.",
            ]),
        ]),
        Release(version: "1.2.1", date: "5/11/26", isLatest: false, entries: [
            (tag: "FIXED", tagColor: .systemGreen, items: [
                "If the initial connect fails, hitting play again now retries cleanly instead of getting stuck.",
                "Long buffering pauses now show as offline so it's clearer when to retry.",
            ]),
        ]),
        Release(version: "1.2", date: "5/11/26", isLatest: false, entries: [
            (tag: "IMPROVED", tagColor: .systemBlue, items: [
                "Now a universal app — runs natively on both Apple Silicon and Intel Macs.",
            ]),
        ]),
        Release(version: "1.1", date: "5/11/26", isLatest: false, entries: [
            (tag: "IMPROVED", tagColor: .systemBlue, items: [
                "Faster, more reliable streaming engine.",
                "No external dependencies — the app is fully self-contained.",
            ]),
        ]),
        Release(version: "1.0", date: "5/11/26", isLatest: false, entries: [
            (tag: "NEW", tagColor: .systemOrange, items: [
                "Menu bar audio player for the Claude FM live stream.",
                "Volume slider.",
                "Play at launch option.",
                "Start at login.",
                "Configurable global hotkey.",
                "About dialog.",
            ]),
        ]),
    ]

    init() {
        let w: CGFloat = 660
        let h: CGFloat = 580

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        title = ""
        titlebarAppearsTransparent = true
        center()

        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        // Header
        let iconView = NSImageView(frame: NSRect(x: 28, y: 14, width: 40, height: 40))
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "What's New")
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.frame = NSRect(x: 76, y: 14, width: 200, height: 24)
        container.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "\(Self.releases.count) releases")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 76, y: 38, width: 300, height: 16)
        container.addSubview(subtitle)

        // Scroll view
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 68, width: w, height: h - 68))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        let cardMargin: CGFloat = 28
        let cardWidth = w - cardMargin * 2
        let cardGap: CGFloat = 14

        // Build cards and measure total height
        var cardViews: [NSView] = []
        var totalHeight: CGFloat = 14

        for release in Self.releases {
            let card = Self.makeCard(release: release, width: cardWidth)
            cardViews.append(card)
            totalHeight += card.frame.height + cardGap
        }
        totalHeight += 14

        let docView = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: totalHeight))

        var y: CGFloat = 14
        for card in cardViews {
            card.frame.origin = NSPoint(x: cardMargin, y: y)
            docView.addSubview(card)
            y += card.frame.height + cardGap
        }

        scrollView.documentView = docView
        container.addSubview(scrollView)

        self.contentView = container
    }

    private static func makeCard(release: Release, width: CGFloat) -> NSView {
        let pad: CGFloat = 24
        let innerWidth = width - pad * 2
        let itemIndent: CGFloat = 110
        let itemWidth = innerWidth - itemIndent

        // First pass: measure height
        var totalItemsHeight: CGFloat = 0
        for entry in release.entries {
            for (i, item) in entry.items.enumerated() {
                totalItemsHeight += measureText(item, width: itemWidth - 14, fontSize: 13.5)
                if i < entry.items.count - 1 { totalItemsHeight += 6 }
            }
            totalItemsHeight += 16
        }

        let headerHeight: CGFloat = 36
        let separatorSpace: CGFloat = 24
        let cardHeight = pad + headerHeight + separatorSpace + totalItemsHeight + pad - 16

        let card = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: cardHeight))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor

        var y = pad

        // Version number
        let versionLabel = NSTextField(labelWithString: release.version)
        versionLabel.font = .systemFont(ofSize: 26, weight: .bold)
        versionLabel.sizeToFit()
        versionLabel.frame.origin = NSPoint(x: pad, y: y)
        card.addSubview(versionLabel)

        // LATEST badge
        if release.isLatest {
            let badge = makeBadge("LATEST", color: .systemOrange)
            badge.frame.origin = NSPoint(x: pad + versionLabel.frame.width + 12, y: y + 6)
            card.addSubview(badge)
        }

        // Date
        let dateLabel = NSTextField(labelWithString: release.date)
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .secondaryLabelColor
        dateLabel.alignment = .right
        dateLabel.frame = NSRect(x: width - pad - 80, y: y + 8, width: 80, height: 16)
        card.addSubview(dateLabel)

        y += headerHeight

        // Separator
        let sep = NSView(frame: NSRect(x: pad, y: y, width: innerWidth, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        card.addSubview(sep)

        y += separatorSpace

        // Entries
        for entry in release.entries {
            // Badge on first line
            let badge = makeBadge(entry.tag, color: entry.tagColor, withDot: true)
            badge.frame.origin = NSPoint(x: pad, y: y)
            card.addSubview(badge)

            let bulletIndent: CGFloat = 14
            for (i, item) in entry.items.enumerated() {
                let bulletLabel = NSTextField(labelWithString: "\u{2022}")
                bulletLabel.font = .systemFont(ofSize: 11)
                bulletLabel.textColor = .secondaryLabelColor
                bulletLabel.frame = NSRect(x: pad + itemIndent, y: y + 1, width: 10, height: 16)
                card.addSubview(bulletLabel)

                let textH = measureText(item, width: itemWidth - bulletIndent, fontSize: 13.5)
                let itemLabel = NSTextField(wrappingLabelWithString: item)
                itemLabel.font = .systemFont(ofSize: 13.5)
                itemLabel.preferredMaxLayoutWidth = itemWidth - bulletIndent
                itemLabel.frame = NSRect(x: pad + itemIndent + bulletIndent, y: y, width: itemWidth - bulletIndent, height: textH)
                card.addSubview(itemLabel)

                y += textH
                if i < entry.items.count - 1 { y += 6 }
            }
            y += 16
        }

        return card
    }

    private static func makeBadge(_ text: String, color: NSColor, withDot: Bool = false) -> NSView {
        let label = NSTextField(labelWithString: text + " ")
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = color
        let lw = label.intrinsicContentSize.width
        let dotSpace: CGFloat = withDot ? 14 : 0
        let totalW = dotSpace + lw + 12

        let badge = FlippedView(frame: NSRect(x: 0, y: 0, width: totalW, height: 20))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = color.withAlphaComponent(0.1).cgColor
        badge.layer?.cornerRadius = 4

        if withDot {
            let dot = NSView(frame: NSRect(x: 6, y: 7, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.cornerRadius = 3
            badge.addSubview(dot)
        }

        label.frame = NSRect(x: dotSpace + 4, y: 2, width: lw, height: 16)
        badge.addSubview(label)

        return badge
    }

    private static func measureText(_ text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return max(ceil(rect.height) + 4, 22)
    }
}
