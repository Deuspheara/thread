import Foundation
import Observation
import ThreadDomain

/// Edits privacy rules and waits for durable storage and live application before reporting success.
@MainActor
@Observable
public final class ObservationExclusionsModel {
    public var applicationsText = ""
    public var domainsText = ""
    public private(set) var saving = false
    public private(set) var message: String?
    private let load: @MainActor () async throws -> ObservationExclusions
    private let save: @MainActor (ObservationExclusions) async throws -> Void

    public init(initial: ObservationExclusions?, load: @escaping @MainActor () async throws -> ObservationExclusions,
                save: @escaping @MainActor (ObservationExclusions) async throws -> Void) {
        self.load = load
        self.save = save
        if let initial { display(initial) }
        else { message = "Privacy rules could not be read. Observation is paused. Save rules to resume." }
    }

    public func apply() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let value = try ObservationExclusions(applications: lines(applicationsText), domains: lines(domainsText))
            try await save(value)
            display(value)
            message = "Saved. Exclusions apply to new activity; existing history remains."
        } catch IntentCompletionError.unknown {
            message = "Connection lost. The rules may have saved. Reload saved rules before retrying."
        } catch is ExclusionError {
            message = "Use up to 64 bundle identifiers and 64 domains, one per line. Enter domains without URLs or wildcards."
        } catch {
            message = "Privacy rules could not be saved. Try again."
        }
    }

    public func reload() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do { display(try await load()); message = "Loaded. Save to apply these rules." }
        catch { message = "Privacy rules could not be read. Try again." }
    }

    private func display(_ value: ObservationExclusions) {
        applicationsText = value.applications.joined(separator: "\n")
        domainsText = value.domains.joined(separator: "\n")
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
