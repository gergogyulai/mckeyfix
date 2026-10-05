// MCKeyFix — makes the built-in MacBook keyboard behave for Minecraft.
//
// While Minecraft is frontmost AND the mouse is captured (you're actually in-game,
// not in a menu/inventory), it:
//   • remaps fn/🌐 → Left Control on the internal keyboard only (so fn = sprint and
//     the Globe key can't switch the input source)
//   • makes F1–F12 act as real function keys (F3, F5, … work without fn)
//   • disables the ^Space / ^⌥Space input-source shortcuts and the ^1–9 / ^arrow
//     Spaces shortcuts, so sprint + jump/hotbar doesn't trigger them
// Everything is restored the moment you leave the game, pause, or switch apps.

import AppKit
import Darwin
import IOKit.hidsystem

// MARK: - Private SkyLight API (used by lots of shortcut utilities)

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> CGError

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

// MARK: - Config

/// 60 = select previous input source (^Space), 61 = next input source (^⌥Space),
/// 79–82 = move left/right a Space (^←/^→), 118–126 = switch to Desktop 1–9 (^1–^9).
let hotKeysToDisable: [Int32] = [60, 61, 79, 80, 81, 82] + Array(118...126)

let internalKeyboard = #"{"Built-In":true,"PrimaryUsagePage":1,"PrimaryUsage":6}"#
// fn is reported as AppleVendorTopCase:0x03 or AppleVendorKeyboard:0x03 depending on the model.
// 0xFF00000003 / 0xFF0100000003 → 0x7000000E0 (Left Control)
let fnToControlMapping = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":1095216660483,"HIDKeyboardModifierMappingDst":30064771296},{"HIDKeyboardModifierMappingSrc":280379760050179,"HIDKeyboardModifierMappingDst":30064771296}]}"#

let stateFile: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MCKeyFix", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("active-state")
}()

// MARK: - System tweaks

func hidutilSet(_ json: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = ["property", "--matching", internalKeyboard, "--set", json]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

/// Sets the F-key mode the same way the System Settings switch does (0 = media keys,
/// 1 = standard function keys). `hidutil property --set HIDFKeyMode` doesn't work: the
/// keyboard filter only honours it when it arrives through this legacy parameter call.
/// Like the system switch, it applies to every keyboard.
func setFKeyMode(_ mode: Int32) {
    let handle = NXOpenEventStatus()
    var value = mode
    _ = IOHIDSetParameter(handle, "HIDFKeyMode" as CFString, &value, IOByteCount(MemoryLayout<Int32>.size))
    NXCloseEventStatus(handle)
}

/// The user's own "Use F1, F2, etc. keys as standard function keys" setting.
func userFKeyMode() -> Int32 {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    return CFPreferencesCopyAppValue("com.apple.keyboard.fnState" as CFString, kCFPreferencesAnyApplication) as? Int32 ?? 0
}

func enableFixes() -> [Int32] {
    let disabled = hotKeysToDisable.filter { CGSIsSymbolicHotKeyEnabled($0) }
    // Persist first so a crash can't leave the shortcuts off forever.
    try? disabled.map(String.init).joined(separator: ",").write(to: stateFile, atomically: true, encoding: .utf8)
    for k in disabled { _ = CGSSetSymbolicHotKeyEnabled(k, false) }
    hidutilSet(fnToControlMapping)
    setFKeyMode(1)
    return disabled
}

func disableFixes(_ disabled: [Int32]) {
    for k in disabled { _ = CGSSetSymbolicHotKeyEnabled(k, true) }
    hidutilSet(#"{"UserKeyMapping":[]}"#)
    setFKeyMode(userFKeyMode())
    try? FileManager.default.removeItem(at: stateFile)
}

/// If a previous run died while active, put everything back.
func recoverFromCrash() {
    guard let s = try? String(contentsOf: stateFile, encoding: .utf8) else { return }
    disableFixes(s.split(separator: ",").compactMap { Int32($0) })
}

// MARK: - Minecraft detection

func commandLine(of pid: pid_t) -> String {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return "" }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return "" }
    return String(decoding: buf[4..<size].map { $0 == 0 ? 32 : $0 }, as: UTF8.self)
}

