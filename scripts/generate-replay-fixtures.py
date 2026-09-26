#!/usr/bin/env python3
"""Generate synthetic normalized-event fixtures; never capture real user activity."""
import json
from pathlib import Path
from uuid import UUID

ROOT = Path(__file__).resolve().parent.parent
EPOCH = 1704067200
REFERENCE = EPOCH - 978307200
SESSION = {"rawValue": str(UUID(int=101))}
CONNECTION = {"rawValue": str(UUID(int=201))}

class Scenario:
    def __init__(self, name, purpose):
        self.name, self.purpose, self.steps = name, purpose, []
        self.sequence = 0
        self.previous_repository = None

    def event(self, at, source, kind, value):
        event = {"id": {"rawValue": str(UUID(int=len(self.steps) + 1))},
                 "timestamp": REFERENCE + at, "source": {"rawValue": source},
                 "kind": {kind: {"_0": value}}}
        self.steps.append({"at": at, "event": event})

    def project(self, at, name, branch="fix"):
        self.sequence += 1
        path = "/fixture/" + name
        terminal = {"session": SESSION, "processIdentifier": 1, "workingDirectory": path,
                    "terminalApplication": None, "sequence": self.sequence}
        repository = {"identity": {"commonDirectory": path + "/.git"}, "rootPath": path,
                      "gitDirectory": path + "/.git", "branch": branch, "head": None,
                      "dirty": {"changedTrackedFiles": 0, "conflictedFiles": 0, "isApproximate": False}}
        self.event(at, "shell", "terminalDirectoryChanged", terminal)
        kind = "branchChanged" if self.previous_repository and self.previous_repository[0] == path and self.previous_repository[1] != branch else "repositoryChanged"
        self.previous_repository = (path, branch)
        self.event(at, "git", kind, {"terminal": SESSION, "sequence": self.sequence,
                   "resolution": {"available": {"_0": repository}}})

    def browser(self, at, url):
        self.event(at, "browser", "browserTabActivated", {
            "identity": {"connection": CONNECTION, "tab": 1}, "browser": "chrome", "window": 1,
            "url": url, "domain": url.split('/')[2], "title": "Synthetic documentation", "isActive": True})

    def document(self, at, name, basename, pid):
        app = {"identity": {"bundleIdentifier": "fixture.editor"}, "name": "Fixture Editor",
               "processIdentifier": pid, "launchDate": REFERENCE}
        self.event(at, "workspace", "applicationActivated", app)
        self.event(at, "ax", "accessibilityPermissionChanged", "granted")
        self.event(at, "ax", "windowFocused", {"identity": {"rawValue": str(UUID(int=300 + pid))},
                   "application": app, "title": basename, "frame": {"x": 0, "y": 0, "width": 800, "height": 600},
                   "document": {"path": "/fixture/" + name + "/" + basename}})

    def expect(self, at, count, project=None, branch="fix", url=None, membership=None):
        active = {"repository": "/fixture/" + project, "branch": branch} if project else ({"browserURL": url} if url else None)
        expected = {"threads": count, "active": active}
        if membership: expected["membership"] = membership
        self.steps.append({"at": at, "expect": expected})

    def save(self):
        payload = {"schemaVersion": 1, "name": self.name, "synthetic": True, "purpose": self.purpose,
                   "epoch": EPOCH, "steps": self.steps}
        directory = ROOT / "Tests/Fixtures"
        directory.mkdir(exist_ok=True)
        (directory / (self.name + ".json")).write_text(json.dumps(payload, indent=2) + '\n')

s = Scenario("zavori_android_bug", "Multisource project convergence and return to the original Thread")
s.project(0, "Zavori", "fix/android-notifications")
s.document(0.2, "Zavori", "Notifications.kt", 2)
s.browser(1, "https://docs.example.com/android")
s.expect(4, 1, "Zavori", "fix/android-notifications", membership="new")
s.project(20, "CardGame", "rendering")
s.document(20.2, "CardGame", "Renderer.swift", 3)
s.expect(26, 2, "CardGame", "rendering", membership="new")
s.project(40, "Zavori", "fix/android-notifications")
s.document(40.2, "Zavori", "Notifications.kt", 2)
s.expect(46, 2, "Zavori", "fix/android-notifications", membership="existing")
s.save()

s = Scenario("homecontrol_ota_switch", "Same repository on different branches must form separate work and reuse prior identities")
s.project(0, "HomeControl", "fix/ota-reconnect")
s.expect(3, 1, "HomeControl", "fix/ota-reconnect", membership="new")
s.project(20, "HomeControl", "feature/dashboard")
s.expect(26, 2, "HomeControl", "feature/dashboard", membership="new")
s.project(40, "HomeControl", "fix/ota-reconnect")
s.expect(46, 2, "HomeControl", "fix/ota-reconnect", membership="existing")
s.save()

s = Scenario("browser_research_switch", "Brief research waits, sustained research creates work, neutral private focus cannot create a Thread")
s.browser(0, "https://docs.example.com/research")
s.expect(3, 0, membership="undetermined")
s.browser(21, "https://docs.example.com/research")
s.expect(24, 1, url="https://docs.example.com/research", membership="new")
s.browser(25, "https://search.example.com/")
s.expect(28, 1, url="https://docs.example.com/research", membership="existing")
s.event(29, "browser", "browserFocusCleared", CONNECTION)
s.event(30, "workspace", "applicationActivated", {"identity": {"bundleIdentifier": "com.google.Chrome"},
        "name": "Chrome", "processIdentifier": 10, "launchDate": REFERENCE})
s.expect(33, 1, url="https://docs.example.com/research", membership="undetermined")
s.save()

s = Scenario("rapid_context_switch", "Historical contexts update membership without rapidly switching active work")
s.project(0, "A")
s.expect(3, 1, "A", membership="new")
for at, project in [(10, "B"), (11, "C"), (12, "A"), (13, "B"), (14, "A")]: s.project(at, project)
s.expect(17, 3, "A", membership="existing")
s.project(20, "B")
s.expect(26, 3, "B", membership="existing")
s.save()

s = Scenario("ambiguous_context", "Documentation shared across two projects remains ambiguous after repository evidence expires")
url = "https://docs.example.com/shared"
s.project(0, "A")
s.browser(1, url)
s.expect(4, 1, "A", membership="new")
s.project(20, "B")
s.browser(21, url)
s.expect(26, 2, "B", membership="new")
s.browser(70, url)
s.expect(73, 2, "B", membership="undetermined")
s.browser(91, url)
s.expect(94, 2, "B", membership="undetermined")
s.save()
