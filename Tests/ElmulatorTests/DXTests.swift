import Elmulator
import ElmulatorTCP
import ElmulatorTestSupport
import Foundation
import Testing

// `scenarioURL(_:)` is shared from EngineTests.swift in this target.

@Suite("Scenario builder and Codable round-trip")
struct ScenarioBuilderTests {
    @Test("an inline scenario drives the engine")
    func inlineDrivesEngine() {
        let scenario = Scenario(id: "inline", commands: [
            Scenario.Command(request: "ATZ", responseChunks: ["ELM327 v1.5\r\r>"], echo: true),
            Scenario.Command(request: "03", responseChunks: ["7E8 04 43 01 04 20\r\r>"]),
        ])
        var engine = ScenarioEngine(scenario: scenario)
        #expect(engine.plan(for: "ATZ").joinedASCII.hasPrefix("ATZ\r"))
        #expect(engine.plan(for: "03").joinedASCII.contains("43 01 04 20"))
    }

    @Test("Codable round-trips an inline scenario")
    func codableRoundTrip() throws {
        let scenario = Scenario(
            scenarioID: "x",
            commands: [Scenario.Command(request: "ATZ", responseChunks: ["OK\r\r>"])],
            expectedScanSummary: Scenario.ExpectedScanSummary(storedCodes: ["P0420"], milReportedOn: true)
        )
        let data = try JSONEncoder().encode(scenario)
        #expect(try JSONDecoder().decode(Scenario.self, from: data) == scenario)
    }
}

@Suite("Bundled scenarios")
struct BundledScenarioTests {
    @Test("bundled equals load for every scenario")
    func bundledEqualsLoad() throws {
        for name in Scenario.bundledNames {
            #expect(try Scenario.bundled(name) == Scenario.load(from: scenarioURL(name)), "\(name)")
        }
    }

    @Test("bundledNames is the scenario set")
    func names() {
        #expect(Scenario.bundledNames.contains("p0420_basic"))
        #expect(Scenario.bundledNames.count == 7)
    }

    @Test("unknown bundled name throws")
    func unknown() {
        #expect(throws: Scenario.LoadError.unknownBundled("nope")) {
            _ = try Scenario.bundled("nope")
        }
    }
}

@Suite("Test client")
struct TestClientTests {
    @Test("Conversation drives a bundled scenario in-process")
    func conversation() throws {
        var adapter = try Conversation(bundled: "p0420_basic")
        #expect(adapter.send("ATZ").contains("ELM327 v1.5"))
        #expect(adapter.send("03").contains("43 01 04 20"))
        #expect(adapter.send("0142") == "NO DATA\r\r>")     // default path
        #expect(adapter.transcript.count == 3)
    }

    @Test("Client runs a scan over a real TCP server")
    func clientOverTCP() async throws {
        let server = TCPServer(scenario: try .bundled("p0420_basic"))
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let client = Client(port: port)
        try await client.connect()
        #expect(try await client.send("ATZ").contains("ELM327 v1.5"))
        #expect(try await client.send("03").contains("43 01 04 20"))
        await client.close()
    }
}

@Suite("Engine transcript")
struct TranscriptTests {
    @Test("off by default, populated when enabled")
    func transcript() throws {
        let scenario = try Scenario.bundled("p0420_basic")

        var off = ScenarioEngine(scenario: scenario)
        _ = off.plan(for: "ATZ")
        #expect(off.transcript.isEmpty)

        var on = ScenarioEngine(scenario: scenario, configuration: .init(recordTranscript: true))
        _ = on.plan(for: "ATZ")
        _ = on.plan(for: "03")
        #expect(on.transcript.count == 2)
        #expect(on.transcript.last?.matchedRequest == "03")
        #expect(on.transcript.last?.debugDump().contains("43 01 04 20") == true)
    }
}

@Suite("Scan summary mismatches")
struct SummaryMismatchTests {
    @Test("only set expectation fields are checked")
    func mismatches() {
        let expected = Scenario.ExpectedScanSummary(
            storedCodes: ["P0420"], milReportedOn: true, minSessionWarnings: 1
        )
        #expect(expected.mismatches(observed: .init(
            storedCodes: ["P0420"], milReportedOn: true, sessionWarnings: 2
        )).isEmpty)

        let diffs = expected.mismatches(observed: .init(
            storedCodes: ["P0301"], milReportedOn: true, sessionWarnings: 0
        ))
        #expect(diffs.contains { $0.field == "stored_codes" })
        #expect(diffs.contains { $0.field == "min_session_warnings" })
        #expect(!diffs.contains { $0.field == "vin_reported" })   // nil expectation is ignored
    }
}
