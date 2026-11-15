import Elmulator
import Testing

@Suite("CAN validation oracle bytes")
struct CANFixtureTests {
    @Test func authoredBytesAreUnchanged() throws {
        let expectations = [
            ("can_wrong_service", "03", "7E8 04 47 01 04 20\r\r>"),
            ("can_invalid_hex", "03", "7E8 04 43 01 GG 20\r\r>"),
            ("can_truncated_payload", "03", "7E8 06 43 01 04 20\r\r>"),
            ("can_padded_rpm", "010C", "7E8 04 41 0C 1A F8 AA BB CC\r\r>")
        ]
        for (name, request, expected) in expectations {
            var engine = ScenarioEngine(scenario: try Scenario.bundled(name))
            #expect(engine.plan(for: request).joinedASCII == expected, "\(name)")
        }
    }
    @Test func invalidResultsDoNotPromiseEmptyCodes() throws {
        for name in ["can_wrong_service", "can_invalid_hex", "can_truncated_payload"] {
            let expected = try Scenario.bundled(name).expectedScanSummary
            #expect(expected.storedCodes == nil)
            #expect(expected.noStoredCodesObservation == false)
            #expect(expected.minSessionWarnings == 1)
        }
    }
}
