# Publication test report — 0.5.3

Completed: **2026-10-01T12:58:26.018074+00:00**. These are fresh local results for the source hashes in [summary.json](test-results/summary.json), not inherited claims from an earlier release. Runtime source and builder were kept unchanged from the supplied 0.5.3 package; tests received a portable browser-path default.

## Environment and scope

Linux; Python 3.13.5; Playwright 1.57.0; Chromium 144.0.7559.96 built on Debian GNU/Linux 13 (trixie). Browser tests used the system Chromium override and offline contexts. Native transport, saved state and some clock behaviour are simulated. Screenshot captures show the real HTML/CSS/JavaScript renderer, not a recreated design.

**346 browser checks passed. One check was not run.** All seven browser suites completed. Each suite log and its detailed JSON report are in [test-results/](test-results/).

| Suite | Passed checks | Not run | Evidence |
| --- | ---: | ---: | --- |
| `test_notes_at_top.py` | 62 | 0 | [Log](test-results/test_notes_at_top.log) |
| `test_notes_first_timer.py` | 60 | 0 | [Log](test-results/test_notes_first_timer.log) |
| `test_reset_all_lines.py` | 55 | 0 | [Log](test-results/test_reset_all_lines.log) |
| `test_reader.py` | 60 | 1 | [Log](test-results/test_reader.log) |
| `test_keyboard_recovery.py` | 17 | 0 | [Log](test-results/test_keyboard_recovery.log) |
| `test_slide_buttons.py` | 36 | 0 | [Log](test-results/test_slide_buttons.log) |
| `test_preview_clock_memory.py` | 56 | 0 | [Log](test-results/test_preview_clock_memory.log) |

The one **NOT RUN** result concerns actual `file://` launch and real file-origin storage. This environment blocked local-file navigation by policy. The test records that restriction; no policy bypass was attempted. Import, persistence and restoration tests with simulated storage did run, but do not replace the blocked test.

## Isolated Swift and build-script checks

```text
Swift version 6.2.1 (swift-6.2.1-RELEASE)
Target: x86_64-unknown-linux-gnu
```

- [Key routing](test-results/KeyPolicyTests.log): passed; checks Up/Down capture and pass-through for other tested key codes.
- [Navigation policy](test-results/SlideNavigationPolicyTests.log): **6,257 assertions passed**.
- [Position parser](test-results/PositionParserTests.log): **2,017 assertions passed**.
- [Window placement](test-results/test_window_placement.log): **13 isolated checks passed**, using stub screen/window objects.
- [Builder shell syntax](test-results/builder-syntax.log): `bash -n` passed. Empty output is normal on success.

The three pure Swift test programs compiled and ran. This is **not an AppKit application build** and does not execute either PowerPoint AppleScript adapter. The window-placement harness extracts the production calculation into Foundation stubs; it does not test macOS desktop/window management.

## Not verified

Native Mac compilation/linking; WKWebView rendering; real PowerPoint automation; Accessibility/keyboard delivery; real latency; projector privacy; camera-notch/menu-bar handling; browser combinations other than the named Chromium environment; sleep/wake timing. No GitHub Actions run occurred while preparing this package. Do not infer a passing cloud CI status from the local results.

## Reproduce

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
python -m playwright install chromium
python Tests/run_all.py --browser-only
# With a Swift toolchain installed:
python Tests/run_all.py
```

To use an existing Chromium, set `CHROMIUM_EXECUTABLE` to its executable path. Initial dependency/browser installation needs internet; the reader tests run in offline contexts. See [Playwright's library setup](https://playwright.dev/python/docs/library) and [browser installation](https://playwright.dev/python/docs/browsers).

The runner writes fresh logs/summary into `Tests/artifacts/`, removes the known stale per-suite JSON report before each run, applies a per-suite timeout, and does not count incomplete suites as passes. Generated screenshots remain under `Tests/`. Re-run and review results before copying a new publication report into `docs/`.

## Screenshots

The [gallery](SCREENSHOTS.md) names each test and explains sample data, simulated native messages and virtual time. Selected images were copied from the completed run and visually reviewed. They contain no real presentation or personal desktop capture.
