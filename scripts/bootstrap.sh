#!/bin/bash
# Prepare a fresh checkout: check prerequisites, generate the Xcode project and test fixtures.
# Installs nothing by itself; it prints the command to run when something is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

missing=()
command -v xcodebuild >/dev/null || missing+=("Xcode (App Store)")
command -v xcodegen >/dev/null || missing+=("xcodegen")

# Tools are looked up by absolute path, like the app does (shell aliases such as gs=git status do not count).
brew_formula() {
  case "$1" in
    ffmpeg | ffprobe) echo ffmpeg ;;
    cwebp) echo webp ;;
    avifenc) echo libavif ;;
    gs) echo ghostscript ;;
    *) echo "$1" ;;
  esac
}
formulas=()
for tool in ffmpeg ffprobe pngquant gifski cwebp avifenc gs; do
  found=""
  for dir in /opt/homebrew/bin /usr/local/bin /opt/local/bin; do
    [ -x "$dir/$tool" ] && found="$dir/$tool" && break
  done
  if [ -z "$found" ]; then
    formula=$(brew_formula "$tool")
    [[ " ${formulas[*]-} " == *" $formula "* ]] || formulas+=("$formula")
  fi
done

if [ ${#missing[@]} -gt 0 ] || [ ${#formulas[@]} -gt 0 ]; then
  echo "Missing prerequisites:"
  for item in "${missing[@]-}"; do [ -n "$item" ] && echo "  - $item"; done
  [ ${#formulas[@]} -gt 0 ] && echo "  - tools: brew install ${formulas[*]}"
  [[ " ${missing[*]-} " == *" xcodegen "* ]] && echo "  - brew install xcodegen"
  exit 1
fi

if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  echo "Xcode needs its first-launch system components. Run once (asks for an admin password):"
  echo "  sudo xcodebuild -runFirstLaunch"
  exit 1
fi

xcodegen generate --quiet
scripts/make-fixtures.sh
echo "Ready. Run scripts/check.sh to build and test."
