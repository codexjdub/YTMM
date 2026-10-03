#!/bin/sh
# Builds YTMM.app (Apple silicon + Intel) in this folder.
# Set SIGN_IDENTITY to sign with a certificate from your keychain; otherwise it's signed ad hoc.
set -e
cd "$(dirname "$0")"

# The app's version; release.sh publishes it as v<version>.
version=1.0.1

flags="-c release --arch arm64 --arch x86_64"
swift build $flags
bin="$(swift build $flags --show-bin-path)"

app=YTMM.app
# Quit a running copy, so `open` launches the new build instead of reactivating the old one.
pkill -x YTMM && while pgrep -x YTMM >/dev/null; do sleep 0.1; done || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/YTMM" "$app/Contents/MacOS/"
cp AppIcon.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.codexjdub.YTMM</string>
    <key>CFBundleName</key><string>YTMM</string>
    <key>CFBundleExecutable</key><string>YTMM</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
echo "Built $app"
