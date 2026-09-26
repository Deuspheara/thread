#!/usr/bin/env python3
"""Check package dependencies and source imports against the architecture contract."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
ALLOWED = {
    'ThreadDomain': {'Foundation'},
    'ThreadEngine': {'Foundation', 'ThreadDomain'},
    'ThreadPersistence': {'Foundation', 'ThreadDomain', 'GRDB'},
    'ThreadMacOS': {'LocalAuthentication', 'Security', 'Darwin', 'ServiceManagement', 'Carbon', 'Foundation', 'ThreadDomain', 'AppKit', 'ApplicationServices', 'CoreGraphics', 'OSLog'},
    'ThreadBrowser': {'Foundation', 'ThreadDomain', 'OSLog', 'Darwin', 'SafariServices'},
    'ThreadShell': {'Foundation', 'ThreadDomain', 'Darwin', 'OSLog'},
    'ThreadGit': {'Foundation', 'ThreadDomain', 'OSLog', 'Darwin'},
    'ThreadDecisions': {'Foundation', 'ThreadDomain', 'OSLog'},
    'ThreadRestore': {'Foundation', 'ThreadDomain', 'AppKit', 'ApplicationServices', 'CoreGraphics', 'OSLog'},
    'ThreadUI': {'Foundation', 'ThreadDomain', 'SwiftUI', 'AppKit', 'Observation'},
}
DEPENDENCIES = {name: ({'ThreadDomain'} if name != 'ThreadDomain' else set()) for name in ALLOWED}
DEPENDENCIES['ThreadPersistence'].add('GRDB.swift')
errors = []
for name, allowed_imports in ALLOWED.items():
    package = ROOT / 'Packages' / name
    result = subprocess.run(['swift', 'package', '--package-path', str(package), 'dump-package'],
                            check=True, capture_output=True, text=True)
    manifest = json.loads(result.stdout)
    dependencies = set()
    for dependency in manifest['dependencies']:
        if 'fileSystem' in dependency:
            dependencies.add(Path(dependency['fileSystem'][0]['path']).name)
        elif 'sourceControl' in dependency:
            identity = dependency['sourceControl'][0]['identity']
            dependencies.add('GRDB.swift' if identity == 'grdb.swift' else identity)
        else:
            errors.append(f'{name}: unsupported dependency kind')
    if dependencies != DEPENDENCIES[name]:
        errors.append(f'{name}: expected {DEPENDENCIES[name]}, found {dependencies}')
    for source in (package / 'Sources').rglob('*.swift'):
        text = source.read_text()
        imports = set(re.findall(r'^\s*(?:@(?:preconcurrency|testable|_exported|_implementationOnly)\s+)*(?:(?:public|internal|private|package)\s+)?import\s+(\w+)', text, re.M))
        forbidden = imports - allowed_imports
        if forbidden:
            errors.append(f'{source.relative_to(ROOT)}: forbidden imports {forbidden}')
        if name == 'ThreadPersistence':
            for line in text.splitlines():
                if re.search(r'\bpublic\b', line) and re.search(r'\b(GRDB|DatabaseQueue|DatabasePool|DatabaseReader|DatabaseWriter|Row)\b', line):
                    errors.append(f'{source.relative_to(ROOT)}: GRDB type in public declaration')
# Shared transport exposes Domain contracts; helper composition owns infrastructure and remains UI-free.
for directory, allowed in [
    ('Sources/ThreadActivity', {'Foundation', 'OSLog', 'ThreadDomain', 'ThreadEngine', 'ThreadPersistence', 'ThreadMacOS', 'ThreadShell', 'ThreadGit', 'ThreadBrowser', 'ThreadDecisions', 'ThreadRestore'}),
    ('Sources/ThreadAgentTransport', {'Foundation', 'Security', 'OSLog', 'ThreadDomain'}),
    ('ThreadAgent', {'Foundation', 'Darwin', 'OSLog', 'ThreadAgentTransport', 'ThreadActivity', 'ThreadDomain'}),
]:
    for source in (ROOT / directory).rglob('*.swift'):
        imports = set(re.findall(r'^\s*import\s+(\w+)', source.read_text(), re.M))
        if imports - allowed:
            errors.append(f'{source.relative_to(ROOT)}: forbidden imports {imports - allowed}')
for source in list((ROOT / 'Packages').glob('*/Sources/**/*.swift')) + list((ROOT / 'ThreadApp').rglob('*.swift')) + list((ROOT / 'ThreadAgent').rglob('*.swift')) + list((ROOT / 'Sources').rglob('*.swift')):
    count = len(source.read_text().splitlines())
    if count > 400 and 'Migrations' not in source.parts:
        errors.append(f'{source.relative_to(ROOT)}: {count} lines; decompose before adding behavior')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print('Package dependencies, imports, and source size checks passed.')
