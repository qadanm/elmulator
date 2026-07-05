import Foundation

/// A repo-owned simulator scenario (schema obd2.sim_scenario.v1).
///
/// Scenarios are hand-authored synthetic fixtures under
/// Fixtures/sim_scenarios and are validated by Scripts/sim/validate_scenarios.py.
/// No scenario content is copied from third-party simulators; the byte
/// patterns mirror this repo's own replay traces.
public struct FakeELMScenario: Codable, Sendable {
    public struct Defaults: Codable, Sendable {
        public let atResponse: String
        public let obdResponse: String

        enum CodingKeys: String, CodingKey {
            case atResponse = "at_response"
            case obdResponse = "obd_response"
        }
    }

    public enum PostAction: String, Codable, Sendable {
        case none
        /// Send nothing so the session times out and retries.
        case stall
        /// Close the connection after any chunks were sent.
        case disconnect
    }

    public struct Command: Codable, Sendable {
        public let request: String
        public let responseChunks: [String]
        public let delayMS: Int
        public let echo: Bool
        public let prompt: Bool
        public let postAction: PostAction
        /// When true, this entry answers again once its queue position is
        /// consumed. The last matching entry also repeats by default so
        /// repeated polling (live data later) keeps working.
        public let repeats: Bool

        enum CodingKeys: String, CodingKey {
            case request
            case responseChunks = "response_chunks"
            case delayMS = "delay_ms"
            case echo
            case prompt
            case postAction = "post_action"
            case repeats = "repeat"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.request = try container.decode(String.self, forKey: .request)
            self.responseChunks = try container.decode([String].self, forKey: .responseChunks)
            self.delayMS = try container.decodeIfPresent(Int.self, forKey: .delayMS) ?? 0
            self.echo = try container.decodeIfPresent(Bool.self, forKey: .echo) ?? false
            self.prompt = try container.decodeIfPresent(Bool.self, forKey: .prompt) ?? true
            self.postAction = try container.decodeIfPresent(PostAction.self, forKey: .postAction) ?? .none
            self.repeats = try container.decodeIfPresent(Bool.self, forKey: .repeats) ?? false
        }
    }

    /// Expected full-scan outcome, asserted by integration tests so every
    /// scenario is a self-describing oracle.
    public struct ExpectedScanSummary: Codable, Sendable {
        public let storedCodes: [String]?
        public let pendingCodes: [String]?
        public let permanentCodes: [String]?
        public let milReportedOn: Bool?
        public let vinReported: Bool?
        public let liveValueCount: Int?
        public let minSessionWarnings: Int?
        public let noStoredCodesObservation: Bool?
        public let scanError: String?

        enum CodingKeys: String, CodingKey {
            case storedCodes = "stored_codes"
            case pendingCodes = "pending_codes"
            case permanentCodes = "permanent_codes"
            case milReportedOn = "mil_reported_on"
            case vinReported = "vin_reported"
            case liveValueCount = "live_value_count"
            case minSessionWarnings = "min_session_warnings"
            case noStoredCodesObservation = "no_stored_codes_observation"
            case scanError = "scan_error"
        }
    }

    public let schemaVersion: String
    public let scenarioID: String
    public let synthetic: Bool
    public let description: String
    public let adapterProfile: String
    public let defaults: Defaults
    public let streamSplitBytes: Int?
    public let warnings: [String]
    public let commands: [Command]
    public let expectedScanSummary: ExpectedScanSummary

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case scenarioID = "scenario_id"
        case synthetic
        case description
        case adapterProfile = "adapter_profile"
        case defaults
        case streamSplitBytes = "stream_split_bytes"
        case warnings
        case commands
        case expectedScanSummary = "expected_scan_summary"
    }

    public enum LoadError: Error, Equatable, Sendable {
        case unsupportedSchema(String)
        case notSynthetic(String)
    }

    public static func load(from url: URL) throws -> FakeELMScenario {
        let scenario = try JSONDecoder().decode(FakeELMScenario.self, from: try Data(contentsOf: url))
        guard scenario.schemaVersion == "obd2.sim_scenario.v1" else {
            throw LoadError.unsupportedSchema(scenario.schemaVersion)
        }
        guard scenario.synthetic else {
            // The engine refuses non-synthetic scenarios outright: simulated
            // bytes must never masquerade as real vehicle data.
            throw LoadError.notSynthetic(scenario.scenarioID)
        }
        return scenario
    }
}
