import Elmulator
import Foundation

/// Drives a scenario in-process, with no sockets. The fastest way to check
/// what a scripted adapter would reply: build one, `send` commands, read the
/// strings back. It wraps a `ScenarioEngine` and joins each reply the way a
/// client reading up to the prompt would.
///
/// ```swift
/// var adapter = try Conversation(bundled: "p0420_basic")
/// _ = adapter.send("ATZ")
/// #expect(adapter.send("03").contains("43 01 04 20"))
/// ```
public struct Conversation {
    private var engine: ScenarioEngine

    public init(scenario: Scenario, configuration: EngineConfiguration = .init()) {
        var config = configuration
        config.recordTranscript = true
        self.engine = ScenarioEngine(scenario: scenario, configuration: config)
    }

    /// Build a `Conversation` for a bundled example scenario by name.
    public init(bundled name: String, configuration: EngineConfiguration = .init()) throws {
        self.init(scenario: try Scenario.bundled(name), configuration: configuration)
    }

    /// Send a command and get the reply as one string: the joined reply bytes,
    /// what the wire would carry up to and including the prompt.
    public mutating func send(_ command: String) -> String {
        engine.plan(for: command).joinedASCII
    }

    /// The full conversation so far, for a byte-level log when a test fails.
    public var transcript: [TranscriptEntry] { engine.transcript }
}
