// The BLE types dropped their `BLE` prefix in 0.3.0 (the module already
// namespaces them as `ElmulatorBLE.*`), so they no longer collide with a
// consuming app's own BLE layer. These aliases keep 0.2 code compiling; they
// will be removed in a later release.

@available(*, deprecated, renamed: "CentralStack")
public typealias BLEStack = CentralStack

@available(*, deprecated, renamed: "CentralEvent")
public typealias BLEStackEvent = CentralEvent

@available(*, deprecated, renamed: "DiscoveredPeripheral")
public typealias BLEDiscoveredPeripheral = DiscoveredPeripheral

@available(*, deprecated, renamed: "ConnectionEvent")
public typealias BLEConnectionEvent = ConnectionEvent

@available(*, deprecated, renamed: "ConnectionAction")
public typealias BLEConnectionAction = ConnectionAction

@available(*, deprecated, renamed: "ConnectionStateMachine")
public typealias BLEConnectionStateMachine = ConnectionStateMachine

@available(*, deprecated, renamed: "AdapterProfile")
public typealias BLEAdapterProfile = AdapterProfile

@available(*, deprecated, renamed: "ConnectionError")
public typealias BLETransportError = ConnectionError
