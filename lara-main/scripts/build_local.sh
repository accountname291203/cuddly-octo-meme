#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf build/
mkdir -p build

echo "[*] Building lara IPA (no xcpretty, no ldid)..."
echo

xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  archive \
  -archivePath "$PWD/build/lara.xcarchive" 2>&1 | tee build/xcodebuild.log

APP_PATH="$PWD/build/lara.xcarchive/Products/Applications/lara.app"
if [ ! -d "$APP_PATH" ]; then
  echo "[!] Build failed — no .app found at $APP_PATH"
  echo "[!] Check build/xcodebuild.log for errors"
  exit 1
fi

echo "[*] Packaging IPA..."
rm -rf "$PWD/build/Payload"
mkdir -p "$PWD/build/Payload"
cp -R "$APP_PATH" "$PWD/build/Payload/"

# Fake-sign with entitlements using codesign (no ldid needed)
# Skip signing entirely — SideStore/LiveContainer will re-sign anyway
codesign --remove-signature "$PWD/build/Payload/lara.app/lara" 2>/dev/null || true

# Embed entitlements into Info.plist as a reference (optional)
plutil -replace UIFileSharingEnabled -bool YES "$PWD/build/Payload/lara.app/Info.plist" 2>/dev/null || true

(cd "$PWD/build" && /usr/bin/zip -qry lara.ipa Payload)

rm -rf "$PWD/build/Payload" "$PWD/build/lara.xcarchive"

echo
echo "[✓] Build successful!"
echo "[✓] IPA at: $(pwd)/build/lara.ipa"
