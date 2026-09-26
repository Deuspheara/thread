#!/usr/bin/env python3
"""Package the thin decision backend from an explicit, secret-free file allowlist."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parent.parent
backend = root / 'Backend'
files = [backend / name for name in ('.env.example', 'Dockerfile', '.dockerignore', 'compose.yaml', 'compose.host-tunnel.yaml', 'package.json', 'package-lock.json', 'tsconfig.json', 'tsconfig.build.json')]
files.extend(sorted((backend / 'src').rglob('*.ts')))
if not (backend / 'src/main.ts').is_file():
    raise SystemExit('Backend source files are missing.')
for path in files:
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(backend.resolve()):
        raise SystemExit('Backend package input must be a regular allowlisted file.')

template = (backend / '.env.example').read_text()
expected = {'OPENROUTER_API_KEY': '', 'OPENROUTER_MODEL': 'typesafe/jev-1.13',
            'THREAD_CLIENT_TOKENS': "'{}'", 'THREAD_API_PORT': '8787',
            'THREAD_REDIS_URL': 'redis://127.0.0.1:6379/0'}
seen = set()
for line in template.splitlines():
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    key, separator, value = line.partition('=')
    key, value = key.strip(), value.strip()
    if not separator or key not in expected or key in seen or value != expected[key]:
        raise SystemExit('The public template must contain only blank credentials and default settings.')
    seen.add(key)
if seen != set(expected):
    raise SystemExit('The public template is missing required default settings.')

output = root / 'build' / 'thread-api.zip'
output.parent.mkdir(parents=True, exist_ok=True)
manifest = {}
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        data = path.read_bytes()
        name = path.relative_to(backend).as_posix()
        manifest[name] = hashlib.sha256(data).hexdigest()
        item = zipfile.ZipInfo(name)
        item.create_system = 3
        item.external_attr = 0o100644 << 16
        item.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(item, data)
    archive.writestr('SHA256.json', json.dumps(manifest, indent=2) + '\n')
print(output)
