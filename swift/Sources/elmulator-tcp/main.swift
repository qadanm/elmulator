import Elmulator
import ElmulatorTCP
import Foundation

// Dev/test tool. Hosts a scenario over localhost TCP. The Python equivalent
// is `elmulator serve`; both speak the same scenario format with identical
// semantics, which the conformance suite verifies byte-for-byte.

let usage = """
elmulator-tcp: host a synthetic ELM327 over localhost TCP.

Usage:
  elmulator-tcp --scenario PATH [options]

Options:
  --scenario PATH     scenario file (*.scenario.json)
  --port N            TCP port (default 35000; 0 picks a free port)
  --echo MODE         on | off | scenario (default: scenario)
  --split a,b,c       cycled extra chunk sizes
  --latency-ms N      extra latency added to each reply (default 0)
  --jitter-ms N       deterministic jitter bound, uses --seed (default 0)
  --seed N            jitter seed (default 0)
  --help              print this message

Prints "LISTENING <port>" on stdout once bound. Binds 127.0.0.1.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n\n\(usage)\n".utf8))
    exit(2)
}

var values: [String: String] = [:]
do {
    let list = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < list.count {
        let token = list[index]
        guard token.hasPrefix("--") else { fail("unexpected argument: \(token)") }
        if token == "--help" { print(usage); exit(0) }
        guard index + 1 < list.count else { fail("missing value for \(token)") }
        values[token] = list[index + 1]
        index += 2
    }
}

guard let scenarioPath = values["--scenario"] else { fail("--scenario is required") }

func intValue(_ key: String, in values: [String: String], default fallback: Int) -> Int {
    guard let raw = values[key] else { return fallback }
    guard let value = Int(raw) else { fail("\(key) must be an integer") }
    return value
}

let echoOverride: Bool?
switch values["--echo"] ?? "scenario" {
case "on": echoOverride = true
case "off": echoOverride = false
case "scenario": echoOverride = nil
default: fail("--echo must be on, off, or scenario")
}

let splitPattern = values["--split"].map { text in
    text.split(separator: ",").compactMap { Int($0) }
}

let configuration = FakeELMEngineConfiguration(
    splitPattern: splitPattern,
    echoOverride: echoOverride,
    extraLatencyMS: intValue("--latency-ms", in: values, default: 0),
    jitterMS: intValue("--jitter-ms", in: values, default: 0),
    seed: UInt64(intValue("--seed", in: values, default: 0))
)

let port = UInt16(intValue("--port", in: values, default: 35000))

let scenario: FakeELMScenario
do {
    scenario = try FakeELMScenario.load(from: URL(filePath: scenarioPath))
} catch {
    fail("could not load scenario: \(error)")
}

let server = FakeELMTCPServer(scenario: scenario, configuration: configuration)
let bound = try await server.start(port: port)
// Write directly to the file handle: `print` is block-buffered when stdout is
// a pipe, which would hide this line from a parent process reading it live.
FileHandle.standardOutput.write(Data("LISTENING \(bound)\n".utf8))
FileHandle.standardError.write(Data("[elmulator-tcp] scenario \(scenario.scenarioID) on 127.0.0.1:\(bound)\n".utf8))

// Serve until killed.
while true {
    try await Task.sleep(for: .seconds(3600))
}
