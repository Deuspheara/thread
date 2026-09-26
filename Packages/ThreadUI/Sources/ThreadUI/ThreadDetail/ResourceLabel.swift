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
