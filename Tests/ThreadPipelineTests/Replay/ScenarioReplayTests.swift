import Testing

struct ScenarioReplayTests {
    @Test(arguments: ["zavori_android_bug", "homecontrol_ota_switch", "browser_research_switch",
                      "rapid_context_switch", "ambiguous_context"], [false, true])
    func normalizedFixturesMatchExpectedWorkWithLocalAndUnavailableRemote(_ name: String, remoteUnavailable: Bool) async throws {
        let fixture = try ReplayFixture.load(name)
        var replay = FixtureReplay(remoteUnavailable: remoteUnavailable)
        try await replay.run(fixture)
    }
}
