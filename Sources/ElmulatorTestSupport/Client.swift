import Foundation
import Network

/// A tiny TCP client for a running elmulator TCP server (the in-process
/// `TCPServer`, or the `elmulator serve` / `elmulator-tcp` CLI). It connects,
/// sends commands, and reassembles each reply up to the ELM `>` prompt, so a
/// test is a few lines instead of a hand-rolled socket loop.
///
/// ```swift
/// let server = TCPServer(scenario: try .bundled("p0420_basic"))
/// let port = try await server.start()
/// let client = Client(port: port)
/// try await client.connect()
/// #expect(try await client.send("03").contains("43 01 04 20"))
/// await client.close()
/// ```
public actor Client {
    public enum ClientError: Error, Sendable, Equatable {
        case notConnected
        /// No prompt arrived within the timeout (for example a stall).
        case timedOut(command: String)
        /// The peer closed before sending a prompt (for example a disconnect).
        case disconnected(command: String)
    }

    private enum Received {
        case bytes([UInt8])
        case closed
    }

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private var buffer = ""

    public init(host: String = "127.0.0.1", port: UInt16) {
        self.host = host
        self.port = port
    }

    public func connect() async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any,
            using: .tcp
        )
        self.connection = connection
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case let .failed(error): cont.resume(throwing: error)
                case .cancelled: cont.resume(throwing: ClientError.notConnected)
                default: break
                }
            }
            connection.start(queue: .global())
        }
        connection.stateUpdateHandler = nil
    }

    public func close() {
        connection?.cancel()
        connection = nil
    }

    /// Send a command (a `\r` is appended) and return the reply up to and
    /// including the ELM prompt `>`. Throws `timedOut` on a stall and
    /// `disconnected` if the peer closes before a prompt.
    public func send(_ command: String, timeout: Duration = .seconds(5)) async throws -> String {
        guard let connection else { throw ClientError.notConnected }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data((command + "\r").utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }

        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !buffer.contains(">") {
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero { throw ClientError.timedOut(command: command) }
            switch try await receiveOne(over: connection, within: remaining, command: command) {
            case let .bytes(bytes):
                buffer += String(decoding: bytes, as: UTF8.self)
            case .closed:
                throw ClientError.disconnected(command: command)
            }
        }

        let promptIndex = buffer.firstIndex(of: ">")!
        let reply = String(buffer[buffer.startIndex...promptIndex])
        buffer = String(buffer[buffer.index(after: promptIndex)...])
        return reply
    }

    private func receiveOne(over connection: NWConnection, within remaining: Duration, command: String) async throws -> Received {
        try await withThrowingTaskGroup(of: Received.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Received, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                        if let error { cont.resume(throwing: error); return }
                        if let data, !data.isEmpty { cont.resume(returning: .bytes([UInt8](data))); return }
                        if isComplete { cont.resume(returning: .closed); return }
                        cont.resume(returning: .bytes([]))
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: remaining)
                throw ClientError.timedOut(command: command)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }
}
