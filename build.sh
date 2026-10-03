#!/bin/sh
# Builds YouTubeMusicMenu.app in this folder.
set -e
cd "$(dirname "$0")"

swift build -c release

app=YouTubeMusicMenu.app
# Quit a running copy, so `open` launches the new build instead of reactivating the old one.
pkill -x YouTubeMusicMenu && while pgrep -x YouTubeMusicMenu >/dev/null; do sleep 0.1; done || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/YouTubeMusicMenu "$app/Contents/MacOS/"
cp AppIcon.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.YouTubeMusicMenu</string>
    <key>CFBundleName</key><string>YouTubeMusicMenu</string>
    <key>CFBundleExecutable</key><string>YouTubeMusicMenu</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$app"
echo "Built $app"
