# CodeFM Menubar App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menubar app that plays the CodeFM YouTube live stream audio via yt-dlp and AVPlayer.

**Architecture:** Swift Package Manager executable with AppKit. Three components (StatusBarController, StreamPlayer, PlayerState) plus AppDelegate/main. A build script assembles the .app bundle with bundled yt-dlp and Info.plist.

**Tech Stack:** Swift, AppKit, AVFoundation, SPM, yt-dlp

---

## File Map

| File | Responsibility |
|------|---------------|
| `Package.swift` | SPM manifest — macOS 13+, executable target |
| `Sources/PlayerState.swift` | Enum: stopped, loading, playing, offline |
| `Sources/StreamPlayer.swift` | yt-dlp extraction + AVPlayer playback + state machine |
| `Sources/StatusBarController.swift` | NSStatusItem, SF Symbol icons, left/right click handling |
| `Sources/AppDelegate.swift` | NSApplicationDelegate, owns StatusBarController |
| `Sources/main.swift` | Entry point — creates NSApplication, sets delegate, runs |
| `Resources/Info.plist` | LSUIElement=true, bundle metadata |
| `Scripts/build-app.sh` | Compiles via SPM, assembles .app bundle |
| `.gitignore` | Swift/macOS ignores |

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `.gitignore`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p Sources Resources Scripts
```

- [ ] **Step 2: Create Package.swift**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeFM",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CodeFM",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
```

- [ ] **Step 3: Create Info.plist**

Create `Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CodeFM</string>
    <key>CFBundleIdentifier</key>
    <string>com.codefm.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>CodeFM</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
```

- [ ] **Step 4: Create build script**

Create `Scripts/build-app.sh`:

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="CodeFM"
BUILD_DIR=".build/release"
APP_BUNDLE="build/$APP_NAME.app"

echo "Building $APP_NAME..."
swift build -c release

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/"

if [ -f Resources/yt-dlp ]; then
    cp Resources/yt-dlp "$APP_BUNDLE/Contents/Resources/yt-dlp"
    chmod +x "$APP_BUNDLE/Contents/Resources/yt-dlp"
else
    echo "WARNING: Resources/yt-dlp not found. Download it before distributing."
    echo "  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos -o Resources/yt-dlp"
    echo "  chmod +x Resources/yt-dlp"
fi

echo "Done: $APP_BUNDLE"
echo "Run:  open $APP_BUNDLE"
echo "Install: cp -r $APP_BUNDLE /Applications/"
```

- [ ] **Step 5: Create .gitignore**

Create `.gitignore`:

```
.build/
build/
.swiftpm/
.DS_Store
Resources/yt-dlp
```

- [ ] **Step 6: Verify SPM resolves**

Run: `swift package resolve`

Expected: clean resolve, no errors.

- [ ] **Step 7: Commit**

```bash
git init
git add Package.swift Resources/Info.plist Scripts/build-app.sh .gitignore
git commit -m "chore: project scaffolding — SPM, Info.plist, build script"
```

---

### Task 2: PlayerState Enum

**Files:**
- Create: `Sources/PlayerState.swift`

- [ ] **Step 1: Create PlayerState.swift**

Create `Sources/PlayerState.swift`:

```swift
import AppKit

enum PlayerState {
    case stopped
    case loading
    case playing
    case offline

    var symbolName: String {
        switch self {
        case .stopped, .loading, .offline:
            return "play.circle.fill"
        case .playing:
            return "pause.circle.fill"
        }
    }

