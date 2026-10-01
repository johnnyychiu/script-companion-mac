#!/bin/bash
# Builds local source on this Mac. No sudo, macros, or security bypasses.
# Apple tools installation, when explicitly accepted, needs a one-time download.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
LOG="$ROOT/build.log"
exec > >(tee "$LOG") 2>&1
TMP=""
finish() {
  local status=$?
  trap - EXIT
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then /bin/rm -rf "$TMP"; fi
  if [ "$status" -ne 0 ]; then
    printf '\nBuild did not finish. Details are in build.log in this folder.\n'
    printf 'The standalone reader.html still works without the Mac app.\n'
    read -r -p 'Press Return to close. ' _ || true
  fi
  exit "$status"
}
trap finish EXIT
if [ "$(uname -s)" != 'Darwin' ]; then
  echo 'Build this app on a Mac. The HTML reader also works on other computers.'
  exit 1
fi
MAJOR=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)
if [ "$MAJOR" -lt 13 ]; then echo 'This prototype targets macOS 13 or newer. Use reader.html on older systems.'; exit 1; fi
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  printf '\nApple’s Command Line Tools are needed for this one-time local build.\n'
  printf 'macOS will offer an installation dialog. That initial download needs internet.\n'
  printf 'After installation, double-click Build Mac App.command again.\n'
  /usr/bin/xcode-select --install || true
  read -r -p 'Press Return to close this window. ' _ || true
  exit 0
fi
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Swift compiler not found. Install/update Apple Command Line Tools, then run this file again.'
  exit 1
fi
DEST="$ROOT/Script Companion.app"
if [ -e "$DEST" ]; then
  echo 'Script Companion.app already exists. Quit it, then move or rename it before rebuilding.'
  echo 'This builder does not overwrite existing apps.'
  exit 1
fi
TMP=$(/usr/bin/mktemp -d "$ROOT/.script-companion-build.XXXXXX")
APP="$TMP/Script Companion.app"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp "$ROOT/Source/Info.plist" "$APP/Contents/Info.plist"
/bin/cp "$ROOT/Source/reader.html" "$ROOT/Source/PowerPoint.applescript" "$ROOT/Source/PowerPointPosition.applescript" "$APP/Contents/Resources/"
# Precompile to avoid parsing AppleScript source on every position poll.
# Failure here keeps the readable source fallback; no commands are executed by this step.
for ADAPTER in PowerPoint PowerPointPosition; do
  if ! /usr/bin/osacompile -o "$APP/Contents/Resources/$ADAPTER.scpt" "$ROOT/Source/$ADAPTER.applescript"; then
    /bin/rm -f "$APP/Contents/Resources/$ADAPTER.scpt"
    printf 'Using source fallback for %s; compilation was unavailable.\n' "$ADAPTER"
  fi
done
/bin/cp -R "$ROOT/Licenses" "$APP/Contents/Resources/Licenses"
ARCH=$(/usr/bin/uname -m)
SDK=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
printf '\nBuilding Script Companion for %s on this Mac…\n' "$ARCH"
/usr/bin/xcrun swiftc -swift-version 5 -O \
  -sdk "$SDK" -target "${ARCH}-apple-macosx13.0" \
  -module-cache-path "$TMP/module-cache" \
  -framework AppKit -framework WebKit -framework Carbon -framework ApplicationServices -framework CoreGraphics \
  "$ROOT/Source/PresentationKeyPolicy.swift" \
  "$ROOT/Source/SlideNavigationPolicy.swift" \
  "$ROOT/Source/PowerPointPositionParser.swift" \
  "$ROOT/Source/SlideButtonController.swift" \
  "$ROOT/Source/ScriptCompanion.swift" \
  -o "$APP/Contents/MacOS/ScriptCompanion"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
# Ad-hoc local signing. This is NOT a Developer ID signature or notarization.
/usr/bin/codesign --force --sign - --options runtime \
  --entitlements "$ROOT/Source/Entitlements.plist" "$APP"
/usr/bin/codesign --verify --strict "$APP"
/bin/mv "$APP" "$DEST"
printf '\nCreated: %s\n' "$DEST"
printf '\nBefore rehearsal: use extended displays, not mirroring.\n'
printf 'PowerPoint live link and full-screen window behaviour still need testing on your Mac.\n'
printf 'Open the app from this folder. The ▤ Script menu has Show / Hide / Quit.\n'
/usr/bin/open -R "$DEST"
read -r -p 'Press Return to finish. ' _ || true
