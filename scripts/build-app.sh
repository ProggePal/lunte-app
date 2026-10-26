#!/usr/bin/env bash
# Builds both packages and assembles dist/Lunte.app (docs/contract.md §7).
#   scripts/build-app.sh            debug build, signed ad-hoc
#   scripts/build-app.sh --release  release build, Developer ID + hardened runtime (notarizing is a separate step)
set -euo pipefail
cd "$(dirname "$0")/.."

config=debug
sign=(--force --sign -)
if [[ "${1:-}" == "--release" ]]; then
  config=release
  sign=(--force --timestamp --options runtime --sign "Developer ID Application: Panter AS (BF4LY62Q92)")
fi

# ponytail: builds for this Mac's architecture only; add --arch arm64 --arch x86_64 when an Intel Mac plays
swift build --package-path LunteCore -c "$config" --product lunte-hook
swift build --package-path LunteApp -c "$config"
core_bin=$(swift build --package-path LunteCore -c "$config" --show-bin-path)
app_bin=$(swift build --package-path LunteApp -c "$config" --show-bin-path)

app=dist/Lunte.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$app_bin/Lunte" "$core_bin/lunte-hook" "$app/Contents/MacOS/"
ditto --norsrc --noextattr "$app_bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/boom.wav Resources/Lunte.icns "$app/Contents/Resources/"
cp LunteApp/Sources/LayaKit/LICENSE "$app/Contents/Resources/LayaKit-LICENSE.txt" # Apache-2.0 travels with the binary
cp LunteApp/.build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt" # so does Sparkle's MIT
ditto --norsrc --noextattr plugin "$app/Contents/Resources/plugin"
xattr -cr "$app" 2>/dev/null || true

# Inside out. Sparkle's nested pieces as its docs say: sparkle-project.org/documentation/sandboxing/#code-signing
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${sign[@]}" "$sparkle/XPCServices/Installer.xpc"
codesign "${sign[@]}" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
codesign "${sign[@]}" "$sparkle/Autoupdate"
codesign "${sign[@]}" "$sparkle/Updater.app"
codesign "${sign[@]}" "$app/Contents/Frameworks/Sparkle.framework"
codesign "${sign[@]}" "$app/Contents/MacOS/lunte-hook"
codesign "${sign[@]}" "$app"

echo "Built $app ($config)"
