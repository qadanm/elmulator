import Foundation

/// Behavior knobs applied on top of a scenario. The same configuration
/// semantics exist in Scripts/sim/fake_elm_server.py so the Swift and
/// Python hosts stay interchangeable.
public struct FakeELMEngineConfiguration: Sendable {
    /// Cycled piece sizes applied after scenario-level splitting, for
    /// example [1, 2, 5]. Nil means no extra splitting.
    public var splitPattern: [Int]?
    /// Forces echo on or off for every command, overriding the scenario.
    public var echoOverride: Bool?
    /// Flat extra latency added to the first piece of every reply.
    public var extraLatencyMS: Int
    /// Deterministic jitter bound (0 disables). Uses `seed`.
    public var jitterMS: Int
    public var seed: UInt64

    public init(
        splitPattern: [Int]? = nil,
        echoOverride: Bool? = nil,
        extraLatencyMS: Int = 0,
        jitterMS: Int = 0,
        seed: UInt64 = 0
    ) {
        self.splitPattern = splitPattern
        self.echoOverride = echoOverride
        self.extraLatencyMS = extraLatencyMS
        self.jitterMS = jitterMS
        self.seed = seed
    }
}

/// One planned reply: byte pieces with delays, then an action.
public struct FakeELMResponsePlan: Sendable {
    public struct Piece: Sendable, Equatable {
        public let bytes: [UInt8]
        public let delayMS: Int
    }

    public let pieces: [Piece]
    public let postAction: FakeELMScenario.PostAction
    /// Nil when no scenario entry matched and a default reply was used.
    public let matchedRequest: String?

    public var joinedASCII: String {
        String(decoding: pieces.flatMap(\.bytes), as: UTF8.self)
    }
}

/// The scenario engine: pure request-to-reply planning with no I/O.
/// Hosts (the in-process TCP server, the Python CLI server via the same
/// semantics, and the future BLE peripheral tool) own transport concerns.
public struct FakeELMScenarioEngine: Sendable {
    private let scenario: FakeELMScenario
    private let configuration: FakeELMEngineConfiguration
    /// Consumption cursor per normalized request.
    private var cursors: [String: Int] = [:]
    private var random: SplitMix64

    public init(scenario: FakeELMScenario, configuration: FakeELMEngineConfiguration = .init()) {
        self.scenario = scenario
        self.configuration = configuration
        self.random = SplitMix64(seed: configuration.seed)
    }

    /// ELM adapters are case-insensitive and ignore spaces in commands.
    public static func normalize(_ rawCommand: String) -> String {
        rawCommand
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "\r" && $0 != "\n" }
    }

    public mutating func plan(for rawCommand: String) -> FakeELMResponsePlan {
        let normalized = Self.normalize(rawCommand)
        let entries = scenario.commands.enumerated().filter {
            Self.normalize($0.element.request) == normalized
        }

        guard !entries.isEmpty else {
            return defaultPlan(for: normalized, rawCommand: rawCommand)
        }

        // Entries for one request are consumed in order. The cursor caps at
        // the last entry, so the last entry repeats and re-polling never
        // goes silent. An entry with repeat true pins the cursor and keeps
        // answering every later match.
        let cursor = cursors[normalized] ?? 0
        let position = min(cursor, entries.count - 1)
        let command = entries[position].element
        if !command.repeats {
            cursors[normalized] = min(position + 1, entries.count - 1)
        }

        return buildPlan(command: command, rawCommand: rawCommand)
    }

    private func echoEnabled(for command: FakeELMScenario.Command?) -> Bool {
        if let forced = configuration.echoOverride { return forced }
        return command?.echo ?? false
    }

    private mutating func buildPlan(
        command: FakeELMScenario.Command,
        rawCommand: String
    ) -> FakeELMResponsePlan {
        var text = ""
        if echoEnabled(for: command) {
            text += Self.normalize(rawCommand) + "\r"
        }
        text += command.responseChunks.joined()

        // Author-defined chunk boundaries are preserved by splitting on the
        // same offsets, then scenario and configuration splitting refine.
        var pieces = split(
            text: text,
            authoredBoundaries: command.echo || configuration.echoOverride == true
                ? [Self.normalize(rawCommand).count + 1] + boundaries(of: command.responseChunks, offset: Self.normalize(rawCommand).count + 1)
                : boundaries(of: command.responseChunks, offset: 0)
        )
        pieces = applyChunking(pieces)

        var planned: [FakeELMResponsePlan.Piece] = []
        for (index, piece) in pieces.enumerated() {
            var delay = index == 0 ? command.delayMS + configuration.extraLatencyMS : 0
            if index == 0, configuration.jitterMS > 0 {
                delay += Int(random.next() % UInt64(configuration.jitterMS + 1))
            }
            planned.append(.init(bytes: Array(piece.utf8), delayMS: delay))
        }
        return FakeELMResponsePlan(
            pieces: planned,
            postAction: command.postAction,
            matchedRequest: command.request
        )
    }

    private mutating func defaultPlan(for normalized: String, rawCommand: String) -> FakeELMResponsePlan {
        let body = normalized.hasPrefix("AT")
            ? scenario.defaults.atResponse
            : scenario.defaults.obdResponse
        var text = ""
        if configuration.echoOverride == true {
            text += normalized + "\r"
        }
        text += body
        let pieces = applyChunking([text]).map {
            FakeELMResponsePlan.Piece(bytes: Array($0.utf8), delayMS: configuration.extraLatencyMS)
        }
        return FakeELMResponsePlan(pieces: pieces, postAction: .none, matchedRequest: nil)
    }

    // MARK: - Splitting

    private func boundaries(of chunks: [String], offset: Int) -> [Int] {
        var positions: [Int] = []
        var position = offset
        for chunk in chunks.dropLast() {
            position += chunk.count
            positions.append(position)
        }
        return positions
    }

    private func split(text: String, authoredBoundaries: [Int]) -> [String] {
        guard !text.isEmpty else { return [] }
        let characters = Array(text)
        var pieces: [String] = []
        var start = 0
        for boundary in (authoredBoundaries + [characters.count]).sorted() where boundary > start && boundary <= characters.count {
            pieces.append(String(characters[start..<boundary]))
            start = boundary
        }
        if start < characters.count {
            pieces.append(String(characters[start...]))
        }
        return pieces
    }

    private func applyChunking(_ pieces: [String]) -> [String] {
        var result = pieces
        if let maxBytes = scenario.streamSplitBytes {
            result = result.flatMap { slice($0, sizes: [maxBytes]) }
        }
        if let pattern = configuration.splitPattern, !pattern.isEmpty {
            result = result.flatMap { slice($0, sizes: pattern) }
        }
        return result.filter { !$0.isEmpty }
    }

    private func slice(_ text: String, sizes: [Int]) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var index = 0
        var sizeIndex = 0
        while index < characters.count {
            let size = max(1, sizes[sizeIndex % sizes.count])
            let end = min(index + size, characters.count)
            pieces.append(String(characters[index..<end]))
            index = end
            sizeIndex += 1
        }
        return pieces
    }
}

/// Small deterministic PRNG (SplitMix64) so jitter is reproducible from a
/// seed. Clean-room implementation of the public algorithm.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
