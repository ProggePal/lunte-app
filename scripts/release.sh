#!/usr/bin/env bash
# Ships a signed, notarized Lunte to GitHub Releases, where Sparkle finds it.
#   scripts/release.sh 0.1.1
# One-time setup on the release Mac (both keep their secrets in the keychain, never in the repo):
#   xcrun notarytool store-credentials lunte
#   LunteApp/.build/artifacts/sparkle/Sparkle/bin/generate_keys
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/release.sh <version, e.g. 0.1.1>}
profile=${NOTARY_PROFILE:-lunte}
bin=LunteApp/.build/artifacts/sparkle/Sparkle/bin
plist=Resources/Info.plist
repo=ProggePal/lunte-app

[[ -z $(git status --porcelain) ]] || { echo "Commit first: a release is built from what's committed." >&2; exit 1; }
# The GitHub release notes are this version's section of CHANGELOG.md.
notes=$(awk -v v="## $version" '$0 == v {found=1; next} /^## / && found {exit} found' CHANGELOG.md)
[[ -n ${notes//[[:space:]]/} ]] || { echo "Add a \"## $version\" section to CHANGELOG.md first." >&2; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c "Print :LunteRelayURL" "$plist") != http://localhost* ]] \
  || { echo "Point LunteRelayURL in $plist at the deployed relay first." >&2; exit 1; }
key=$("$bin/generate_keys" -p 2>/dev/null) || { echo "No Sparkle key yet. Run once: $bin/generate_keys" >&2; exit 1; }
xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 \
  || { echo "No notarization login yet. Run once: xcrun notarytool store-credentials $profile" >&2; exit 1; }

# Sparkle compares CFBundleVersion, so it must only ever go up.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" \
  -c "Set :SUPublicEDKey $key" "$plist"
scripts/build-app.sh --release

zip=dist/Lunte-$version.zip
# No xattrs in the zip: macOS tags Sparkle's symlinks with com.apple.provenance, ditto stores that as ._ files, and
# Archive Utility (double-click) leaves those inside the framework, so Gatekeeper says "could not verify" (0.1.0–0.2.1).
pack() { rm -f "$zip" && ditto -c -k --norsrc --noextattr --keepParent dist/Lunte.app "$zip"; }
rm -rf dist/appcast && mkdir -p dist/appcast
pack
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple dist/Lunte.app
pack # re-zip with the notarization ticket inside
if zipinfo -1 "$zip" | grep '/\._' >/dev/null; then echo "$zip has ._ files; a double-click unzip would break the signature." >&2; exit 1; fi

cp "$zip" dist/appcast/
"$bin/generate_appcast" --download-url-prefix "https://github.com/$repo/releases/download/v$version/" dist/appcast

git commit -qam "Release $version"
git tag "v$version"
git push -q origin HEAD "v$version"
gh release create "v$version" "$zip" dist/appcast/appcast.xml --repo "$repo" --title "Lunte $version" \
  --notes "$notes"
echo "Released Lunte $version: https://github.com/$repo/releases/tag/v$version"
