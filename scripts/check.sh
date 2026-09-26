#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Routine POC checks share the root build cache. Package suites are opt-in.
mode="${1:---quick}"
case "$mode" in
    --quick|--full)
        [[ $# -le 1 ]] || { echo 'Unexpected arguments' >&2; exit 2; }
        ;;
    --package)
        [[ $# -eq 2 && "$2" == Thread* && "$2" != */* && -f "Packages/$2/Package.swift" ]] || {
            echo 'Usage: scripts/check.sh --package ThreadEngine (or another local package)' >&2
            exit 2
        }
        ;;
    *)
        echo 'Usage: scripts/check.sh [--quick|--full|--package PACKAGE]' >&2
        exit 2
        ;;
esac

python3 scripts/check-boundaries.py
# This compiles the app and its dependencies and runs the root pipeline/replay tests.
# SwiftPM does not run dependency packages' own test targets here.
swift test -Xswiftc -warnings-as-errors

check_package() {
    local package="$1"
    if [[ -d "$package/Tests" ]]; then
        # swift test already builds the package; a preceding swift build is redundant.
        swift test --package-path "$package" -Xswiftc -warnings-as-errors
    else
        swift build --package-path "$package" -Xswiftc -warnings-as-errors
    fi
}

if [[ "$mode" == --package ]]; then
    check_package "Packages/$2"
fi
if [[ "$mode" != --full ]]; then
    exit 0
fi

for package in Packages/*; do
    check_package "$package"
done
python3 scripts/check-shell-hook.py
node --test BrowserExtensions/Chromium/tests/*.test.js
node --test BrowserExtensions/Safari/tests/*.test.js
python3 scripts/stage-safari-web.py
node --check build/safari-web/background.js
python3 scripts/check-browser-host.py
python3 scripts/check-browser-restore.py

(cd Backend && npm run typecheck && npm run lint && npm test && npm run build)
python3 scripts/tests/test_decision_routing.py
python3 scripts/tests/test_membership_applications.py
python3 scripts/tests/test_transition_applications.py
python3 scripts/tests/test_resource_reassignments.py
