import Foundation
import ThreadDomain

/// Defines synthetic normalized event sequences and independent checkpoint expectations.
struct ReplayFixture: Decodable {
    struct Step: Decodable {
        let at: Double
        let event: ActivityEvent?
        let expect: Expectation?
    }
    struct Expectation: Decodable {
        enum Membership: String, Decodable { case new, existing, undetermined }
        let threads: Int
        let active: Anchor?
        let membership: Membership?
    }
    struct Anchor: Hashable, Decodable {
        let repository: String?
        let branch: String?
        let browserURL: String?
        func matches(_ detail: ThreadDetail) -> Bool {
            if let repository {
                let id = RepositoryIdentity(commonDirectory: repository + "/.git")
                return detail.resources.contains { $0.resource.id == .repository(id) }
                    && (branch.map { name in detail.resources.contains { $0.resource.id == .branch(id, name) } } ?? true)
            }
            if let browserURL { return detail.resources.contains { $0.resource.id == .browserPage(.chrome, browserURL) } }
            return false
        }
    }
    let schemaVersion: Int
    let name: String
    let synthetic: Bool
    let purpose: String
    let epoch: Double
    let steps: [Step]

    static func load(_ name: String) throws -> ReplayFixture {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 262_144 else { throw FixtureError.invalid }
        let fixture = try JSONDecoder().decode(Self.self, from: data)
        guard fixture.schemaVersion == 1, fixture.name == name, fixture.synthetic,
              fixture.epoch.isFinite, !fixture.steps.isEmpty else { throw FixtureError.invalid }
        var last = -Double.infinity
        for step in fixture.steps {
            guard step.at.isFinite, step.at >= 0, step.at >= last,
                  (step.event == nil) != (step.expect == nil) else { throw FixtureError.invalid }
            if let event = step.event {
                guard event.timestamp.timeIntervalSince1970 <= fixture.epoch + step.at + 0.000001 else { throw FixtureError.invalid }
            }
            last = step.at
        }
        return fixture
    }
    enum FixtureError: Error { case missing, invalid }
}
