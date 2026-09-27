import Foundation
import ThreadDomain

/// Formats resource metadata for local inspection without changing its identity.
struct ResourceLabel {
    func kind(_ resource: Resource) -> String {
        switch resource.kind {
        case .application: "Application"
        case .window: "Window"
        case .browserPage: "Browser tab"
        case .terminal: "Terminal session"
        case .workingDirectory: "Directory"
        case .repository: "Repository"
        case .branch: "Git branch"
        case .file: "File"
        }
    }

    func title(_ id: ResourceID) -> String {
        switch id {
        case .file(let file): URL(fileURLWithPath: file.path).lastPathComponent
        case .workingDirectory(let path): path
        case .application(let app): app.bundleIdentifier
        case .repository(let repository): repository.commonDirectory
        case .branch(_, let name): name
        case .window: "Existing window"
        case .terminal: "Terminal directory"
        case .browserPage(_, let url): url
        }
    }

    func symbol(_ resource: Resource) -> String {
        switch resource.kind {
        case .file: "doc"
        case .browserPage: "globe"
        case .terminal: "terminal"
        case .workingDirectory, .repository: "folder"
        case .branch: "arrow.triangle.branch"
        case .application: "app"
        case .window: "macwindow"
        }
    }

    func compactTitle(_ resource: Resource) -> String {
        switch resource {
        case .file(let file): URL(fileURLWithPath: file.path).lastPathComponent
        case .repository(let repository): URL(fileURLWithPath: repository.rootPath).lastPathComponent
        case .workingDirectory(let path): URL(fileURLWithPath: path).lastPathComponent
        case .terminal(let terminal): URL(fileURLWithPath: terminal.workingDirectory).lastPathComponent
        default: title(resource)
        }
    }

    func title(_ resource: Resource) -> String {
        switch resource {
        case .application(let value): value.name
        case .window(let value): value.title ?? "Window"
        case .browserPage(let value): value.title
        case .terminal(let value): value.workingDirectory
        case .workingDirectory(let path): path
        case .repository(let value): value.rootPath
        case .branch(_, let name): name
        case .file(let value): value.path
        }
    }
}
