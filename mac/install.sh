#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/mac/FelixMac/FelixMac.xcodeproj"
INSTALL_PATH="/Applications/Felix.app"
DERIVED="$(mktemp -d /tmp/felix-build.XXXXXX)"

echo "→ Building Felix Mac..."
xcodebuild \
  -project "$PROJECT" \
  -scheme FelixMac \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build 2>&1 | grep -E "BUILD|error:" || true

BUILT_APP="$DERIVED/Build/Products/Release/Felix.app"
if [[ ! -d "$BUILT_APP" ]]; then
  BUILT_APP="$DERIVED/Build/Products/Release/FelixMac.app"
fi

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build failed — app not found." >&2
  exit 1
fi

echo "→ Installing to $INSTALL_PATH"
osascript -e 'tell application "Felix" to quit' 2>/dev/null || true
pkill -x Felix 2>/dev/null || true
sleep 1
rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"

echo "→ Saving repo path + enabling login at login"
defaults write com.ishaan.FelixMac felixRepoRoot "$REPO_ROOT"
defaults write com.ishaan.FelixMac felixEnableLoginAtInstall -bool true

open "$INSTALL_PATH"

echo ""
echo "Done! Felix is in /Applications."
echo "  • It auto-starts when you log in"
echo "  • Or open it anytime from Spotlight / Applications"
echo "  • Then run the iPhone app — same WiFi, no ngrok"
