// 0.5: opt-in, process-targeted number + Return shortcut.
// This is NOT the PowerPoint AppleScript "go to slide" command.
// Select a slideshow/Presenter View window explicitly. Unknown focus fails closed.
import AppKit
import ApplicationServices
import CoreGraphics

final class SlideButtonController {
    private struct Target { let app: NSRunningApplication; let window: AXUIElement }
    private var target: Target?
    var isConfigured: Bool { target != nil }
    func reset() { target = nil }

    private func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
        return result
    }
    private func element(_ object: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let result = value(object, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    private func text(_ element: AXUIElement, _ attribute: CFString) -> String {
        value(element, attribute) as? String ?? ""
    }
    private func flag(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        (value(element, attribute) as? NSNumber)?.boolValue ?? false
    }
    private func windows(_ app: NSRunningApplication) -> [AXUIElement] {
        value(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    }
    private func modal(_ window: AXUIElement) -> Bool {
        let subrole = text(window, kAXSubroleAttribute as CFString)
        return flag(window, kAXModalAttribute as CFString) || subrole == "AXDialog" || subrole == "AXSystemDialog"
            || ((value(window, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? []).contains { text($0, kAXRoleAttribute as CFString) == "AXSheet" }
    }
    private func dimensions(_ window: AXUIElement) -> CGSize? {
        guard let raw = value(window, kAXSizeAttribute as CFString), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
    @discardableResult
    func configure(presentation: String) throws -> Bool {
        target = nil
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) else {
            throw CompanionError.message("Allow this rebuilt Script Companion in System Settings → Privacy & Security → Accessibility, reopen it, then choose Slide buttons: Set up again. Automation permission alone is not enough for keyboard slide buttons.")
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first
                ?? NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint" }) else {
            throw CompanionError.message("PowerPoint is not running.")
        }
        let candidates = windows(app).filter {
            guard text($0, kAXRoleAttribute as CFString) == "AXWindow", !modal($0),
                  !flag($0, kAXMinimizedAttribute as CFString), let size = dimensions($0) else { return false }
            return size.width >= 400 && size.height >= 250
        }
        guard !candidates.isEmpty else {
            throw CompanionError.message("PowerPoint exposed no usable windows to Accessibility. Start Presenter View, close PowerPoint dialogs, and try setup again. No keys were sent.")
        }
        let chooser = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 460, height: 28))
        for (i, window) in candidates.enumerated() {
            let name = text(window, kAXTitleAttribute as CFString)
            let size = dimensions(window) ?? .zero
            chooser.addItem(withTitle: "\(i + 1). \(name.isEmpty ? "Untitled PowerPoint window" : name) [\(Int(size.width))×\(Int(size.height))]")
        }
        let alert = NSAlert()
        alert.messageText = "Choose the slideshow window for slide buttons"
        alert.informativeText = "Linked deck: \(presentation)\n\nSelect Presenter View or the audience slideshow window, NEVER the editing window. If the names are ambiguous, cancel rather than guess.\n\nThe Next/Previous buttons will focus this window and send a slide number followed by Return. They then read PowerPoint to confirm the actual slide. This requires Accessibility permission and skips animation steps. Custom slideshow order is not supported.\n\nClose PowerPoint dialogs and do not type in its notes while using these buttons. Window selection is forgotten when you unlink. This native method still needs testing on your Mac."
        alert.accessoryView = chooser
        alert.addButton(withTitle: "Use selected slideshow window")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard candidates.indices.contains(chooser.indexOfSelectedItem) else { return false }
        target = Target(app: app, window: candidates[chooser.indexOfSelectedItem])
        return true
    }

    private func check(_ target: Target, requireFocus: Bool) throws {
        guard AXIsProcessTrusted(), !target.app.isTerminated,
              target.app.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint",
              windows(target.app).contains(where: { CFEqual($0, target.window) }), !modal(target.window),
              !flag(target.window, kAXMinimizedAttribute as CFString) else {
            throw CompanionError.message("Selected PowerPoint window is unavailable or blocked by a dialog. Choose Slide buttons: Set up again. No further keys were sent.")
        }
        guard requireFocus else { return }
        let axApp = AXUIElementCreateApplication(target.app.processIdentifier)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier,
              let focusedWindow = element(axApp, kAXFocusedWindowAttribute as CFString), CFEqual(focusedWindow, target.window),
              let focusedElement = element(axApp, kAXFocusedUIElementAttribute as CFString) else {
            throw CompanionError.message("PowerPoint did not give the selected slideshow window keyboard focus. Click a non-text area of Presenter View, then retry. No further keys were sent.")
        }
        // Never type a number into a focused notes field, editor, search box or dialog.
        var current: AXUIElement? = focusedElement
        var reachedWindow = false
        let unsafeRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXSheet", "AXDialog", "AXUnknown", "AXButton", "AXLink", "AXMenu", "AXMenuItem", "AXPopUpButton", "AXCheckBox", "AXRadioButton"]
        for _ in 0..<24 {
            guard let node = current else { break }
            let role = text(node, kAXRoleAttribute as CFString)
            var settable = DarwinBoolean(false)
            let canEdit = AXUIElementIsAttributeSettable(node, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
            guard !role.isEmpty, !unsafeRoles.contains(role), !canEdit, !modal(node) else {
                throw CompanionError.message("A text field or dialog has focus in PowerPoint. Click a non-text area of Presenter View before using slide buttons. No further keys were sent.")
            }
            if CFEqual(node, target.window) { reachedWindow = true; break }
            current = element(node, kAXParentAttribute as CFString)
        }
        guard reachedWindow else {
            throw CompanionError.message("Could not verify keyboard focus belongs to the selected slideshow window. No keys were sent. Use PowerPoint's native controls until this window can be verified.")
        }
        let modifiers = CGEventSource.flagsState(.combinedSessionState)
        guard modifiers.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            throw CompanionError.message("Release Shift, Control, Option and Command before changing slides. No further keys were sent.")
        }
    }

    func send(slide: Int, stillAllowed: @escaping () -> Bool, completion: @escaping (Error?) -> Void) {
        guard let chosen = target, let codes = SlideNavigationPolicy.keyCodes(slide: slide) else {
            completion(CompanionError.message("Choose Slide buttons: Set up before changing slides.")); return
        }
        guard CGPreflightPostEventAccess() else { completion(CompanionError.message("macOS has not allowed this rebuilt app to send keyboard events. Check Script Companion in Privacy & Security → Accessibility, then reopen the app. No keys were sent.")); return }
        guard stillAllowed() else { completion(CompanionError.message("Slide request cancelled before keyboard input.")); return }
        do { try check(chosen, requireFocus: false) } catch { completion(error); return }
        // Only raise the explicitly selected window, never click projector coordinates.
        let axApp = AXUIElementCreateApplication(chosen.app.processIdentifier)
        let focused = element(axApp, kAXFocusedWindowAttribute as CFString)
        // A window already selected in PowerPoint does not need an AXRaise action.
        if focused == nil || !CFEqual(focused!, chosen.window) {
            guard AXUIElementPerformAction(chosen.window, kAXRaiseAction as CFString) == .success else {
                completion(CompanionError.message("PowerPoint could not raise the selected slideshow window. Click Presenter View and try again. No keys were sent.")); return
            }
        }
        guard chosen.app.activate(options: []) else {
            completion(CompanionError.message("PowerPoint could not receive keyboard focus. No keys were sent.")); return
        }
        // Do not impose a fixed delay on an already-focused slideshow.
        // All original focus/text-field/dialog checks remain; no events on failed checks.
        waitForFocus(codes: codes, characters: Array(String(slide).utf16), chosen: chosen,
                     attemptsLeft: 8, stillAllowed: stillAllowed, completion: completion)
    }
    private func waitForFocus(codes: [UInt16], characters: [UInt16], chosen: Target, attemptsLeft: Int,
                              stillAllowed: @escaping () -> Bool, completion: @escaping (Error?) -> Void) {
        guard stillAllowed() else { completion(CompanionError.message("Slide request cancelled before keyboard input.")); return }
        do {
            try check(chosen, requireFocus: true)
            postPair(codes: codes, characters: characters, at: 0, chosen: chosen,
                     stillAllowed: stillAllowed, completion: completion)
        } catch {
            guard attemptsLeft > 0 else { completion(error); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.waitForFocus(codes: codes, characters: characters, chosen: chosen,
                                  attemptsLeft: attemptsLeft - 1, stillAllowed: stillAllowed, completion: completion)
            }
        }
    }
    private func postPair(codes: [UInt16], characters: [UInt16], at index: Int, chosen: Target,
                          stillAllowed: @escaping () -> Bool, completion: @escaping (Error?) -> Void) {
        guard stillAllowed() else { completion(CompanionError.message("Slide request cancelled. No further keyboard input was sent.")); return }
        do { try check(chosen, requireFocus: true) } catch { completion(error); return }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: codes[index], keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: codes[index], keyDown: false) else {
            completion(CompanionError.message("macOS could not create the slide shortcut.")); return
        }
        down.flags = []; up.flags = []
        if index < characters.count {
            var character = characters[index]
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
        }
        // These events are addressed to PowerPoint only, not to the global event stream.
        down.postToPid(chosen.app.processIdentifier)
        up.postToPid(chosen.app.processIdentifier)
        if index + 1 == codes.count { completion(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            self?.postPair(codes: codes, characters: characters, at: index + 1, chosen: chosen,
                           stillAllowed: stillAllowed, completion: completion)
        }
    }
}
