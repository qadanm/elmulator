import Elmulator
import Foundation
import Testing
@testable import ElmulatorTCP

/// Locate the repo's `scenarios/` directory relative to this source file so
/// tests need no working-directory assumptions or external fixtures package.
func scenarioURL(_ name: String) -> URL {
    URL(filePath: #filePath)            // .../Tests/ElmulatorTests/EngineTests.swift
        .deletingLastPathComponent()    // ElmulatorTests
        .deletingLastPathComponent()    // Tests
        .deletingLastPathComponent()    // repo root
        .appending(path: "scenarios")
        .appending(path: "\(name).scenario.json")
}

func loadScenario(_ name: String) throws -> FakeELMScenario {
    try FakeELMScenario.load(from: scenarioURL(name))
}

@Suite("FakeELM scenario engine")
struct EngineTests {
    @Test("all committed scenarios load and are synthetic")
    func scenariosLoad() throws {
        for name in [
            "no_codes_basic", "p0420_basic", "p0301_basic", "malformed",
            "chunked_stream", "adapter_disconnect", "headers_off_echo_on",
        ] {
            let scenario = try loadScenario(name)
            #expect(scenario.synthetic)
            #expect(scenario.scenarioID == name)
            #expect(!scenario.commands.isEmpty)
        }
    }

    @Test("command matching is whitespace and case insensitive")
    func normalization() throws {
        var engine = FakeELMScenarioEngine(scenario: try loadScenario("p0420_basic"))
        let plan = engine.plan(for: " at z \r")
        #expect(plan.matchedRequest == "ATZ")
        #expect(plan.joinedASCII.contains("ELM327 v1.5"))
    }

    @Test("echo true prepends the request before the reply")
    func echoBehavior() throws {
        var engine = FakeELMScenarioEngine(scenario: try loadScenario("p0420_basic"))
        let reset = engine.plan(for: "ATZ")
        #expect(reset.joinedASCII.hasPrefix("ATZ\r"))
        _ = engine.plan(for: "ATE0")
        let headers = engine.plan(for: "ATH1")
        #expect(!headers.joinedASCII.hasPrefix("ATH1"))
    }

    @Test("unknown AT and OBD commands get scenario defaults")
    func defaults() throws {
        var engine = FakeELMScenarioEngine(scenario: try loadScenario("p0420_basic"))
        let at = engine.plan(for: "ATDPN")
        #expect(at.matchedRequest == nil)
        #expect(at.joinedASCII == "OK\r\r>")
        let obd = engine.plan(for: "0142")
        #expect(obd.matchedRequest == nil)
        #expect(obd.joinedASCII == "NO DATA\r\r>")
    }

    @Test("entries consume in order and the last one repeats")
    func consumptionOrder() throws {
        var engine = FakeELMScenarioEngine(scenario: try loadScenario("adapter_disconnect"))
        let first = engine.plan(for: "0100")
        #expect(first.pieces.isEmpty)
        #expect(first.postAction == .stall)
        let second = engine.plan(for: "0100")
        #expect(second.joinedASCII.contains("41 00 BE 3E B8 11"))
        let third = engine.plan(for: "0100")
        #expect(third.joinedASCII.contains("41 00 BE 3E B8 11"))
    }

    @Test("disconnect action is reported to the host")
    func disconnectAction() throws {
        var engine = FakeELMScenarioEngine(scenario: try loadScenario("adapter_disconnect"))
        for command in ["ATZ", "ATE0", "ATL0", "ATH1", "ATSP0", "0100", "0100", "0120", "0101"] {
            _ = engine.plan(for: command)
        }
        let dropped = engine.plan(for: "03")
        #expect(dropped.postAction == .disconnect)
        #expect(dropped.pieces.isEmpty)
    }

    @Test("scenario stream_split_bytes splits every reply")
    func scenarioSplitting() throws {
        var engine = FakeELMScenarioEngine(scenario: try loadScenario("chunked_stream"))
        let plan = engine.plan(for: "0100")
        #expect(plan.pieces.count > 3)
        #expect(plan.pieces.allSatisfy { $0.bytes.count <= 7 })
        #expect(plan.joinedASCII == "SEARCHING...\r7E8 06 41 00 BE 3E B8 11\r\r>")
    }

    @Test("configuration split pattern cycles sizes")
    func patternSplitting() throws {
        var engine = FakeELMScenarioEngine(
            scenario: try loadScenario("p0420_basic"),
            configuration: .init(splitPattern: [1, 2, 5])
        )
        _ = engine.plan(for: "ATZ")
        _ = engine.plan(for: "ATE0")
        let plan = engine.plan(for: "0105")
        #expect(plan.pieces.count >= 4)
        #expect(plan.pieces[0].bytes.count == 1)
        #expect(plan.pieces[1].bytes.count == 2)
        #expect(plan.pieces[2].bytes.count == 5)
        #expect(plan.joinedASCII == "7E8 03 41 05 7B\r\r>")
    }

    @Test("echo override forces echo on regardless of scenario")
    func echoOverride() throws {
        var engine = FakeELMScenarioEngine(
            scenario: try loadScenario("p0420_basic"),
            configuration: .init(echoOverride: true)
        )
        _ = engine.plan(for: "ATZ")
        _ = engine.plan(for: "ATE0")
        let plan = engine.plan(for: "ATH1")
        #expect(plan.joinedASCII.hasPrefix("ATH1\r"))
    }

    @Test("jitter is deterministic for a fixed seed")
    func deterministicJitter() throws {
        func delays(seed: UInt64) throws -> [Int] {
            var engine = FakeELMScenarioEngine(
                scenario: try loadScenario("p0420_basic"),
                configuration: .init(jitterMS: 50, seed: seed)
            )
            return ["ATZ", "ATE0", "ATL0"].map { engine.plan(for: $0).pieces.first?.delayMS ?? -1 }
        }
        #expect(try delays(seed: 42) == delays(seed: 42))
    }

    @Test("prompt content is preserved exactly")
    func promptPreserved() throws {
        var engine = FakeELMScenarioEngine(scenario: try loadScenario("no_codes_basic"))
        for command in ["ATZ", "ATE0", "ATL0", "ATH1", "ATSP0"] {
            let plan = engine.plan(for: command)
            #expect(plan.joinedASCII.hasSuffix(">"), "\(command) reply must end at the prompt")
        }
    }

    @Test("multi-line and malformed content passes through untouched")
    func contentPassthrough() throws {
        var vinEngine = FakeELMScenarioEngine(scenario: try loadScenario("no_codes_basic"))
        for command in ["ATZ", "ATE0", "ATL0", "ATH1", "ATSP0", "0100", "0120", "0101", "03", "07", "0A"] {
            _ = vinEngine.plan(for: command)
        }
        let vin = vinEngine.plan(for: "0902")
        #expect(vin.joinedASCII.contains("7E8 10 14 49 02 01 31 43 34\r"))
        #expect(vin.joinedASCII.contains("7E8 22 43 31 32 33 34 35 36\r\r>"))

        var badEngine = FakeELMScenarioEngine(scenario: try loadScenario("malformed"))
        for command in ["ATZ", "ATE0", "ATL0", "ATH1", "ATSP0", "0100", "0101"] {
            _ = badEngine.plan(for: command)
        }
        #expect(badEngine.plan(for: "03").joinedASCII == "43 ZZ\r\r>")
    }

    @Test("non-synthetic scenarios are refused")
    func refusesNonSynthetic() throws {
        let json = """
        {"schema_version": "obd2.sim_scenario.v1", "scenario_id": "bad", "synthetic": false,
         "description": "x", "adapter_profile": "x",
         "defaults": {"at_response": "OK\\r\\r>", "obd_response": "NO DATA\\r\\r>"},
         "stream_split_bytes": null, "warnings": [], "commands": [],
         "expected_scan_summary": {}}
        """
        let url = FileManager.default.temporaryDirectory
            .appending(path: "bad-\(UUID().uuidString).scenario.json")
        try json.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: FakeELMScenario.LoadError.notSynthetic("bad")) {
            _ = try FakeELMScenario.load(from: url)
        }
    }
}

@Suite("FakeELM line framing")
struct LineFramingTests {
    @Test("commands split on CR or LF and partials stay buffered")
    func lineExtraction() {
        var buffer = "010"
        #expect(FakeELMTCPServer.takeLine(from: &buffer) == nil)
        buffer += "0\r01"
        #expect(FakeELMTCPServer.takeLine(from: &buffer) == "0100")
        #expect(FakeELMTCPServer.takeLine(from: &buffer) == nil)
        buffer += "05\n"
        #expect(FakeELMTCPServer.takeLine(from: &buffer) == "0105")
        #expect(buffer.isEmpty)
    }
}
