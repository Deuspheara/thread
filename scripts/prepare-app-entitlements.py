#!/usr/bin/env python3
"""Resolve supplied signing configuration without inventing a team or App Group."""
import os
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parent.parent
identity = os.environ.get("THREAD_SIGNING_IDENTITY", "-")
group = os.environ.get("THREAD_APP_GROUP", "")
if group and identity == "-":
    raise SystemExit("THREAD_APP_GROUP requires THREAD_SIGNING_IDENTITY; ad-hoc signing cannot authorize a shared group.")
if any(character.isspace() for character in group) or "$" in group:
    raise SystemExit("Invalid App Group identifier.")
app = {}
extension = {"com.apple.security.app-sandbox": True}
if group:
    app["com.apple.security.application-groups"] = [group]
    extension["com.apple.security.application-groups"] = [group]
(root / "build").mkdir(exist_ok=True)
for name, entitlements in [("app", app), ("safari", extension)]:
    (root / f"build/{name}.entitlements").write_bytes(plistlib.dumps(entitlements))
info_path = root / "build/Thread.app/Contents/Info.plist"
info = plistlib.loads(info_path.read_bytes())
if group:
    info["ThreadAppGroupIdentifier"] = group
else:
    info.pop("ThreadAppGroupIdentifier", None)
info_path.write_bytes(plistlib.dumps(info))
