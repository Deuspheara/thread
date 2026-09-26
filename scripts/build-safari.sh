#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
case "$configuration" in
    debug) xcode_configuration=Debug ;;
    release) xcode_configuration=Release ;;
    *) echo 'Usage: scripts/build-safari.sh [debug|release]' >&2; exit 2 ;;
esac
python3 scripts/stage-safari-web.py
xcodebuild -quiet -project BrowserExtensions/Safari/ThreadSafari.xcodeproj \
    -scheme ThreadSafari -configuration "$xcode_configuration" \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/safari-derived \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES "THREAD_APP_GROUP=${THREAD_APP_GROUP:-}" build