/// Minecraft Java runs as a plain `java` process whose arguments mention minecraft.
/// (This deliberately excludes the launcher itself.)
func isMinecraft(_ app: NSRunningApplication) -> Bool {
    guard let exe = app.executableURL?.lastPathComponent.lowercased(), exe.hasPrefix("java") else { return false }
    return commandLine(of: app.processIdentifier).lowercased().contains("minecraft")
}

func isOnScreenEdge(_ p: CGPoint) -> Bool {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &count)
    for id in ids.prefix(Int(count)) {
        let b = CGDisplayBounds(id)
        guard b.contains(p) else { continue }
        return p.x <= b.minX + 1 || p.y <= b.minY + 1 || p.x >= b.maxX - 2 || p.y >= b.maxY - 2
    }
    return true
}

// MARK: - App

final class Controller: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    var minecraftFront = false
    var playing = false            // mouse is captured by the game
    var capturedStreak = 0
    var freeStreak = 0
    var lastLocation: CGPoint?

    var active = false
    var disabledHotKeys: [Int32] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        recoverFromCrash()

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "About MCKeyFix", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit MCKeyFix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        frontAppChanged()

        // Global monitors for mouse events don't need any permissions.
        NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] e in self?.mouseMoved(e) }

        // Retries pending switches that are waiting for fn/ctrl to be released.
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.reconcile() }

        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
        refreshUI()
    }

    var signalSources: [DispatchSourceSignal] = []

    func applicationWillTerminate(_ n: Notification) {
        if active { disableFixes(disabledHotKeys) }
    }

    @objc func frontAppChanged() {
        minecraftFront = NSWorkspace.shared.frontmostApplication.map(isMinecraft) ?? false
        // Minecraft pauses (frees the cursor) when it loses focus, so start from "not playing".
        playing = false
        capturedStreak = 0
        freeStreak = 0
        lastLocation = nil
        reconcile()
    }

    /// In-game, Minecraft detaches the cursor: mouse events keep arriving with deltas
    /// but the cursor location never changes. In menus the location moves normally.
    func mouseMoved(_ e: NSEvent) {
        guard minecraftFront, e.deltaX != 0 || e.deltaY != 0, let loc = e.cgEvent?.location else { return }
        if loc == lastLocation && !isOnScreenEdge(loc) {
            capturedStreak += 1; freeStreak = 0
        } else {
            freeStreak += 1; capturedStreak = 0
        }
        lastLocation = loc
        if capturedStreak >= 3 { playing = true }
        if freeStreak >= 2 { playing = false }
        reconcile()
    }

    func reconcile() {
        let want = minecraftFront && playing
        guard want != active else { return }
        // Never flip the remap while fn/ctrl is held, or the key-up would get
        // translated differently than the key-down and leave a modifier stuck.
        let held = CGEventSource.flagsState(.hidSystemState).intersection([.maskControl, .maskSecondaryFn])
        guard held.isEmpty else { return }

        if want { disabledHotKeys = enableFixes() } else { disableFixes(disabledHotKeys); disabledHotKeys = [] }
        active = want
        refreshUI()
    }

    @objc func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Makes the MacBook keyboard behave in Minecraft.\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(
            string: "github.com/gergogyulai/mckeyfix",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .link: URL(string: "https://github.com/gergogyulai/mckeyfix")!]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))

        // Menu bar apps aren't active by default, so the panel would open behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func refreshUI() {
        statusItem.button?.image = NSImage(
            systemSymbolName: active ? "gamecontroller.fill" : "gamecontroller",
            accessibilityDescription: "MCKeyFix")
        statusLine.title = active ? "Active — fn is Control, ^Space disabled"
                         : minecraftFront ? "Minecraft open, not in-game"
                         : "Idle — waiting for Minecraft"
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
