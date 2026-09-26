#!/usr/bin/env python3
"""Remove machine-specific SwiftPM/toolchain search paths from the assembled app binary."""
from pathlib import Path
import re
import subprocess
import sys

binary = Path(sys.argv[1])
commands = subprocess.check_output(['otool', '-l', str(binary)], text=True)
paths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset \d+\)', commands)
if '@executable_path/../Frameworks' not in paths:
    raise SystemExit('App framework runtime path is missing')
for path in paths:
    if path.startswith('/') and path != '/usr/lib/swift':
        subprocess.run(['install_name_tool', '-delete_rpath', path, str(binary)], check=True)
