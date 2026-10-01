# Troubleshooting and rehearsal checklist

## The browser buttons do not move PowerPoint

That is expected. `Source/reader.html` has no native bridge. It controls the local script only. Build the Mac companion, start Presenter View, link the correct deck and configure slide buttons for native control.

## “Parameter error (-50)”, unavailable controls, or no slide confirmation

This was reported during prototype development. The current code avoids the original AppleScript slide-jump command and uses an explicitly selected slideshow window plus a number/Return shortcut. It is **not a verified universal fix**. A successful notes link does not establish that slide controls work.

Keep the audience's presentation under control using PowerPoint itself. With a working notes link the reader can still follow; otherwise it holds a snapshot. Optional PowerPoint-focused Up/Down capture can move script lines while PowerPoint handles its own Left/Right keys, including animations. It requires permission and deliberate activation; disable it before editing or opening dialogs.

Do not repeatedly resend navigation commands to force a response. Review the reader's message and actual audience slide. For a report, use **▤ Script → Save slide-control diagnostic…** when available. Review and redact the output, especially paths and presentation/window identities. Do not attach a real script or a confidential deck.

## Permission prompts or rebuilt app not recognised

Automation is used for reading PowerPoint; Accessibility is separate and used for keyboard controls. Review the app in System Settings → Privacy & Security, grant only the permissions needed for the chosen feature, then reopen and repeat setup when necessary. Rebuilding or moving a locally signed app can require rechecking its permissions. Do not disable system protection or bypass managed-device policy.

## Slide changes are slow

The first link and **Refresh notes** read the deck. The position-only polling interval is nominally 0.35 seconds, not a promised total latency. macOS scripting, focus changes and PowerPoint responses add time. Cached notes may appear before a later notes refresh. Diagnostics include operation timing; provide an observed measurement rather than an assumed speed improvement.

## Wrong or outdated image

Images are static exports. Load notes first and verify the complete file-to-slide mapping. Re-export after visual edits. Hidden slides/full-deck order matter. This version does not render `.pptx` artwork directly or capture the projector window. A live note link and a current snapshot are separate things.

## Reset, timers and unexpected line positions

**Line 1** resets one slide. **Reset all slides to line 1** resets all positions after confirmation and leaves the current slide/timers unchanged. Editing/importing a new script can reset positions; importing a JSON backup restores its positions. Retiming a rehearsal uses the timer's separate Reset. Restored timers open paused. Pause before sleep or closing; forced termination may lose the most recent checkpoint interval.

## Window cannot reach the physical top edge

The current line starts near the top of the HTML content. The normal macOS title bar remains. **Move reader to top** respects `NSScreen.visibleFrame`, not the physical pixel edge: menu-bar/notch/system-reserved areas may remain. The app does not draw over the camera housing.

## Build fails

Use a fresh folder with no existing `Script Companion.app`. Check macOS 13+, installed Apple Command Line Tools, writable files and the actual `build.log`. Shell syntax checks and browser tests do not establish that the native code compiles on your machine. Share a redacted build error and versions, not a private presentation.

## Minimum rehearsal before a real presentation

- Use a non-sensitive three-slide deck. Test normal reading, accidental next/back, remembered lines, reset-all, timer pause/reset and snapshots.
- Confirm extended displays, the selected presenter display, and what the projector shows while switching focus. Do not assume the reader is private.
- Test line keys and slide keys separately, with and without animations. Verify the actual slide after a command and the visible connection status after a failure.
- Keep manual PowerPoint navigation and a notes backup available. Test your clicker, your exact PowerPoint/macOS versions, sleep/wake and dialogs before relying on them.

## Platform references

These explain platform behaviour, not a compatibility certification for this app.

- [Apple Command Line Tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)
- [Apple usable screen frame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- [PowerPoint presentation shortcuts](https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-deliver-powerpoint-presentations)
