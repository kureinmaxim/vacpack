#!/bin/bash
# Install a DMG built by scripts/package.sh into /Applications, so the Dock shows the new icon.
#   scripts/install.sh          install .build/dist/Vacpack-<version>.dmg
#   scripts/install.sh <dmg>    install that DMG
#
# Quits a running Vacpack, moves the installed copy to the Trash (nothing is deleted), copies the
# new one, re-registers it with Launch Services, makes it forget older copies in the Trash and
# restarts the Dock: without that the Dock can keep showing a cached, blank icon.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  -h | --help)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

fail() {
  echo "install failed: $1" >&2
  exit 1
}

version=$(sed -nE 's/^ *MARKETING_VERSION: *"([^"]+)".*/\1/p' project.yml)
dmg=${1:-.build/dist/Vacpack-$version.dmg}
[ -f "$dmg" ] || fail "no DMG at $dmg; run scripts/package.sh first"
app=/Applications/Vacpack.app
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
plist() { /usr/libexec/PlistBuddy -c "Print $1" "$2/Contents/Info.plist"; }
running() { /bin/ps -ax -o command= | grep -q "^$app/Contents/MacOS/Vacpack"; }

if running; then
  osascript -e 'tell application id "xyz.kurein.vacpack" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do running || break; sleep 0.25; done
  running && fail "Vacpack is still running; quit it and try again"
fi

mount=$(mktemp -d)
trap 'hdiutil detach -quiet "$mount" 2>/dev/null || true; rmdir "$mount" 2>/dev/null || true' EXIT
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
[ -d "$mount/Vacpack.app" ] || fail "$dmg has no Vacpack.app"

if [ -d "$app" ]; then
  trashed="$HOME/.Trash/Vacpack $(plist CFBundleShortVersionString "$app") (build $(plist CFBundleVersion "$app")).app"
  [ -e "$trashed" ] && trashed="${trashed%.app} $(date +%H%M%S).app"
  mv "$app" "$trashed"
fi
ditto "$mount/Vacpack.app" "$app"
codesign --verify --deep --strict "$app" || fail "the installed app's signature does not verify"

touch "$app"
"$lsregister" -f "$app"
for stale in "$HOME"/.Trash/Vacpack*.app; do
  [ -d "$stale" ] && "$lsregister" -u "$stale"
done
killall Dock
open "$app"
echo "Installed Vacpack $(plist CFBundleShortVersionString "$app") (build $(plist CFBundleVersion "$app")) and restarted the Dock."
echo "Older copies are in the Trash; empty it when you no longer need them."
