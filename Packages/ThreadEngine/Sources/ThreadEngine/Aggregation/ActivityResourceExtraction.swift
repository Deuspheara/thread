import ThreadDomain

/// Selects only accepted foreground or shell evidence, never background tab inventories.
struct ActivityResourceExtraction {
    func resources(for event: ActivityEvent, accepted state: CurrentContext) -> [Resource] {
        switch event.kind {
        case .applicationActivated(let app):
            return state.application == app ? [.application(app)] : []
        case .windowFocused(let window), .windowUpdated(let window):
            guard state.window == window else { return [] }
            var resources: [Resource] = [.application(window.application), .window(window)]
            if let document = window.document { resources.append(.file(document)) }
            return resources
        case .browserTabActivated(let tab), .browserTabUpdated(let tab):
            return state.browserTab == tab ? [.browserPage(tab)] : []
        case .terminalDirectoryChanged(let terminal), .terminalCommandCompleted(let terminal, _):
            return state.terminal == terminal ? [.terminal(terminal), .workingDirectory(terminal.workingDirectory)] : []
        case .repositoryChanged(let observation), .branchChanged(let observation):
            guard let terminal = state.terminal, terminal.session == observation.terminal,
                  terminal.sequence == observation.sequence,
                  case .available(let repository) = observation.resolution else { return [] }
            var result: [Resource] = [.terminal(terminal), .workingDirectory(terminal.workingDirectory), .repository(repository)]
            if let branch = repository.branch { result.append(.branch(repository.identity, branch)) }
            return result
        default: return []
        }
    }
}
