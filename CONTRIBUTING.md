# Contributing

This is an early source prototype. Small, reviewed changes are preferable to broad automation changes before the Mac integration has been exercised on real hardware.

## Before a change

Read the README, reproduce the behaviour with the sample deck, and keep unrelated modifications separate. Never use a confidential presentation in a public issue, screenshot, test fixture or CI run. See SECURITY.md for sensitive reports.

## Local checks

Install `requirements-dev.txt` and Chromium in a virtual environment as described in the README. Run `python Tests/run_all.py --browser-only`, or `python Tests/run_all.py` with Swift installed. Logs and generated screenshots belong in ignored `Tests/artifacts/` and `Tests/` outputs, not in a pull request by default.

Use `bash -n "Build Mac App.command"` to check the builder's shell syntax. This does not build the app. Build and rehearse on macOS separately for any native change. Do not call Swift parser-only validation a successful AppKit build.

## What a pull request should explain

Describe the problem and the smallest reproduction. State which tests actually ran, the OS/browser versions, and whether PowerPoint/projector testing occurred. For visible changes, attach a fresh capture of the actual UI with sample data and label any simulated connection or virtual clock. Do not fabricate screenshots or reuse an old passing report as evidence of a new run.

Preserve these behaviours: no automatic resend of a failed slide keystroke; no optimistic reader slide before confirmation; no line key changing a slide; explicit keyboard/slide-control opt-in; safe handling of dialogs and text inputs; visible snapshot/unlinked state; note and image content treated as data. Do not add cloud uploads, microphone access, global key capture or new permissions silently.

Maintain bundled license notices. Document compatibility limits and changes in CHANGELOG.md. Contributions are submitted under the project MIT license, except where an existing third-party license applies.
