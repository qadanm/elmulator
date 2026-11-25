import Elmulator
import Testing

@Suite("Synthetic CAN clear outcome oracle")
struct ClearFixtureTests {
    private static let prescan = [
        ("03", "7E8 04 43 01 04 20\r7EA 02 43 00\r\r>"),
        ("07", "7E8 04 47 01 03 01\r7EA 02 47 00\r\r>"),
        ("0A", "7E8 04 4A 01 04 20\r7EA 02 4A 00\r\r>"),
        ("0101", "7E8 06 41 01 81 07 01 00\r7EA 06 41 01 00 04 00 00\r\r>")
    ]

    @Test func acknowledgedTranscriptKeepsPermanentCodes() throws {
        let scenario = try Scenario.bundled("can_clear_acknowledged")
        var engine = try checkPrescan(scenario, clearHasPrompt: true)
        checkReply("04", "7E8 01 44\r7EA 01 44\r\r>", in: &engine)

        checkReply("03", "7E8 02 43 00\r7EA 02 43 00\r\r>", in: &engine)
        checkReply("07", "7E8 02 47 00\r7EA 02 47 00\r\r>", in: &engine)
        checkReply("0A", "7E8 04 4A 01 04 20\r7EA 02 4A 00\r\r>", in: &engine)
        checkReply("0101", "7E8 06 41 01 00 77 01 01\r7EA 06 41 01 00 44 00 00\r\r>", in: &engine)
    }

    @Test func negativeTranscriptKeepsThePrescanEvidence() throws {
        let scenario = try Scenario.bundled("can_clear_negative")
        var engine = try checkPrescan(scenario, clearHasPrompt: true)
        checkReply("04", "7E8 03 7F 04 22\r7EA 03 7F 04 22\r\r>", in: &engine)

        for (request, bytes) in Self.prescan {
            checkReply(request, bytes, in: &engine)
        }
    }

    @Test func ambiguousTranscriptsHaveDistinctBytesAndTransportActions() throws {
        let outcomes: [(String, String, Scenario.PostAction)] = [
            ("can_clear_lost_ack", "", .disconnect),
            ("can_clear_timeout", "", .stall),
            ("can_clear_partial_ack", "7E8 01 44\r\r>", .none),
            ("can_clear_pending", "7E8 01 44\r7EA 03 7F 04 78\r", .none)
        ]
        for (name, bytes, action) in outcomes {
            let scenario = try Scenario.bundled(name)
            var engine = try checkPrescan(scenario, clearHasPrompt: bytes.hasSuffix(">"))
            checkReply("04", bytes, action: action, in: &engine, scenario: name)
        }
    }

    private func checkPrescan(_ scenario: Scenario, clearHasPrompt: Bool) throws -> ScenarioEngine {
        #expect(scenario.synthetic)
        #expect(scenario.expectedScanSummary == Scenario.ExpectedScanSummary())
        let clear = try #require(scenario.commands.first { $0.request == "04" })
        #expect(clear.prompt == clearHasPrompt, "\(scenario.scenarioID)")

        var engine = ScenarioEngine(scenario: scenario)
        for (request, bytes) in Self.prescan {
            checkReply(request, bytes, in: &engine, scenario: scenario.scenarioID)
        }
        return engine
    }

    private func checkReply(
        _ request: String,
        _ bytes: String,
        action: Scenario.PostAction = .none,
        in engine: inout ScenarioEngine,
        scenario: String = ""
    ) {
        let plan = engine.plan(for: request)
        #expect(plan.matchedRequest == request, "\(scenario) \(request)")
        #expect(plan.joinedASCII == bytes, "\(scenario) \(request)")
        #expect(plan.postAction == action, "\(scenario) \(request)")
    }
}
