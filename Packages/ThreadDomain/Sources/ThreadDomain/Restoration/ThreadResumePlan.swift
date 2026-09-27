import Foundation

/// Shares deterministic confirmed resume targets between execution and local presentation.
public struct ThreadResumePlan: Equatable, Codable, Sendable {
    public let targets: [RestoreTarget]
    public init(_ detail: ThreadDetail, directoryIdentity: @Sendable (String) -> String = {
        URL(fileURLWithPath: $0).standardizedFileURL.path
    }) {
        let confirmed = detail.resources.filter { $0.status == .confirmed }
        let ordered = confirmed.filter { $0.resource.kind == .application }
            + confirmed.filter { $0.resource.kind == .terminal }
            + confirmed.filter { ![.application, .terminal, .window, .branch].contains($0.resource.kind) }
            + confirmed.filter { $0.resource.kind == .window }
        let documents = Set(confirmed.compactMap { edge -> ResourceID? in
            edge.resource.kind == .file ? edge.resource.id : nil
        })
        let documentApps = Set(confirmed.compactMap { $0.restoreApplication?.identity })
        let destinationApps = Set(confirmed.filter { ![.application, .window, .branch].contains($0.resource.kind) }
            .compactMap { ThreadResumePlan.application(for: RestoreTarget(resource: $0.resource, application: $0.restoreApplication)).identity })
        let projectPaths = Set(confirmed.compactMap { Self.directory($0.resource) }.map(directoryIdentity))
        var directories = Set<String>()
        targets = ordered.compactMap { edge in
            if case .application(let app) = edge.resource, (documentApps.contains(app.identity) || destinationApps.contains(app.identity)) { return nil }
            if case .window(let window) = edge.resource, let file = window.document,
               documents.contains(Resource.file(file).id) { return nil }
            if let path = Self.directory(edge.resource), !directories.insert(directoryIdentity(path)).inserted { return nil }
            let fallback: RestoreApplication?
            if case .file(let file) = edge.resource,
               URL(fileURLWithPath: file.path).pathExtension.lowercased() == "code-workspace" {
                fallback = RestoreApplication(identity: ApplicationIdentity(bundleIdentifier: "com.microsoft.VSCode"), name: "VS Code", origin: .fallback)
            } else { fallback = nil }
            let isProject: Bool
            if case .file(let file) = edge.resource { isProject = projectPaths.contains(directoryIdentity(file.path)) }
            else { isProject = false }
            return RestoreTarget(resource: edge.resource, application: edge.restoreApplication ?? fallback, isProject: isProject)
        }
    }
    public static func directory(_ resource: Resource) -> String? {
        switch resource {
        case .terminal(let value): value.workingDirectory
        case .workingDirectory(let path): path
        case .repository(let value): value.rootPath
        default: nil
        }
    }
}

public extension ThreadReading {
    /// Reads a bounded complete plan; a partial page is never advertised as the complete resume.
    func resumePlan(_ thread: ThreadID) async throws -> ThreadResumePlan? {
        var resources: [ThreadResource] = []
        var cursor: ResourceID?
        repeat {
            guard let page = try await detailPage(thread, after: cursor, limit: 64) else { return nil }
            if let plan = page.resumePlan { return plan }
            resources.append(contentsOf: page.resources)
            cursor = page.next
            if cursor == nil { return ThreadResumePlan(ThreadDetail(thread: page.thread, resources: resources)) }
        } while resources.count < 512
        throw ThreadReadError.unavailable
    }
}
