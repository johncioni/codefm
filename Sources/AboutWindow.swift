import AppKit
import QuartzCore

final class AboutWindow: NSWindow {
    init() {
        let w: CGFloat = 420
        let h: CGFloat = 340

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        title = ""
        initialFirstResponder = nil
        center()

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        content.wantsLayer = true

        // Spinning vinyl with app icon
        let vinylSize: CGFloat = 120
        let vinylView = VinylRecordView(frame: NSRect(x: (w - vinylSize) / 2, y: 25, width: vinylSize, height: vinylSize))
        content.addSubview(vinylView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Code FM")
        nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 0, y: 148, width: w, height: 30)
        content.addSubview(nameLabel)

        // Tagline
        let tagline = NSTextField(labelWithString: "Music for thinking and building")
        tagline.font = .systemFont(ofSize: 13)
        tagline.textColor = .secondaryLabelColor
        tagline.alignment = .center
        tagline.frame = NSRect(x: 0, y: 180, width: w, height: 18)
        content.addSubview(tagline)

        // Version / Made by row
        let boxFrame = NSRect(x: 30, y: 223, width: w - 60, height: 50)
        let infoBox = NSBox(frame: boxFrame)
        infoBox.boxType = .custom
        infoBox.borderColor = .separatorColor
        infoBox.borderWidth = 1
        infoBox.cornerRadius = 8
        infoBox.fillColor = .controlBackgroundColor
        infoBox.titlePosition = .noTitle

        let versionHeader = NSTextField(labelWithString: "VERSION")
        versionHeader.font = .systemFont(ofSize: 10, weight: .medium)
        versionHeader.textColor = .tertiaryLabelColor
        versionHeader.frame = NSRect(x: 15, y: 25, width: 100, height: 14)
        infoBox.addSubview(versionHeader)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let versionValue = NSTextField(labelWithString: "\(version) (\(build))")
        versionValue.font = .systemFont(ofSize: 14)
        versionValue.frame = NSRect(x: 15, y: 6, width: 100, height: 20)
        infoBox.addSubview(versionValue)

        let madeByHeader = NSTextField(labelWithString: "MADE BY")
        madeByHeader.font = .systemFont(ofSize: 10, weight: .medium)
        madeByHeader.textColor = .tertiaryLabelColor
        madeByHeader.alignment = .right
        madeByHeader.frame = NSRect(x: boxFrame.width - 130, y: 25, width: 115, height: 14)
        infoBox.addSubview(madeByHeader)

        let madeByValue = NSTextField(labelWithString: "John Cioni")
        madeByValue.font = .systemFont(ofSize: 14)
        madeByValue.alignment = .right
        madeByValue.frame = NSRect(x: boxFrame.width - 130, y: 6, width: 115, height: 20)
        infoBox.addSubview(madeByValue)

        content.addSubview(infoBox)

        // Settings credits link
        let creditsButton = NSButton(
            title: "Stream sources & credits in Settings \u{2192} Stream Library",
            target: self,
            action: #selector(handleOpenCredits)
        )
        creditsButton.bezelStyle = .inline
        creditsButton.isBordered = false
        creditsButton.font = .systemFont(ofSize: 12)
        creditsButton.contentTintColor = .linkColor
        creditsButton.alignment = .center
        creditsButton.frame = NSRect(x: 0, y: 285, width: w, height: 18)
        content.addSubview(creditsButton)

        // Footer
        let footer = NSTextField(labelWithString: "\u{00A9} 2026 \u{00B7} Made with love in West Palm Beach \u{1F334}")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        footer.frame = NSRect(x: 0, y: 312, width: w, height: 16)
        content.addSubview(footer)

        self.contentView = content
        makeFirstResponder(nil)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        makeFirstResponder(nil)
    }

    @objc private func handleOpenCredits() {
        NotificationCenter.default.post(name: .codeFMOpenSettingsLibrary, object: nil)
    }
}

extension Notification.Name {
    static let codeFMOpenSettingsLibrary = Notification.Name("CodeFMOpenSettingsLibrary")
}

