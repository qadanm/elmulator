import Elmulator
import Foundation
import Network

/// A localhost TCP host for the scenario engine, used in-process by
/// integration tests. The standalone CLI equivalent for manual simulator
/// sessions is Scripts/sim/fake_elm_server.py; both speak the same
/// scenario format with the same semantics.
public actor FakeELMTCPServer {
    public enum ServerError: Error, Sendable {
        case startFailed(String)
        case notRunning
    }

    private let scenario: FakeELMScenario
    private let configuration: FakeELMEngineConfiguration
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var handlerTasks: [Task<Void, Never>] = []
    private let queue = DispatchQueue(label: "obd2.fakeelm.server")

    public init(scenario: FakeELMScenario, configuration: FakeELMEngineConfiguration = .init()) {
        self.scenario = scenario
        self.configuration = configuration
    }

    /// Starts listening on 127.0.0.1. Port 0 picks an ephemeral port.
    /// Returns the bound port.
    public func start(port: UInt16 = 0) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw ServerError.startFailed(String(describing: error))
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            Task { await self.adopt(connection) }
        }

        let waiter = OneShotWaiter()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                waiter.resume(.success(()))
            case let .failed(error):
                waiter.resume(.failure(ServerError.startFailed(String(describing: error))))
            case .cancelled:
                waiter.resume(.failure(ServerError.startFailed("listener cancelled")))
            default:
                break
            }
        }
        listener.start(queue: queue)
        try await waiter.wait()

        guard let boundPort = listener.port?.rawValue else {
            throw ServerError.startFailed("no bound port")
        }
        return boundPort
    }

    public func stop() {
        for task in handlerTasks {
            task.cancel()
        }
        handlerTasks.removeAll()
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    private func adopt(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        let scenario = self.scenario
        let configuration = self.configuration
        let task = Task {
            var engine = FakeELMScenarioEngine(scenario: scenario, configuration: configuration)
            var buffer = ""
            do {
                receive: while !Task.isCancelled {
                    guard let data = try await Self.receiveChunk(connection) else {
                        break
                    }
                    buffer += String(decoding: data, as: UTF8.self)
                    while let line = Self.takeLine(from: &buffer) {
                        guard !line.isEmpty else { continue }
                        let plan = engine.plan(for: line)
                        for piece in plan.pieces {
                            if piece.delayMS > 0 {
                                try await Task.sleep(for: .milliseconds(piece.delayMS))
                            }
                            try await Self.send(Data(piece.bytes), over: connection)
                        }
                        switch plan.postAction {
                        case .none, .stall:
                            // A stall plan simply produced no pieces; the
                            // client's session owns the timeout.
                            continue
                        case .disconnect:
                            connection.cancel()
                            break receive
                        }
                    }
                }
            } catch {
                // Client went away or the connection failed; nothing to do,
                // the next test or session opens a fresh connection.
            }
            connection.cancel()
        }
        handlerTasks.append(task)
    }

    /// Extracts one command terminated by CR or LF. Partial commands stay
    /// buffered: the server never assumes one read is one command.
    static func takeLine(from buffer: inout String) -> String? {
        guard let index = buffer.firstIndex(where: { $0 == "\r" || $0 == "\n" }) else {
            return nil
        }
        let line = String(buffer[buffer.startIndex..<index])
        buffer = String(buffer[buffer.index(after: index)...])
        return line.trimmingCharacters(in: .whitespaces)
    }

    private static func receiveChunk(_ connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }

    private static func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

/// Resumes a checked continuation exactly once, from callback-style APIs
/// that may fire more than one state transition.
final class OneShotWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, any Error>?
    private var continuation: CheckedContinuation<Void, any Error>?

    func resume(_ result: Result<Void, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard self.result == nil else { return }
        self.result = result
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    /// Cancellation-safe: a cancelled waiter resumes with CancellationError
    /// instead of leaking its continuation.
    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        } onCancel: {
            resume(.failure(CancellationError()))
        }
    }
}
