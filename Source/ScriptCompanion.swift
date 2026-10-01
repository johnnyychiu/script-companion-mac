// Script Companion 0.5.3 — local macOS prototype.
// Build on macOS 13+ using Build Mac App.command. No third-party native frameworks.
import AppKit
import WebKit
import Carbon
import CoreGraphics
import ApplicationServices

final class ReaderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct PowerPointState {
    let payload: [String: Any]
    var number: Int { payload["number"] as? Int ?? 0 }
    var total: Int { payload["total"] as? Int ?? 0 }
    var name: String { payload["name"] as? String ?? "PowerPoint" }
    var identity: String { payload["identity"] as? String ?? name }
}

// Drain both subprocess pipes concurrently. Waiting before draining can deadlock
// when a presentation contains more notes than the operating system pipe buffer.
final class PipeCapture {
    private let lock = NSLock()
    private var data = Data()
    private var exceeded = false
    func collect(_ handle: FileHandle, limit: Int) {
        while true {
            let chunk = handle.readData(ofLength: 65536)
            if chunk.isEmpty { break }
            lock.lock()
            if data.count + chunk.count <= limit { data.append(chunk) }
            else { exceeded = true } // Continue draining even after the size limit.
            lock.unlock()
        }
    }
    func result() -> (Data, Bool) {
        lock.lock(); defer { lock.unlock() }; return (data, exceeded)
    }
}