private final class VinylRecordView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        let diameter = min(bounds.width, bounds.height)
        let radius = diameter / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let discRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: diameter,
            height: diameter
        )
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Soft drop shadow beneath the disc
        let shadowLayer = CALayer()
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(
            ellipseIn: discRect.insetBy(dx: 1, dy: 1).offsetBy(dx: 0, dy: 3),
            transform: nil
        )
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.35
        shadowLayer.shadowOffset = .zero
        shadowLayer.shadowRadius = 9
        layer?.addSublayer(shadowLayer)

        // Rotating disc — grooves, label, and icon spin together
        let discLayer = CALayer()
        discLayer.frame = bounds
        discLayer.contents = Self.drawVinyl(size: bounds.size)
        discLayer.contentsGravity = .resizeAspect
        discLayer.contentsScale = scale
        discLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        discLayer.position = center

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -Double.pi * 2
        rotation.duration = 10
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        discLayer.add(rotation, forKey: "spin")
        layer?.addSublayer(discLayer)

        // Stationary specular highlight — this is what sells "spinning vinyl":
        // light reflections stay fixed in world space while the disc turns.
        let glossLayer = CALayer()
        glossLayer.frame = bounds
        glossLayer.contents = Self.drawGloss(size: bounds.size)
        glossLayer.contentsGravity = .resizeAspect
        glossLayer.contentsScale = scale
        layer?.addSublayer(glossLayer)

        // Spindle hole — stationary at the axis of rotation
        let holeRadius: CGFloat = max(1.5, diameter * 0.017)
        let holeLayer = CALayer()
        holeLayer.frame = CGRect(
            x: center.x - holeRadius,
            y: center.y - holeRadius,
            width: holeRadius * 2,
            height: holeRadius * 2
        )
        holeLayer.backgroundColor = NSColor.black.cgColor
        holeLayer.cornerRadius = holeRadius
        layer?.addSublayer(holeLayer)
    }

    required init?(coder: NSCoder) { nil }

    private static func drawVinyl(size: NSSize) -> NSImage {
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = size.width / 2
            let cy = size.height / 2
            let radius = min(cx, cy) - 1
            let labelRadius = radius * 0.38

            // Base disc — deep matte plastic
            let disc = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            NSColor(white: 0.045, alpha: 1.0).setFill()
            disc.fill()

            // Fine concentric grooves, outside the label only
            for i in stride(from: 0.42, through: 0.975, by: 0.011) {
                let r = radius * CGFloat(i)
                let groove = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                groove.lineWidth = 0.4
                let shade: CGFloat = (Int(i * 1000) % 3 == 0) ? 0.17 : 0.095
                NSColor(white: shade, alpha: 1.0).setStroke()
                groove.stroke()
            }

            // Track-break bands — slightly darker rings dividing "songs"
            for i in [0.56, 0.71, 0.86] as [CGFloat] {
                let r = radius * i
                let band = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                band.lineWidth = 0.8
                NSColor(white: 0.015, alpha: 1.0).setStroke()
                band.stroke()
            }

            // Outer rim — crisp edge
            let rim = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            NSColor(white: 0.22, alpha: 1.0).setStroke()
            rim.lineWidth = 1.0
            rim.stroke()

            // Faint moat ring just outside the label (where label paper meets vinyl)
            let moat = NSBezierPath(ovalIn: NSRect(x: cx - labelRadius - 1, y: cy - labelRadius - 1, width: (labelRadius + 1) * 2, height: (labelRadius + 1) * 2))
            NSColor(white: 0.0, alpha: 0.35).setStroke()
            moat.lineWidth = 0.6
            moat.stroke()

            // Colored center label (paper sticker)
            let labelColor = NSColor(red: 0.84, green: 0.46, blue: 0.34, alpha: 1.0)
            let label = NSBezierPath(ovalIn: NSRect(x: cx - labelRadius, y: cy - labelRadius, width: labelRadius * 2, height: labelRadius * 2))
            labelColor.setFill()
            label.fill()

            // Label inner darker ring (subtle paper edge)
            let labelRing = NSBezierPath(ovalIn: NSRect(x: cx - labelRadius + 0.5, y: cy - labelRadius + 0.5, width: labelRadius * 2 - 1, height: labelRadius * 2 - 1))
            NSColor(white: 0.0, alpha: 0.12).setStroke()
            labelRing.lineWidth = 0.6
            labelRing.stroke()

            // App icon, clipped to the label circle so corners don't bleed onto vinyl
            if let icon = NSImage(named: NSImage.applicationIconName) {
                NSGraphicsContext.saveGraphicsState()
                let clip = NSBezierPath(ovalIn: NSRect(x: cx - labelRadius, y: cy - labelRadius, width: labelRadius * 2, height: labelRadius * 2))
                clip.addClip()
                let iconSide = labelRadius * 1.55
                icon.draw(in: NSRect(x: cx - iconSide / 2, y: cy - iconSide / 2, width: iconSide, height: iconSide))
                NSGraphicsContext.restoreGraphicsState()
            }

            _ = ctx
            return true
        }
    }

    private static func drawGloss(size: NSSize) -> NSImage {
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = size.width / 2
            let cy = size.height / 2
            let radius = min(cx, cy) - 1

            // Clip to the disc shape so highlights don't bleed past the edge
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            clip.addClip()

            let space = CGColorSpaceCreateDeviceRGB()

            // Primary highlight — soft elliptical glow, upper-left
            if let grad = CGGradient(
                colorsSpace: space,
                colors: [
                    NSColor(white: 1.0, alpha: 0.13).cgColor,
                    NSColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) {
                let c = CGPoint(x: cx - radius * 0.32, y: cy + radius * 0.42)
                ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius * 0.95, options: [])
            }

            // Secondary glow — fainter, lower-right
            if let grad = CGGradient(
                colorsSpace: space,
                colors: [
                    NSColor(white: 1.0, alpha: 0.06).cgColor,
                    NSColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) {
                let c = CGPoint(x: cx + radius * 0.38, y: cy - radius * 0.42)
                ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius * 0.7, options: [])
            }

            // Long thin specular streak across the top — catches the eye as the disc spins past
            if let grad = CGGradient(
                colorsSpace: space,
                colors: [
                    NSColor(white: 1.0, alpha: 0.0).cgColor,
                    NSColor(white: 1.0, alpha: 0.08).cgColor,
                    NSColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0, 0.5, 1]
            ) {
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: .pi / 4)
                ctx.translateBy(x: -cx, y: -cy)
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: cx - radius, y: cy + radius * 0.55),
                    end: CGPoint(x: cx + radius, y: cy + radius * 0.55),
                    options: []
                )
                ctx.restoreGState()
            }

            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
}
