#!/bin/bash
set -e

APP_NAME="Tokengotchi"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Create bundle directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Generate Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.tokengotchi.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# Find all Swift source files
SWIFT_FILES=$(find Sources -name "*.swift")

if [ -z "$SWIFT_FILES" ]; then
    echo "❌ No Swift files found in Sources directory."
    exit 1
fi

echo "🔨 Compiling $APP_NAME..."
swiftc -o "$MACOS_DIR/$APP_NAME" \
    $SWIFT_FILES \
    -framework SwiftUI \
    -framework AppKit \
    -framework SpriteKit \
    -framework Combine

echo "✅ Build complete → $APP_DIR"
echo "🚀 Launching..."
open "$APP_DIR"
