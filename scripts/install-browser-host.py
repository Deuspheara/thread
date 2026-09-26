#!/usr/bin/env python3
"""Register the built native host for an explicitly selected Chromium browser."""
import argparse, base64, hashlib, json, os
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--browser', choices=['chrome','chromium','brave','edge'], required=True)
parser.add_argument('--output', type=Path, help='Generate a manifest here without registering with a browser')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
manifest = json.loads((root/'BrowserExtensions/Chromium/manifest.json').read_text())
key = base64.b64decode(manifest['key'])
extension_id = ''.join(chr(97+int(c,16)) for c in hashlib.sha256(key).hexdigest()[:32])
executable = args.app.resolve()/'Contents/MacOS/ThreadBrowserHost'
if not executable.is_file() or not os.access(executable, os.X_OK): parser.error('Build Thread.app before registering its host')
# Brave's macOS native-host lookup deliberately shares Chrome's user directory.
vendors = {'chrome':'Google/Chrome','chromium':'Chromium','brave':'Google/Chrome','edge':'Microsoft Edge'}
output = args.output or Path.home()/'Library/Application Support'/vendors[args.browser]/'NativeMessagingHosts/app.thread.browser.json'
payload = {'name':'app.thread.browser','description':'Thread local tab metadata bridge','path':str(executable),
           'type':'stdio','allowed_origins':[f'chrome-extension://{extension_id}/']}
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(payload,indent=2)+'\n')
print(output)