    var opacity: CGFloat {
        switch self {
        case .offline:
            return 0.3
        default:
            return 1.0
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .stopped:
            return "CodeFM — Stopped"
        case .loading:
            return "CodeFM — Loading"
        case .playing:
            return "CodeFM — Playing"
        case .offline:
            return "CodeFM — Offline"
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`

Expected: build will fail because there's no `main.swift` yet — that's fine. Verify no syntax errors in `PlayerState.swift` by checking the error is only about missing entry point, not about this file.

- [ ] **Step 3: Commit**

```bash
git add Sources/PlayerState.swift
git commit -m "feat: add PlayerState enum with icon mapping"
```

---

### Task 3: StreamPlayer

**Files:**
- Create: `Sources/StreamPlayer.swift`

- [ ] **Step 1: Create StreamPlayer.swift**

Create `Sources/StreamPlayer.swift`:

```swift
import AVFoundation
import Foundation

final class StreamPlayer {
    private static let youtubeURL = "https://www.youtube.com/live/YmQ7jRgf4f0"

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var extractionProcess: Process?

    var onStateChange: ((PlayerState) -> Void)?

    private(set) var state: PlayerState = .stopped {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
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

    private func play() {
        state = .loading
        extractAudioURL { [weak self] url in
            DispatchQueue.main.async {
                guard let self else { return }
                if let url {
                    self.startPlayback(url: url)
                } else {
                    self.state = .offline
                }
            }
        }
    }

    private func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        extractionProcess?.terminate()
        extractionProcess = nil
        state = .stopped
    }

    private func extractAudioURL(completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ytdlpPath = Bundle.main.path(forResource: "yt-dlp", ofType: nil)
                ?? self?.findYtdlpInPath()

            guard let ytdlpPath else {
                completion(nil)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlpPath)
            process.arguments = ["-f", "bestaudio", "--get-url", StreamPlayer.youtubeURL]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            self?.extractionProcess = process

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    completion(nil)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let urlString = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let urlString, let url = URL(string: urlString) {
                    completion(url)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
    }

    private func findYtdlpInPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func startPlayback(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        statusObservation = item.observe(\.status) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.state = .playing
                case .failed:
                    self.player = nil
                    self.statusObservation = nil
                    self.state = .offline
                default:
                    break
                }
            }
        }

        player.play()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`

Expected: still fails on missing entry point only — no errors from `StreamPlayer.swift` or `PlayerState.swift`.

- [ ] **Step 3: Commit**

```bash
git add Sources/StreamPlayer.swift
git commit -m "feat: add StreamPlayer — yt-dlp extraction and AVPlayer playback"
```

---

### Task 4: StatusBarController

**Files:**
- Create: `Sources/StatusBarController.swift`

- [ ] **Step 1: Create StatusBarController.swift**

Create `Sources/StatusBarController.swift`:

```swift
import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let streamPlayer: StreamPlayer
    private let menu: NSMenu

    init(streamPlayer: StreamPlayer) {
        self.streamPlayer = streamPlayer
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.menu = NSMenu()

        super.init()

        setupButton()
        setupMenu()

        streamPlayer.onStateChange = { [weak self] state in
            self?.updateIcon(for: state)
        }

        updateIcon(for: .stopped)
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupMenu() {
        menu.addItem(
            NSMenuItem(
                title: "Quit CodeFM",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            streamPlayer.togglePlayback()
        }
    }

    private func updateIcon(for state: PlayerState) {
        guard let button = statusItem.button else { return }

        let image = NSImage(
            systemSymbolName: state.symbolName,
            accessibilityDescription: state.accessibilityLabel
        )
        image?.isTemplate = true

        button.image = image
        button.alphaValue = state.opacity
        button.toolTip = state.accessibilityLabel
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`

Expected: still fails on missing entry point only.

- [ ] **Step 3: Commit**

```bash
git add Sources/StatusBarController.swift
git commit -m "feat: add StatusBarController — menubar icon and click handling"
```

---

### Task 5: AppDelegate and Entry Point

**Files:**
- Create: `Sources/AppDelegate.swift`
- Create: `Sources/main.swift`

- [ ] **Step 1: Create AppDelegate.swift**

Create `Sources/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let streamPlayer = StreamPlayer()
        statusBarController = StatusBarController(streamPlayer: streamPlayer)
    }
}
```

- [ ] **Step 2: Create main.swift**

Create `Sources/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Verify full build succeeds**

Run: `swift build -c release 2>&1 | tail -5`

Expected: `Build complete!` — no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppDelegate.swift Sources/main.swift
git commit -m "feat: add AppDelegate and main entry point — app builds"
```

---

### Task 6: Download yt-dlp, Build App Bundle, and Test

**Files:**
- Modify: `Scripts/build-app.sh` (make executable)

- [ ] **Step 1: Download yt-dlp binary**

```bash
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos -o Resources/yt-dlp
chmod +x Resources/yt-dlp
```

Verify: `Resources/yt-dlp --version` should print a version string.

- [ ] **Step 2: Make build script executable and run it**

```bash
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
```

Expected output:
```
Building CodeFM...
Build complete!
Assembling app bundle...
Done: build/CodeFM.app
Run:  open build/CodeFM.app
Install: cp -r build/CodeFM.app /Applications/
```

- [ ] **Step 3: Launch the app and verify menubar icon**

```bash
open build/CodeFM.app
```

Verify manually:
1. A `play.circle.fill` icon appears in the menubar (solid circle with play triangle cut out).
2. No dock icon appears.
3. No window opens.

- [ ] **Step 4: Test left-click — play**

Left-click the menubar icon.

Verify:
1. After 1-2 seconds (yt-dlp extraction), audio begins playing.
2. Icon changes to `pause.circle.fill` (solid circle with pause bars cut out).

- [ ] **Step 5: Test left-click — pause**

Left-click the menubar icon again.

Verify:
1. Audio stops immediately.
2. Icon changes back to `play.circle.fill`.

- [ ] **Step 6: Test right-click — quit menu**

Right-click the menubar icon.

Verify:
1. A small menu appears with "Quit CodeFM".
2. Click "Quit CodeFM" — app exits, icon disappears from menubar.

- [ ] **Step 7: Commit**

```bash
git add Scripts/build-app.sh
git commit -m "feat: build script and manual verification complete"
```

---

## Verification Checklist

After all tasks, verify each spec requirement:

- [ ] App lives in menubar only (no dock icon, no window)
- [ ] Left-click toggles play/pause
- [ ] Right-click shows quit menu
- [ ] Stopped state: `play.circle.fill` at full opacity
- [ ] Playing state: `pause.circle.fill` at full opacity
- [ ] Offline state: `play.circle.fill` at ~30% opacity
- [ ] Audio plays from the YouTube live stream
- [ ] Icons adapt to light/dark mode (template images)
- [ ] yt-dlp is bundled in the .app Resources folder
