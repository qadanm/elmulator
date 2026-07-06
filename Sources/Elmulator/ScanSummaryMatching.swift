import Foundation

public extension Scenario.ExpectedScanSummary {
    /// A scan result as decoded by the consuming app. elmulator emits bytes
    /// only and never decodes OBD2, so you fill this in from your own parser
    /// and diff it against the scenario's declared expectations with
    /// `mismatches(observed:)`.
    struct Observed: Sendable, Equatable {
        public var storedCodes: [String]?
        public var pendingCodes: [String]?
        public var permanentCodes: [String]?
        public var milReportedOn: Bool?
        public var vinReported: Bool?
        public var liveValueCount: Int?
        public var sessionWarnings: Int?
        public var noStoredCodesObservation: Bool?
        public var scanError: String?

        public init(
            storedCodes: [String]? = nil,
            pendingCodes: [String]? = nil,
            permanentCodes: [String]? = nil,
            milReportedOn: Bool? = nil,
            vinReported: Bool? = nil,
            liveValueCount: Int? = nil,
            sessionWarnings: Int? = nil,
            noStoredCodesObservation: Bool? = nil,
            scanError: String? = nil
        ) {
            self.storedCodes = storedCodes
            self.pendingCodes = pendingCodes
            self.permanentCodes = permanentCodes
            self.milReportedOn = milReportedOn
            self.vinReported = vinReported
            self.liveValueCount = liveValueCount
            self.sessionWarnings = sessionWarnings
            self.noStoredCodesObservation = noStoredCodesObservation
            self.scanError = scanError
        }
    }

    /// One field where a decoded scan disagreed with the expectation. `field`
    /// is the JSON key (for example `stored_codes`) so you can correlate it
    /// with the scenario file.
    struct FieldMismatch: Equatable, Sendable {
        public let field: String
        public let expected: String
        public let observed: String
    }

    /// Diff a decoded scan against this expectation. Only fields that are set
    /// (non-nil) in the expectation are checked; a nil field means "don't
    /// care". `min_session_warnings` is treated as a lower bound.
    func mismatches(observed: Observed) -> [FieldMismatch] {
        var result: [FieldMismatch] = []

        func check<T: Equatable>(_ key: String, _ expected: T?, _ observed: T?) {
            guard let expected else { return }
            if observed != expected {
                result.append(FieldMismatch(
                    field: key,
                    expected: "\(expected)",
                    observed: observed.map { "\($0)" } ?? "nil"
                ))
            }
        }

        check("stored_codes", storedCodes, observed.storedCodes)
        check("pending_codes", pendingCodes, observed.pendingCodes)
        check("permanent_codes", permanentCodes, observed.permanentCodes)
        check("mil_reported_on", milReportedOn, observed.milReportedOn)
        check("vin_reported", vinReported, observed.vinReported)
        check("live_value_count", liveValueCount, observed.liveValueCount)
        check("no_stored_codes_observation", noStoredCodesObservation, observed.noStoredCodesObservation)
        check("scan_error", scanError, observed.scanError)

        if let minWarnings = minSessionWarnings {
            let seen = observed.sessionWarnings ?? 0
            if seen < minWarnings {
                result.append(FieldMismatch(
                    field: "min_session_warnings",
                    expected: ">=\(minWarnings)",
                    observed: "\(seen)"
                ))
            }
        }

        return result
    }
}
