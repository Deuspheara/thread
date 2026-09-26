#!/bin/bash
# Sign the assembled bundle from nested code outward; keep development ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
app_directory="${1:?Usage: scripts/sign-app.sh app-directory}"
signing_identity="${THREAD_SIGNING_IDENTITY:--}"
signing_options=(--force --sign "$signing_identity")
if [[ "$signing_identity" != - ]]; then
    signing_options+=(--options runtime --timestamp)
    sparkle_framework="$app_directory/Contents/Frameworks/Sparkle.framework"
    sparkle_version="$sparkle_framework/Versions/B"
    codesign "${signing_options[@]}" "$sparkle_version/XPCServices/Installer.xpc"
    codesign "${signing_options[@]}" --preserve-metadata=entitlements "$sparkle_version/XPCServices/Downloader.xpc"
    codesign "${signing_options[@]}" "$sparkle_version/Autoupdate"
    codesign "${signing_options[@]}" "$sparkle_version/Updater.app"
    codesign "${signing_options[@]}" "$sparkle_framework"
fi
codesign "${signing_options[@]}" "$app_directory/Contents/MacOS/ThreadShellSend"
codesign "${signing_options[@]}" "$app_directory/Contents/MacOS/ThreadBrowserHost"
codesign "${signing_options[@]}" --entitlements build/app.entitlements "$app_directory/Contents/XPCServices/ThreadAgent.xpc"
codesign "${signing_options[@]}" --entitlements build/safari.entitlements "$app_directory/Contents/PlugIns/ThreadSafari.appex"
codesign "${signing_options[@]}" --entitlements build/app.entitlements "$app_directory"
codesign --verify --deep --strict "$app_directory"
