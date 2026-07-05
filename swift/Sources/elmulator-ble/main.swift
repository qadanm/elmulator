import Elmulator
import ElmulatorBLE
import Foundation

// Dev-only macOS tool. Hosts a FakeELM scenario as a BLE peripheral so a
// physical iPhone running the app can scan over CoreBluetooth without an
// adapter or a car. See Docs/testing/FAKE_BLE_PERIPHERAL.md.

let usage = """
FakeELMBLEPeripheral: host a synthetic ELM327 over Bluetooth Low Energy.

Usage:
  FakeELMBLEPeripheral --scenario PATH [options]

Options:
  --scenario PATH        scenario file (Fixtures/sim_scenarios/*.scenario.json)
  --name NAME            advertised local name (default: FakeELM)
  --service UUID         advertised service UUID (default: Nordic UART)
  --write-uuid UUID      command write characteristic UUID
  --notify-uuid UUID     reply notify characteristic UUID
  --chunk-size N         notification payload size in bytes (default: 20)
  --latency-ms N         extra latency added to each reply (default: 0)
  --jitter-ms N          deterministic jitter bound, uses --seed (default: 0)
  --seed N               jitter seed (default: 0)
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

func parseArguments(_ arguments: [String]) -> (scenarioPath: String, options: PeripheralHost.Options) {
    var values: [String: String] = [:]
    var index = 0
    let flags = arguments.dropFirst()
    let list = Array(flags)
    while index < list.count {
        let token = list[index]
        guard token.hasPrefix("--") else { fail("unexpected argument: \(token)") }
        if token == "--help" { print(usage); exit(0) }
        guard index + 1 < list.count else { fail("missing value for \(token)") }
        values[token] = list[index + 1]
        index += 2
    }

    guard let scenarioPath = values["--scenario"] else { fail("--scenario is required") }

    let base = BLEAdapterProfile.nordicUART
    let profile = BLEAdapterProfile(
        serviceUUID: values["--service"] ?? base.serviceUUID,
        writeCharacteristicUUID: values["--write-uuid"] ?? base.writeCharacteristicUUID,
        notifyCharacteristicUUID: values["--notify-uuid"] ?? base.notifyCharacteristicUUID,
        writeWithResponse: base.writeWithResponse,
        advertisedName: values["--name"] ?? base.advertisedName
    )

    func intValue(_ key: String, default fallback: Int) -> Int {
        guard let raw = values[key] else { return fallback }
        guard let value = Int(raw) else { fail("\(key) must be an integer") }
        return value
    }

    let splitPattern = values["--split"].map { text in
        text.split(separator: ",").compactMap { Int($0) }
    }

    let configuration = FakeELMEngineConfiguration(
        splitPattern: splitPattern,
        echoOverride: nil,
        extraLatencyMS: intValue("--latency-ms", default: 0),
        jitterMS: intValue("--jitter-ms", default: 0),
        seed: UInt64(intValue("--seed", default: 0))
    )

    let options = PeripheralHost.Options(
        profile: profile,
        chunkSize: intValue("--chunk-size", default: 20),
        configuration: configuration,
        disconnectAfter: values["--disconnect-after"].flatMap(Int.init)
    )
    return (scenarioPath, options)
}

let (scenarioPath, options) = parseArguments(CommandLine.arguments)

let scenario: FakeELMScenario
do {
    scenario = try FakeELMScenario.load(from: URL(filePath: scenarioPath))
} catch {
    fail("could not load scenario: \(error)")
}

let host = PeripheralHost(scenario: scenario, options: options)
host.start()
host.log("press Ctrl-C to stop")

// CoreBluetooth needs a run loop to deliver delegate callbacks.
RunLoop.main.run()
