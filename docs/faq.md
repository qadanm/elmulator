# FAQ

**Can the iOS Simulator use Bluetooth?**
No. The iOS Simulator has no Bluetooth support, so an app cannot scan for or connect to anything there. To test Bluetooth code you use a physical device or mock CoreBluetooth. elmulator with CoreBluetooth-Mock lets your real Bluetooth code run against a scripted adapter with no radio.

**How do I test an OBD2 app without a car?**
Point the app at a fake adapter instead of a real one. elmulator can act as that adapter over Bluetooth LE, over TCP, or as an in-process fake inside your tests, and it replies from a scenario you write. See [Getting started](getting-started.md).

**Is there a free ELM327 emulator that does Bluetooth LE?**
elmulator is one. It is MIT licensed and can advertise a real ELM327-style BLE peripheral on macOS, act as an in-process BLE fake in Swift tests, or bridge to CoreBluetooth-Mock. The older ELM327-emulator is TCP and serial only. See the [comparison](elmulator-vs-elm327-emulator.md).

**Can I test CoreBluetooth code without a device?**
Yes, with [CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock). elmulator turns a scenario into a mock peripheral for it, so your real `CBCentralManager` code runs under `swift test`. See [Test an iOS OBD2 app in CI](testing-obd2-apps-in-ci.md).

**Does elmulator work with Android or other languages?**
The TCP server and the scenario format do. Run `elmulator serve` and point any app at the socket. The in-process fake and the real BLE peripheral are Swift and macOS for now. See the [roadmap](roadmap.md).

**What OBD2 standards does it cover?**
Standard OBD2 over CAN: SAE J1979 and ISO 15765-4.

**What license is it under?**
MIT.

**Can I record a real adapter into a scenario?**
Not yet. Scenarios are written by hand today. It is on the [roadmap](roadmap.md).
