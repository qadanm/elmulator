import Foundation

public extension Scenario {
    /// The ids of the built-in example scenarios (the file stem, without the
    /// `.scenario` suffix), for example `p0420_basic`.
    static var bundledNames: [String] {
        BundledScenarios.all.keys.sorted()
    }

    /// Load a built-in example scenario by name, for example
    /// `try Scenario.bundled("p0420_basic")`. The scenarios are embedded in the
    /// package, so this works with no files on disk and on any platform.
    static func bundled(_ name: String) throws -> Scenario {
        guard let json = BundledScenarios.all[name] else {
            throw LoadError.unknownBundled(name)
        }
        return try decode(from: Data(json.utf8))
    }
}
