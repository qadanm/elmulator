import Foundation

/// A typed BLE transport failure the connection state machine can raise.
///
/// This is intentionally tiny and self-contained: the emulator side owns its
/// own error vocabulary so nothing here depends on a host app's transport
/// types. A consuming app maps these onto its own error model at the seam
/// (for example in its `BLETransportClient`).
public enum BLETransportError: Error, Equatable, Sendable {
    /// The connection never reached the ready state (power, auth, discovery,
    /// subscribe, or connect-deadline failures).
    case connectFailed(String)
    /// A connection that had reached ready was lost.
    case connectionLost(String)
}