enum CompanionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    private var panel: ReaderPanel!
    private var web: WKWebView!
    private var statusItem: NSStatusItem!
    private var screensMenu = NSMenu()
    private var hotkeyMenuItem: NSMenuItem!
    private var pinnedDisplay: CGDirectDisplayID = 0
    private var positioning = false
    private var didPlaceReader = false
    private var displayWarningShown = false
    private var followTimer: Timer?
    private var following = false
    private var busy = false
    private var linkedName = ""
    private var linkedIdentity = ""
    private var navigationAvailable = true
    private let slideButtons = SlideButtonController()
    // Lightweight position checks do not load the notes/JSON framework script.
    private var lastNotesRefresh = Date.distantPast
    private var lastObservedNumber = 0
    private var lastObservedTotal = 0
    private var lastObservedID = ""
    private var cachedSlideIDs: [Int: String] = [:]
    private var navigationStartedAt: TimeInterval?
    private var lastNavigationFinished: TimeInterval = 0
    private var lastNavigationDiagnostic = "No slide-button request yet."
    private var arrowMenuItem: NSMenuItem!
    private var arrowTap: CFMachPort?
    private var arrowSource: CFRunLoopSource?
    private var consumedArrowKeys = Set<Int64>()
    private var arrowModeEnabled = false
    private var interactionBlocked = false
    private var lastLiveUpdate = Date.distantPast
    private var pendingStep: String?
    private var generation = 0
    private let scriptQueue = DispatchQueue(label: "local.scriptcompanion.powerpoint")
    private let saveQueue = DispatchQueue(label: "local.scriptcompanion.saves")
    private var hotkeys: [EventHotKeyRef] = []
    private var hotkeyHandler: EventHandlerRef?
    private var hotkeysEnabled = false
    private let resources = Bundle.main.resourceURL!
    private let stateURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Script Companion/state.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        createReader()
        pinnedDisplay = NSScreen.screens.first(where: { CGDisplayIsBuiltin(displayID($0)) != 0 }).map(displayID)
            ?? NSScreen.screens.first.map(displayID) ?? 0
        rebuildScreenMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        showReader()
    }

    private func createReader() {
        let controller = WKUserContentController()
        controller.add(self, name: "companion")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 920, height: 700), configuration: configuration)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.underPageBackgroundColor = NSColor(calibratedWhite: 0.065, alpha: 1)
        panel = ReaderPanel(contentRect: web.frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Script Companion 0.5.3 — notes at the top"
        panel.contentMinSize = NSSize(width: 640, height: 540)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor(calibratedWhite: 0.065, alpha: 1)
        panel.contentView = web
        panel.delegate = self
        let url = resources.appendingPathComponent("reader.html")
        web.loadFileURL(url, allowingReadAccessTo: resources)
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "▤ Script"
        statusItem.button?.toolTip = "Script Companion"
        let menu = NSMenu()
        menu.addItem(item("Show reader", #selector(showReader)))
        menu.addItem(item("Move reader to top", #selector(moveReaderToTop)))
        menu.addItem(item("Hide reader", #selector(hideReader)))
        menu.addItem(.separator())
        let screenItem = NSMenuItem(title: "Presenter display", action: nil, keyEquivalent: "")
        screenItem.submenu = screensMenu
        menu.addItem(screenItem)
        hotkeyMenuItem = item("Enable global line keys (⌘⌥↑ / ⌘⌥↓)", #selector(toggleHotkeys))
        menu.addItem(hotkeyMenuItem)
        arrowMenuItem = item("PowerPoint line keys — ↑↓ only (presentation only)", #selector(toggleArrowMode))
        menu.addItem(arrowMenuItem)
        menu.addItem(item("Set up slideshow window for buttons", #selector(setupSlideButtons)))
        menu.addItem(item("Save slide-control diagnostic…", #selector(saveControlDiagnostic)))
        menu.addItem(item("Unlink PowerPoint", #selector(unlinkFromMenu)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Script Companion", #selector(quitApp), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        result.target = self
        return result
    }

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func selectedScreen() -> NSScreen? { NSScreen.screens.first { displayID($0) == pinnedDisplay } }

    private func mirrored() -> Bool {
        // Be conservative: hide the script if any attached active display is in a mirror set.
        NSScreen.screens.contains { CGDisplayIsInMirrorSet(displayID($0)) != 0 }
    }

    private func rebuildScreenMenu() {
        screensMenu.removeAllItems()
        for screen in NSScreen.screens {
            let id = displayID(screen)
            let builtIn = CGDisplayIsBuiltin(id) != 0 ? " (built-in)" : ""
            let row = item(screen.localizedName + builtIn, #selector(selectScreen(_:)))
            row.representedObject = NSNumber(value: id)
            row.state = id == pinnedDisplay ? .on : .off
            screensMenu.addItem(row)
        }
    }

    @objc private func selectScreen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NSNumber else { return }
        panel.orderOut(nil)
        pinnedDisplay = id.uint32Value
        rebuildScreenMenu()
        showReader()
    }

    @objc private func displaysChanged() {
        // Never allow a disconnected presenter screen to move private text to the projector.
        panel.orderOut(nil)
        unlink("Display configuration changed. Check the projector, then link again.")
        rebuildScreenMenu()
        guard selectedScreen() != nil, !mirrored() else {
            showDisplayWarning()
            return
        }
        displayWarningShown = false
        // Deliberately require Show reader after changing the display topology.
        notify("The displays changed. Check extended-display mode, then use the ▤ Script menu → Show reader.")
    }

    private func showDisplayWarning() {
        guard !displayWarningShown else { return }
        displayWarningShown = true
        let alert = NSAlert()
        alert.messageText = "Script hidden for display safety"
        alert.informativeText = "Use extended displays, not mirroring. If your presenter display was disconnected, choose it again in the ▤ Script menu. Check the projector before showing the reader. This check cannot detect screen sharing or every adapter configuration."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showReader() {
        guard selectedScreen() != nil, !mirrored() else { panel?.orderOut(nil); showDisplayWarning(); return }
        displayWarningShown = false
        positionOnPresenterDisplay()
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func hideReader() { disableArrowMode(); panel.orderOut(nil) }

    // Move to the top of the selected display's usable area, not over the
    // system menu bar/camera housing or onto a different (audience) display.
    @objc private func moveReaderToTop() {
        guard selectedScreen() != nil, !mirrored() else {
            panel?.orderOut(nil)
            showDisplayWarning()
            return
        }
        displayWarningShown = false
        positionOnPresenterDisplay(snapToTop: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func positionOnPresenterDisplay(snapToTop: Bool = false) {
        guard let screen = selectedScreen(), !positioning else { return }
        positioning = true
        defer { positioning = false }
        let visible = screen.visibleFrame
        // Retain the existing side/bottom margins; remove only the artificial
        // 14-point TOP margin. visibleFrame still protects system-reserved space.
        let area = NSRect(x: visible.minX + 14, y: visible.minY + 14,
                          width: max(0, visible.width - 28),
                          height: max(0, visible.height - 14))
        var frame = panel.frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        if !didPlaceReader || panel.screen.map(displayID) != pinnedDisplay {
            frame.origin = NSPoint(x: area.midX - frame.width / 2, y: area.maxY - frame.height)
        }
        if snapToTop { frame.origin.y = area.maxY - frame.height }
        frame.origin.x = max(area.minX, min(frame.origin.x, area.maxX - frame.width))
        frame.origin.y = max(area.minY, min(frame.origin.y, area.maxY - frame.height))
        panel.setFrame(frame, display: true)
        didPlaceReader = true
    }
    func windowDidMove(_ notification: Notification) { positionOnPresenterDisplay() }
    func windowDidResize(_ notification: Notification) { positionOnPresenterDisplay() }
    func windowWillClose(_ notification: Notification) { unlink("Reader closed. Manual mode is available when reopened.") }

    private func emit(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.Companion && window.Companion.receive(\(json));", completionHandler: nil)
    }
    private func notify(_ message: String) { emit(["type": "error", "message": message]) }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, url.isFileURL,
              url.standardizedFileURL.path == resources.appendingPathComponent("reader.html").standardizedFileURL.path,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            var payload: [String: Any] = ["type": "ready"]
            if let data = try? Data(contentsOf: stateURL), data.count <= 40_000_000,
               let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { payload["state"] = state }
            let timerURL = stateURL.deletingLastPathComponent().appendingPathComponent("timer.json")
            if let data = try? Data(contentsOf: timerURL), data.count <= 300_000,
               let timer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { payload["timer"] = timer }
            emit(payload)
        case "saveTimer":
            guard let timer = body["timer"] as? [String: Any],
                  let elapsed = timer["elapsedMs"] as? Double, elapsed.isFinite, elapsed >= 0,
                  JSONSerialization.isValidJSONObject(timer),
                  let data = try? JSONSerialization.data(withJSONObject: timer), data.count <= 300_000 else { return }
            let destination = stateURL.deletingLastPathComponent().appendingPathComponent("timer.json")
            saveQueue.async { [weak self] in
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destination, options: .atomic)
                } catch { DispatchQueue.main.async { self?.emit(["type": "timerSaveError"]) } }
            }
        case "saveState":
            guard let state = body["state"] as? [String: Any],
                  let raw = state["raw"] as? String, raw.utf8.count <= 8_100_000,
                  let data = try? JSONSerialization.data(withJSONObject: state), data.count <= 40_000_000 else { emit(["type": "saveError"]); return }
            let destination = stateURL
            saveQueue.async { [weak self] in
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destination, options: .atomic)
                    DispatchQueue.main.async { self?.emit(["type": "saved"]) }
                } catch { DispatchQueue.main.async { self?.emit(["type": "saveError"]) } }
            }
        case "exportBackup":
            guard let content = body["content"] as? String, content.utf8.count <= 40_000_000 else { return }
            let save = NSSavePanel()
            save.nameFieldStringValue = String((body["name"] as? String ?? "script.json").prefix(240))
            save.canCreateDirectories = true
            if save.runModal() == .OK, let url = save.url {
                do { try content.write(to: url, atomically: true, encoding: .utf8) }
                catch { notify("Backup could not be saved: \(error.localizedDescription)") }
            }
        case "link": linkPowerPoint(expected: body["expectedName"] as? String ?? "")
        case "unlink": unlink("PowerPoint unlinked. Slide buttons now change only the script.")
        case "powerPointStep":
            guard let direction = body["direction"] as? String else { return }
            requestSlideStep(direction)
        case "configureSlideButtons": setupSlideButtons()
        case "refreshNotes":
            guard following, !busy else { notify("Wait for the current PowerPoint request to finish before refreshing."); return }
            fetchPowerPoint(command: "snapshot", initial: false, expectedImported: "")
        case "toggleArrowMode": toggleArrowMode()
        case "disableArrowMode": disableArrowMode()
        case "interaction": interactionBlocked = body["blocked"] as? Bool ?? false
        case "compact":
            let compact = body["value"] as? Bool ?? false
            let size = compact ? NSSize(width: 660, height: 540) : NSSize(width: 920, height: 700)
            panel.setContentSize(size)
            positionOnPresenterDisplay()
        default: break
        }
    }

    private func isPowerPointRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { ($0.bundleIdentifier ?? "").lowercased() == "com.microsoft.powerpoint" }
    }

    private func linkPowerPoint(expected: String) {
        guard !busy, !mirrored() else { notify("Check the display arrangement before linking."); return }
        guard isPowerPointRunning() else { unlink("Open PowerPoint and start its slideshow before linking."); return }
        generation += 1
        fetchPowerPoint(command: "status", initial: true, expectedImported: expected)
    }

    private func requestSlideStep(_ direction: String) {
        guard following, navigationAvailable, ["next", "previous"].contains(direction), !mirrored(), panel.isVisible, !interactionBlocked else {
            emit(["type": "error", "message": "The reader must be visible, linked, and not editing to change a PowerPoint slide."])
            return
        }
        if navigationStartedAt == nil { navigationStartedAt = ProcessInfo.processInfo.systemUptime }
        // Keep at most one deliberate keypress while a polling request finishes.
        // Autorepeat is suppressed by the browser and the native event tap.
        if busy { pendingStep = direction; emit(["type": "busy", "message": "Waiting to change PowerPoint slide…"]); return }
        navigateWithKeyboard(direction)
    }

    private func fetchPowerPoint(command: String, initial: Bool, expectedImported: String) {
        guard ["position", "status", "snapshot"].contains(command), !busy else { return }
        guard isPowerPointRunning() else { unlink("PowerPoint is no longer running."); return }
        busy = true
        let epoch = generation
        let expected = initial ? "" : linkedIdentity
        if command == "snapshot" {
            emit(["type": "busy", "message": command == "snapshot" ? "Reading all PowerPoint speaker notes…" : "Changing PowerPoint slide…"])
        }
        let script = resources.appendingPathComponent("PowerPoint.applescript")
        scriptQueue.async { [weak self] in
            let result: Result<PowerPointState, Error>
            do { result = .success(try Self.runPowerPoint(script: script, command: command, expected: expected)) }
            catch { result = .failure(error) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard epoch == self.generation else { return }
                self.busy = false
                switch result {
                case .failure(let error):
                    self.unlink("Live sync stopped: \(error.localizedDescription) The reader now holds a snapshot, not live notes. PowerPoint arrow capture is OFF.")
                case .success(let status):
                    self.recordLiveStatus(status)
                    if initial {
                        let alert = NSAlert()
                        alert.messageText = "Read notes from this PowerPoint slideshow?"
                        var details = "\(status.name)\n\(status.total) slides · currently slide \(status.number)\n\nThis replaces this reader's script with PowerPoint's notes without editing the file. Save a backup first to keep a custom script.\n\n0.5.3 uses a guarded slide-number + Return shortcut for the reader's slide buttons, not the rejected AppleScript command. Choose Slide buttons: Set up after linking, select the slideshow window and grant Accessibility permission.\n\nButtons jump absolute slides in deck order, skipping animation steps. Custom shows are not supported. Plain left/right keys while POWERPOINT is focused still perform its normal slide/animation action. Up/Down line capture is a separate opt-in."
                        if !expectedImported.isEmpty && expectedImported.caseInsensitiveCompare(status.name) != .orderedSame {
                            details += "\n\nYour previous imported file was \(expectedImported)."
                        }
                        alert.informativeText = details
                        alert.addButton(withTitle: "Link and read notes")
                        alert.addButton(withTitle: "Cancel")
                        guard alert.runModal() == .alertFirstButtonReturn else { self.unlink("Link cancelled. Manual mode."); return }
                        guard epoch == self.generation, !self.mirrored() else { self.unlink("Displays changed. Check the setup and link again."); return }
                        self.linkedName = status.name
                        self.linkedIdentity = status.identity
                        self.following = true
                        self.navigationAvailable = true
                        self.slideButtons.reset()
                        self.emit(["type": "slideButtons", "configured": false])
                        self.emit(["type": "linked", "name": status.name, "identity": status.identity])
                        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
                            guard let self = self, self.following, !self.busy else { return }
                            self.fetchPowerPoint(command: self.nextPollCommand(), initial: false, expectedImported: "")
                        }
                        self.followTimer?.invalidate()
                        self.followTimer = timer
                        RunLoop.main.add(timer, forMode: .common)
                    }
                    if let warning = status.payload["navigationError"] as? String, !warning.isEmpty {
                        // The show can still be readable when a slide-jump command is rejected.
                        // Pause only the experimental direct slide buttons. Line-only capture
                        // can remain on: horizontal keys go straight to PowerPoint unchanged.
                        self.navigationAvailable = false
                        self.pendingStep = nil
                    }
                    let queued = self.navigationAvailable ? self.pendingStep : nil
                    self.pendingStep = nil
                    var payload = status.payload
                    if status.payload["positionOnly"] as? Bool == true { payload["name"] = self.linkedName }
                    payload["type"] = "slide"
                    payload["busy"] = queued != nil
                    payload["navigationAvailable"] = self.navigationAvailable
                    self.emit(payload)
                    if initial {
                        self.fetchPowerPoint(command: "snapshot", initial: false, expectedImported: "")
                    } else if let queued = queued, self.following {
                        self.requestSlideStep(queued)
                    }
                }
            }
        }
    }


    private func recordLiveStatus(_ status: PowerPointState) {
        lastLiveUpdate = Date()
        lastObservedNumber = status.number; lastObservedTotal = status.total
        if let rows = status.payload["slides"] as? [[String: Any]] {
            cachedSlideIDs = [:]
            for row in rows {
                if let n = row["number"] as? Int { cachedSlideIDs[n] = row["id"] as? String ?? "" }
            }
        }
        if let current = status.payload["current"] as? [String: Any] {
            let id = current["id"] as? String ?? ""
            cachedSlideIDs[status.number] = id
            lastObservedID = id
            lastNotesRefresh = Date()
        } else { lastObservedID = status.payload["slideID"] as? String ?? "" }
    }

    private func nextPollCommand() -> String {
        // A changed count needs a new deck; never assume cached indexes still match.
        if cachedSlideIDs.count != lastObservedTotal { return "snapshot" }
        if cachedSlideIDs[lastObservedNumber] == nil ||
            (!lastObservedID.isEmpty && cachedSlideIDs[lastObservedNumber] != lastObservedID) { return "status" }
        // Reuse already-read notes for quick slide changes. Refresh notes periodically
        // when not in a burst of button presses; explicit Refresh notes remains available.
        if Date().timeIntervalSince(lastNotesRefresh) >= 3.0 &&
            ProcessInfo.processInfo.systemUptime - lastNavigationFinished >= 0.6 { return "status" }
        return "position"
    }

    @objc private func setupSlideButtons() {
        guard following, !busy, panel.isVisible, !mirrored(), !interactionBlocked else {
            notify("Link PowerPoint and finish the current request before setting up slide buttons."); return
        }
        let epoch = generation
        busy = true // Pause polling while the native setup dialog is open.
        emit(["type": "busy", "message": "Choosing a slideshow window…"])
        do {
            let configured = try slideButtons.configure(presentation: linkedName)
            guard epoch == generation else { busy = false; slideButtons.reset(); return }
            emit(["type": "slideButtons", "configured": configured])
            emit(["type": "navigationResult", "ok": configured, "message": configured
                ? "Slide buttons ready to test. Click PPT slide →. The reader will verify PowerPoint's actual slide before moving the script."
                : "Slide-button setup cancelled. Notes are still following PowerPoint."])
        } catch {
            emit(["type": "slideButtons", "configured": false])
            emit(["type": "navigationResult", "ok": false, "message": error.localizedDescription])
        }
        busy = false
        navigationStartedAt = nil
    }

    private func navigateWithKeyboard(_ direction: String) {
        guard following, !busy else { return }
        if !slideButtons.isConfigured {
            setupSlideButtons()
            // Setup never also changes a slide. A second, explicit click is needed.
            return
        }
        busy = true
        pendingStep = nil
        let epoch = generation, expected = linkedIdentity
        let restoreReaderFocus = panel.isKeyWindow
        let initialFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let script = resources.appendingPathComponent("PowerPoint.applescript")
        lastNavigationDiagnostic = "Reading current slide before \(direction)."
        emit(["type": "busy", "message": "Checking PowerPoint before slide change…"])
        scriptQueue.async { [weak self] in
            let result: Result<PowerPointState, Error>
            do { result = .success(try Self.runPowerPoint(script: script, command: "position", expected: expected)) }
            catch { result = .failure(error) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.generation == epoch, self.following else { return }
                switch result {
                case .failure(let error):
                    self.busy = false
                    self.unlink("PowerPoint status could not be verified. No slide shortcut was sent. \(error.localizedDescription)")
                case .success(let before):
                    guard let target = SlideNavigationPolicy.target(current: before.number, total: before.total, direction: direction) else {
                        self.finishKeyboardStep(before, epoch: epoch, warning: "Invalid slide target. No shortcut sent.", restoreFocus: false); return
                    }
                    if target == before.number {
                        self.finishKeyboardStep(before, epoch: epoch, warning: nil, restoreFocus: false); return
                    }
                    self.lastNavigationDiagnostic = "Requested \(before.number) → \(target) of \(before.total); shortcut not yet sent."
                    self.panel.resignKey()
                    self.slideButtons.send(slide: target, stillAllowed: { [weak self] in
                        guard let self = self else { return false }
                        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
                        return self.following && self.generation == epoch && !self.mirrored()
                            && self.panel.isVisible && !self.interactionBlocked && !self.panel.attachedSheetIsVisible
                            && (frontID == "com.microsoft.powerpoint" || frontID == Bundle.main.bundleIdentifier?.lowercased()
                                || NSWorkspace.shared.frontmostApplication?.processIdentifier == initialFrontPID)
                    }, completion: { [weak self] error in
                        guard let self = self else { return }
                        guard self.generation == epoch, self.following else { return }
                        self.verifyKeyboardStep(before: before, target: target, epoch: epoch,
                            shortcutError: error?.localizedDescription, restoreFocus: restoreReaderFocus)
                    })
                }
            }
        }
    }

    private func verifyKeyboardStep(before: PowerPointState, target: Int, epoch: Int,
                                    shortcutError: String?, restoreFocus: Bool) {
        let script = resources.appendingPathComponent("PowerPoint.applescript")
        emit(["type": "busy", "message": "Verifying PowerPoint's actual slide…"])
        // The serial queue holds this transaction; no other poll runs between its reads.
        scriptQueue.async { [weak self] in
            var observed: PowerPointState?
            var readError: String?
            let attempts = shortcutError == nil ? 6 : 1
            for attempt in 0..<attempts {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.12) }
                do {
                    let status = try Self.runPowerPoint(script: script, command: "position", expected: before.identity)
                    observed = status
                    // Only reads are retried. NEVER resend a key or add a second slide step.
                    if shortcutError != nil || status.total != before.total ||
                        SlideNavigationPolicy.observe(before: before.number, target: target, actual: status.number, total: status.total) != .unchanged { break }
                } catch { readError = error.localizedDescription; break }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.generation == epoch, self.following else { return }
                guard readError == nil, let status = observed else {
                    self.busy = false
                    self.lastNavigationDiagnostic = "Navigation unverified: \(readError ?? "no status"). No automatic resend."
                    self.unlink("PowerPoint could not confirm the slide after keyboard control. No further shortcut was sent. Check the projector before retrying. \(readError ?? "No status was returned.")")
                    return
                }
                var warning = shortcutError
                if warning == nil && status.total != before.total {
                    warning = "The slide count changed during navigation. The reader is following the actual slide; no retry was sent."
                }
                if warning == nil && status.number != target {
                    warning = "Slide change not confirmed: requested slide \(target), but PowerPoint reports slide \(status.number). No automatic retry was sent. Check the selected slideshow window and test number + Return directly in Presenter View. Notes still follow the actual slide."
                }
                self.lastNavigationDiagnostic = "Before=\(before.number); requested=\(target); confirmed=\(status.number); total=\(status.total); " + (warning ?? "confirmed")
                self.finishKeyboardStep(status, epoch: epoch, warning: warning, restoreFocus: restoreFocus)
            }
        }
    }

    private func finishKeyboardStep(_ status: PowerPointState, epoch: Int, warning: String?, restoreFocus: Bool) {
        guard epoch == generation, following else { return }
        busy = false
        pendingStep = nil // No deferred click after a completed/failed transaction.
        recordLiveStatus(status)
        lastNavigationFinished = ProcessInfo.processInfo.systemUptime
        navigationAvailable = true // A keyboard failure must not permanently lock the buttons.
        var payload = status.payload
        if status.payload["positionOnly"] as? Bool == true { payload["name"] = linkedName }
        payload["type"] = "slide"; payload["busy"] = false; payload["navigationAvailable"] = true
        payload["navigationMethod"] = "keyboard-number-return"
        emit(payload)
        let elapsedMS = navigationStartedAt.map { max(0, (ProcessInfo.processInfo.systemUptime - $0) * 1000) }
        if let elapsedMS = elapsedMS { lastNavigationDiagnostic += "; elapsed=\(Int(elapsedMS)) ms (including preflight and confirmation)" }
        navigationStartedAt = nil
        var result: [String: Any] = ["type": "navigationResult", "ok": warning == nil,
            "message": warning ?? "PowerPoint confirmed slide \(status.number) / \(status.total)."]
        if let elapsedMS = elapsedMS { result["durationMs"] = elapsedMS }
        emit(result)
        // Restore focus only if the user was in this reader when they requested the step.
        // Do not steal focus back if they switched to a different app during verification.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
        if restoreFocus, panel.isVisible, !mirrored(), front == "com.microsoft.powerpoint" {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func saveControlDiagnostic() {
        let ppt = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint" }
        let pptBundle = ppt?.bundleURL.flatMap { Bundle(url: $0) }
        let version = pptBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let report = "Script Companion 0.5.3 — slide-control diagnostic\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nPowerPoint version: \(version)\nAccessibility trusted: \(AXIsProcessTrusted())\nLinked: \(following)\nSlide buttons configured: \(slideButtons.isConfigured)\nLast navigation: \(lastNavigationDiagnostic)\n\nNo speaker-note text is included. Review the report before sharing; system error messages may contain local paths.\n"
        let dialog = NSSavePanel(); dialog.nameFieldStringValue = "Script Companion slide diagnostic.txt"
        if dialog.runModal() == .OK, let url = dialog.url {
            do { try report.write(to: url, atomically: true, encoding: .utf8) }
            catch { notify("Could not save diagnostic: \(error.localizedDescription)") }
        }
    }

    private static func runPowerPoint(script: URL, command: String, expected: String) throws -> PowerPointState {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let base = command == "position"
            ? script.deletingLastPathComponent().appendingPathComponent("PowerPointPosition.applescript") : script
        let compiled = base.deletingPathExtension().appendingPathExtension("scpt")
        let adapter = FileManager.default.fileExists(atPath: compiled.path) ? compiled : base
        task.arguments = command == "position" ? [adapter.path, expected] : [adapter.path, command, expected]
        let output = Pipe(), errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        try task.run()
        let collectedOutput = PipeCapture(), collectedErrors = PipeCapture()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async {
            collectedOutput.collect(output.fileHandleForReading, limit: 12_000_000)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            collectedErrors.collect(errors.fileHandleForReading, limit: 100_000)
            readers.leave()
        }
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + (command == "snapshot" ? 65 : 12), execute: timeout)
        task.waitUntilExit()
        timeout.cancel()
        readers.wait()
        let (outputData, tooLarge) = collectedOutput.result()
        let (errorData, _) = collectedErrors.result()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else {
            if errorText.contains("-1743") || errorText.lowercased().contains("not authorized") || errorText.lowercased().contains("not authorised") {
                throw CompanionError.message("Allow Script Companion to control PowerPoint in System Settings → Privacy & Security → Automation, then link again.")
            }
            throw CompanionError.message(errorText.isEmpty ? "PowerPoint did not respond." : String(errorText.suffix(900)))
        }
        guard !tooLarge else { throw CompanionError.message("Notes are too large for this prototype. Use a shorter deck or import a saved script.") }
        if command == "position" {
            guard let position = PowerPointPositionParser.parse(outputData), !expected.isEmpty else {
                throw CompanionError.message("PowerPoint returned unsupported slide-position data. No slide input was assumed to succeed.")
            }
            return PowerPointState(payload: ["number": position.number, "total": position.total, "slideID": position.slideID,
                "name": "", "identity": expected, "positionOnly": true])
        }
        guard let payload = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
              let number = payload["number"] as? Int, let total = payload["total"] as? Int,
              let _ = payload["name"] as? String, let _ = payload["identity"] as? String,
              number > 0, number <= total, total <= 2000,
              let current = payload["current"] as? [String: Any], current["number"] as? Int == number else {
            throw CompanionError.message("This PowerPoint version returned unsupported live-notes data.")
        }
        return PowerPointState(payload: payload)
    }

    @objc private func unlinkFromMenu() { unlink("PowerPoint unlinked. Last notes are a snapshot; slide keys now change only the reader.") }
    private func unlink(_ reason: String) {
        generation += 1
        following = false
        busy = false
        cachedSlideIDs = [:]
        lastNotesRefresh = .distantPast
        navigationStartedAt = nil
        lastObservedNumber = 0; lastObservedTotal = 0; lastObservedID = ""
        linkedName = ""
        linkedIdentity = ""
        pendingStep = nil
        slideButtons.reset()
        emit(["type": "slideButtons", "configured": false])
        lastLiveUpdate = Date.distantPast
        disableArrowMode()
        followTimer?.invalidate()
        followTimer = nil
        emit(["type": "unlinked", "message": reason])
    }

    // Explicit, session-only UP/DOWN capture. LEFT/RIGHT always pass unchanged
    // to PowerPoint. No AppleScript navigation or synthetic keyboard events are
    // used for these horizontal keys, including when direct slide control failed.
    // An active tap prevents UP/DOWN also advancing PowerPoint slides.
    @objc private func toggleArrowMode() {
        if arrowModeEnabled { disableArrowMode(); return }
        guard following, panel.isVisible, !mirrored(), !interactionBlocked else { notify("Link PowerPoint, close reader dialogs, and show the reader before enabling PowerPoint line keys."); return }
        let alert = NSAlert()
        alert.messageText = "Capture ↑↓ for script lines; leave ←→ to PowerPoint?"
        alert.informativeText = "While PowerPoint has focus, this mode captures only Up/Down for the highlighted script line. Left/Right reach PowerPoint unchanged and use its normal slide/animation navigation; they do not call the failing AppleScript slide command. It also works in Follow-only notes mode.\n\nAfter enabling, click an unobscured area of Presenter View on your Mac, not the audience slide. Keep PowerPoint focused while reading. Do not use this mode while editing PowerPoint, typing notes, or using its dialogs.\n\nAccessibility permission is required. Escape disables capture and still reaches PowerPoint (so it may end the show). You can instead switch the mode off in the reader or menu. This permission is never granted automatically."
        alert.addButton(withTitle: "Enable for this presentation")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else {
            notify("Enable Script Companion in System Settings → Privacy & Security → Accessibility, then click PowerPoint keys again. Reader-focused Up/Down still work without this permission, but reader-focused slide buttons also need Accessibility permission and slideshow-window setup.")
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context = context else { return Unmanaged.passUnretained(event) }
                let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                return app.filterPresentationKey(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            notify("macOS did not allow arrow capture. Check Accessibility permission and reopen this app. Use reader-focused Up/Down and change slides in PowerPoint until capture can be enabled.")
            return
        }
        arrowTap = tap
        arrowSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = arrowSource { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        arrowModeEnabled = true
        arrowMenuItem.state = .on
        emit(["type": "arrowMode", "enabled": true])
        notify("PowerPoint line keys ON. Click Presenter View on your Mac: ↑↓ = script lines; ←→ = PowerPoint slides / animations. Keep PowerPoint focused. Direct slide-button availability does not affect this mode.")
    }

    private func filterPresentationKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                self?.disableArrowMode()
                self?.notify("macOS stopped arrow capture. Click the reader for arrow controls, or explicitly enable PowerPoint keys again.")
            }
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, consumedArrowKeys.remove(key) != nil { return nil }
        guard type == .keyDown, arrowModeEnabled, following, panel.isVisible,
              !panel.isKeyWindow, !interactionBlocked, !panel.attachedSheetIsVisible,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint" else {
            return Unmanaged.passUnretained(event)
        }
        if key == 53 { // Escape is a release switch; PowerPoint still receives it.
            DispatchQueue.main.async { [weak self] in self?.disableArrowMode() }
            return Unmanaged.passUnretained(event)
        }
        guard let lineDelta = PresentationKeyPolicy.lineDelta(for: key),
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            return Unmanaged.passUnretained(event)
        }
        consumedArrowKeys.insert(key)
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
        // Nothing slow (AppleScript / file IO / Accessibility queries) runs in this callback.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.arrowModeEnabled, self.following, !self.mirrored() else { return }
            if Date().timeIntervalSince(self.lastLiveUpdate) > 5 {
                self.unlink("Live slide information is stale. Arrow capture is OFF; check PowerPoint and link again.")
                return
            }
            self.emit(["type": "line", "delta": lineDelta])
        }
        return nil // Only UP/DOWN are consumed. LEFT/RIGHT passed through above.
    }

    private func disableArrowMode() {
        if let tap = arrowTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = arrowSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        arrowTap = nil
        arrowSource = nil
        consumedArrowKeys.removeAll()
        arrowModeEnabled = false
        arrowMenuItem?.state = .off
        emit(["type": "arrowMode", "enabled": false])
    }

    @objc private func toggleHotkeys() {
        if hotkeysEnabled { disableHotkeys(); return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                numericCast(MemoryLayout<EventHotKeyID>.size), nil, &id)
            guard status == noErr else { return status }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if app.panel.isVisible && !app.mirrored() && !app.panel.attachedSheetIsVisible && !app.interactionBlocked {
                app.emit(["type": "line", "delta": id.id == 1 ? 1 : -1])
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &hotkeyHandler)
        guard handlerStatus == noErr else { notify("Global line keys could not be registered. Use the reader’s buttons."); return }
        for (id, key) in [(UInt32(1), UInt32(125)), (UInt32(2), UInt32(126))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x53435250, id: id),
                GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref = ref else { disableHotkeys(); notify("Another app may be using ⌘⌥↑ / ⌘⌥↓. Use the reader’s buttons instead."); return }
            hotkeys.append(ref)
        }
        hotkeysEnabled = true
        hotkeyMenuItem.state = .on
        emit(["type": "hotkeys", "enabled": true])
    }

    private func disableHotkeys() {
        for ref in hotkeys { UnregisterEventHotKey(ref) }
        hotkeys.removeAll()
        if let handler = hotkeyHandler { RemoveEventHandler(handler); hotkeyHandler = nil }
        hotkeysEnabled = false
        hotkeyMenuItem.state = .off
        emit(["type": "hotkeys", "enabled": false])
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.request.url?.standardizedFileURL == resources.appendingPathComponent("reader.html").standardizedFileURL
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let open = NSOpenPanel()
        open.canChooseDirectories = false
        open.canChooseFiles = true
        open.allowsMultipleSelection = parameters.allowsMultipleSelection
        open.allowedFileTypes = parameters.allowsMultipleSelection ? ["png", "jpg", "jpeg", "zip"] : ["pptx", "txt", "json"]
        completionHandler(open.runModal() == .OK ? open.urls : nil)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Script Companion"
        alert.informativeText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = "Script Companion"; alert.informativeText = message
        alert.runModal(); completionHandler()
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        followTimer?.invalidate()
        disableHotkeys()
        disableArrowMode()
        saveQueue.sync {}
    }
}

private extension NSWindow {
    var attachedSheetIsVisible: Bool { attachedSheet != nil }
}
@main
struct ScriptCompanionMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
