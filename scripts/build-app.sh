#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    echo 'Usage: scripts/build-app.sh [debug|release]' >&2
    exit 2
fi
swift build -c "$configuration" -Xswiftc -warnings-as-errors
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
app_directory="$PWD/build/Thread.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/Thread" "$app_directory/Contents/MacOS/Thread"
python3 scripts/prepare-runtime-paths.py "$app_directory/Contents/MacOS/Thread"
cp "$binary_directory/ThreadShellSend" "$app_directory/Contents/MacOS/ThreadShellSend"
cp "$binary_directory/ThreadBrowserHost" "$app_directory/Contents/MacOS/ThreadBrowserHost"
agent_directory="$app_directory/Contents/XPCServices/ThreadAgent.xpc/Contents"
mkdir -p "$agent_directory/MacOS"
cp "$binary_directory/ThreadAgent" "$agent_directory/MacOS/ThreadAgent"
python3 scripts/prepare-runtime-paths.py "$agent_directory/MacOS/ThreadAgent"
cp ThreadAgent/Resources/Info.plist "$agent_directory/Info.plist"
cp ShellIntegration/zsh/thread.zsh "$app_directory/Contents/Resources/thread.zsh"
cp ThreadApp/Resources/Setup.md "$app_directory/Contents/Resources/Setup.md"
cp ThreadApp/Resources/Info.plist "$app_directory/Contents/Info.plist"
python3 scripts/configure-updates.py "$app_directory/Contents/Info.plist"
sparkle_framework="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$app_directory/Contents/Frameworks"
rm -rf "$app_directory/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_framework" "$app_directory/Contents/Frameworks/Sparkle.framework"
# SwiftPM locates dependency resource bundles beside the executable (including GRDB's privacy manifest).
for resource_bundle in "$binary_directory"/*.bundle; do
    [[ -d "$resource_bundle" ]] || continue
    bundle_name="$(basename "$resource_bundle")"
    if [[ "$bundle_name" == *Tests.bundle ]]; then
        rm -rf "$app_directory/Contents/MacOS/$bundle_name"
        continue
    fi
    destination="$app_directory/Contents/MacOS/$bundle_name"
    ditto "$resource_bundle" "$destination"
    ditto "$resource_bundle" "$agent_directory/MacOS/$bundle_name"
done
scripts/build-safari.sh "$configuration"
xcode_configuration=Debug
[[ "$configuration" == release ]] && xcode_configuration=Release
mkdir -p "$app_directory/Contents/PlugIns"
ditto "build/safari-derived/Build/Products/$xcode_configuration/ThreadSafari.appex" "$app_directory/Contents/PlugIns/ThreadSafari.appex"
python3 scripts/prepare-app-entitlements.py
bash scripts/sign-app.sh "$app_directory"
echo "$app_directory"
