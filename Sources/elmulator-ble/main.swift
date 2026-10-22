import Elmulator
import ElmulatorBLE
import Foundation

// Dev-only macOS tool. Hosts a scenario as a real BLE peripheral so a
// physical iPhone running the app can scan over CoreBluetooth without an
// adapter or a car. See docs/getting-started.md and
// docs/mock-elm327-over-bluetooth.md.

let usage = """
elmulator-ble: host a synthetic ELM327 over Bluetooth Low Energy (macOS).

Usage:
  elmulator-ble --scenario PATH [options]

Options:
  --scenario PATH        scenario file, e.g. scenarios/p0420_basic.scenario.json
  --name NAME            advertised local name (default: FakeELM)
  --service UUID         advertised service UUID (default: Nordic UART)
  --write-uuid UUID      command write characteristic UUID
  --notify-uuid UUID     reply notify characteristic UUID
  --chunk-size N         notification payload size in bytes, at least 1 (default: 20)
  --latency-ms N         extra latency before each reply (default: 0)
  --jitter-ms N          deterministic jitter bound, uses --seed (default: 0)
  --seed N               non-negative jitter seed (default: 0)
  --split a,b,c          cycled extra chunk sizes on top of chunk-size
  --disconnect-after N   drop the connection after N commands
  --help                 print this message

The advertised UUIDs default to a Nordic UART style profile. Adapter clones
vary, so verify against the real adapters before freezing them.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n\n\(usage)\n".utf8))
    exit(2)
}

func validUUIDString(_ value: String) -> Bool {
    if value.count == 4 || value.count == 8 {
        return value.allSatisfy(\.isHexDigit)
    }
    guard value.count == 36 else { return false }
    let groups = value.split(separator: "-", omittingEmptySubsequences: false)
    guard groups.count == 5, groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
    return value.allSatisfy { $0.isHexDigit || $0 == "-" }
}

func parseArguments(_ arguments: [String]) -> (scenarioPath: String, options: PeripheralHost.Options) {
    let knownOptions: Set<String> = [
        "--scenario", "--name", "--service", "--write-uuid", "--notify-uuid",
        "--chunk-size", "--latency-ms", "--jitter-ms", "--seed",
        "--split", "--disconnect-after",
    ]
    var values: [String: String] = [:]
    var index = 0
    let list = Array(arguments.dropFirst())
    while index < list.count {
        let token = list[index]
        guard token.hasPrefix("--") else { fail("unexpected argument: \(token)") }
        if token == "--help" { print(usage); exit(0) }
        guard knownOptions.contains(token) else { fail("unknown option: \(token)") }
        guard index + 1 < list.count else { fail("missing value for \(token)") }
        values[token] = list[index + 1]
        index += 2
    }

    guard let scenarioPath = values["--scenario"] else { fail("--scenario is required") }

    func intValue(_ key: String, default fallback: Int, range: ClosedRange<Int>? = nil) -> Int {
        guard let raw = values[key] else { return fallback }
        guard let value = Int(raw) else { fail("\(key) must be an integer") }
        if let range, !range.contains(value) {
            fail("\(key) must be between \(range.lowerBound) and \(range.upperBound)")
        }
        return value
    }

    for key in ["--service", "--write-uuid", "--notify-uuid"] {
        if let value = values[key], !validUUIDString(value) {
            fail("\(key) must be a 16-bit, 32-bit, or 128-bit UUID")
        }
    }
    if let name = values["--name"], name.isEmpty {
        fail("--name must not be empty")
    }

    let base = AdapterProfile.nordicUART
    let profile = AdapterProfile(
        serviceUUID: values["--service"] ?? base.serviceUUID,
        writeCharacteristicUUID: values["--write-uuid"] ?? base.writeCharacteristicUUID,
        notifyCharacteristicUUID: values["--notify-uuid"] ?? base.notifyCharacteristicUUID,
        writeWithResponse: base.writeWithResponse,
        advertisedName: values["--name"] ?? base.advertisedName
    )

    let splitPattern: [Int]?
    if let raw = values["--split"] {
        let parts = raw.split(separator: ",")
        guard !parts.isEmpty else { fail("--split needs at least one positive size") }
        splitPattern = parts.map { part in
            guard let size = Int(part), size > 0 else {
                fail("--split values must be positive integers, for example 1,2,5")
            }
            return size
        }
    } else {
        splitPattern = nil
    }

    let configuration = EngineConfiguration(
        splitPattern: splitPattern,
        echoOverride: nil,
        extraLatencyMS: intValue("--latency-ms", default: 0, range: 0...Int.max),
        jitterMS: intValue("--jitter-ms", default: 0, range: 0...Int.max),
        seed: UInt64(intValue("--seed", default: 0, range: 0...Int.max))
    )

    let disconnectAfter: Int?
    if values["--disconnect-after"] != nil {
        disconnectAfter = intValue("--disconnect-after", default: 1, range: 1...Int.max)
    } else {
        disconnectAfter = nil
    }

    let options = PeripheralHost.Options(
        profile: profile,
        chunkSize: intValue("--chunk-size", default: 20, range: 1...Int.max),
        configuration: configuration,
        disconnectAfter: disconnectAfter
    )
    return (scenarioPath, options)
}

let (scenarioPath, options) = parseArguments(CommandLine.arguments)

let scenario: Scenario
do {
    scenario = try Scenario.load(from: URL(filePath: scenarioPath))
} catch {
    fail("could not load scenario: \(error)")
}

let host = PeripheralHost(scenario: scenario, options: options)
host.start()
host.log("press Ctrl-C to stop")

// CoreBluetooth needs a run loop to deliver delegate callbacks.
RunLoop.main.run()
