#!/usr/bin/env python3
"""Package the maintained observer and Safari transport without shipping test files."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
destination = root / "build/safari-web"
destination.mkdir(parents=True, exist_ok=True)
sources = [
    root / "BrowserExtensions/Chromium/privacy.js",
    root / "BrowserExtensions/Chromium/TabObserver.js",
    root / "BrowserExtensions/Chromium/TabRestorer.js",
    root / "BrowserExtensions/Safari/RequestConnection.js",
    root / "BrowserExtensions/Safari/background.js",
]
# These four controlled ES modules have only single-line imports and named exports.
# Safari uses a classic background script; no external bundler/runtime is needed.
parts = []
for source in sources:
    lines = [line.removeprefix("export ") for line in source.read_text().splitlines()
             if not line.startswith("import ")]
    parts.append("\n".join(lines))
(destination / "background.js").write_text("\"use strict\";\n" + "\n\n".join(parts) + "\n")
manifest = {
    "manifest_version": 3,
    "name": "Thread Context",
    "version": "0.1.0",
    "description": "Share normal Safari tab metadata with the local Thread app.",
    "permissions": ["tabs", "nativeMessaging"],
    "background": {"scripts": ["background.js"]},
    "action": {"default_title": "Reconnect Thread"},
}
(destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(destination)
