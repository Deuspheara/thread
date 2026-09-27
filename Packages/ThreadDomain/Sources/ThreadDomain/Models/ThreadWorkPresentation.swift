import Foundation

/// Identifies a local application for presentation without retaining process or platform objects.
public struct WorkApplication: Equatable, Hashable, Codable, Sendable, Identifiable {
    public let identity: ApplicationIdentity?
    public let name: String
    public var id: String { identity?.bundleIdentifier ?? name }
    public init(identity: ApplicationIdentity?, name: String) { self.identity = identity; self.name = name }
}

/// Groups actual planned operations by their application, leaving unknown ownership honest.
public struct ThreadApplicationGroup: Equatable, Codable, Sendable, Identifiable {
    public let application: WorkApplication
    public let targets: [RestoreTarget]
    public var id: String { application.id }
    public var preview: String {
        let files = targets.filter { $0.resource.kind == .file && !$0.isProject }.count
        let projects = targets.filter(\.isProject).count
        let tabs = targets.filter { $0.resource.kind == .browserPage }.count
        if tabs > 0 { return "\(tabs) \(tabs == 1 ? "tab" : "tabs")" }
        if projects > 0 { return files == 0 ? "Project" : "Project + \(files) \(files == 1 ? "file" : "files")" }
        if files > 0 { return "\(files) \(files == 1 ? "file" : "files")" }
        if let path = targets.compactMap({ ThreadResumePlan.directory($0.resource) }).first {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return targets.contains { $0.resource.kind == .window } ? "Existing window" : "Activate"
    }
    public var description: String {
        if targets.contains(where: { $0.resource.kind == .file }) {
            return application.identity == nil ? "Open with the macOS default application" : "Request files or projects in \(application.name)"
        }
        if targets.contains(where: { $0.resource.kind == .browserPage }) { return "Focus or reopen public pages" }
        if targets.contains(where: { ThreadResumePlan.directory($0.resource) != nil }) { return "Open directory; commands are never replayed" }
        return "Activate application or match an existing window"
    }
}

/// Carries bounded application and project anchors for primary launcher rows.
public struct ThreadWorkSummary: Equatable, Codable, Sendable {
    public let applications: [WorkApplication]
    public let project: String?
    public let branch: String?
    public var context: String {
        [project, branch].compactMap { $0 }.joined(separator: " · ")
    }
    public init(_ detail: ThreadDetail) {
        let confirmed = detail.resources.filter { $0.status == .confirmed }
        let repository = confirmed.compactMap { edge -> RepositoryContext? in
            if case .repository(let value) = edge.resource { return value }; return nil
        }.sorted { $0.rootPath < $1.rootPath }.first
        let directory = repository?.rootPath ?? confirmed.compactMap { ThreadResumePlan.directory($0.resource) }.sorted().first
        project = directory.map { URL(fileURLWithPath: $0).lastPathComponent }
        branch = repository?.branch ?? confirmed.compactMap { edge -> String? in
            if case .branch(_, let name) = edge.resource { return name }; return nil
        }.sorted().first
        applications = Array(ThreadResumePlan(detail).groups.map(\.application).filter { $0.name != "Other items" }.prefix(8))
    }
}

public extension ThreadResumePlan {
    var groups: [ThreadApplicationGroup] {
        var groups: [ThreadApplicationGroup] = []
        for target in targets {
            let app = Self.application(for: target)
            if let index = groups.firstIndex(where: { $0.application == app }) {
                groups[index] = ThreadApplicationGroup(application: app, targets: groups[index].targets + [target])
            } else { groups.append(ThreadApplicationGroup(application: app, targets: [target])) }
        }
        return groups.sorted {
            let left = Self.presentationOrder($0), right = Self.presentationOrder($1)
            return left == right ? $0.application.name < $1.application.name : left < right
        }
    }
    private static func presentationOrder(_ group: ThreadApplicationGroup) -> Int {
        if group.targets.contains(where: { $0.resource.kind == .file }) { return 0 }
        if group.targets.contains(where: { $0.resource.kind == .browserPage }) { return 1 }
        if group.targets.contains(where: { ThreadResumePlan.directory($0.resource) != nil }) { return 2 }
        return 3
    }
    static func application(for target: RestoreTarget) -> WorkApplication {
        if let app = target.application { return WorkApplication(identity: app.identity, name: app.name) }
        switch target.resource {
        case .application(let app): return WorkApplication(identity: app.identity, name: app.name)
        case .window(let window): return WorkApplication(identity: window.application.identity, name: window.application.name)
        case .browserPage(let tab):
            let known: (String?, String)
            switch tab.browser {
            case .brave: known = ("com.brave.Browser", "Brave")
            case .chrome: known = ("com.google.Chrome", "Chrome")
            case .edge: known = ("com.microsoft.edgemac", "Edge")
            case .safari: known = ("com.apple.Safari", "Safari")
            case .chromium: known = (nil, "Browser")
            }
            let identity = tab.application ?? known.0.map { ApplicationIdentity(bundleIdentifier: $0) }
            return WorkApplication(identity: identity, name: known.1)
        case .terminal, .workingDirectory, .repository:
            return WorkApplication(identity: ApplicationIdentity(bundleIdentifier: "com.apple.Terminal"), name: "Terminal")
        case .file(let file):
            if URL(fileURLWithPath: file.path).pathExtension.lowercased() == "code-workspace" {
                return WorkApplication(identity: ApplicationIdentity(bundleIdentifier: "com.microsoft.VSCode"), name: "VS Code")
            }
            return WorkApplication(identity: nil, name: "Default application")
        case .branch:
            return WorkApplication(identity: nil, name: "Other items")
        }
    }
}
