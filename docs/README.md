# Documentation

- [Getting started](getting-started.md): the three ways to point an app at a fake adapter (TCP, in-process, and a real BLE peripheral).
- [Test an iOS OBD2 app in CI](testing-obd2-apps-in-ci.md): run your real CoreBluetooth code against a scripted ELM327 under `swift test`, with no radio.
- [Mock an ELM327 over Bluetooth](mock-elm327-over-bluetooth.md): the in-process fake, the CoreBluetooth-Mock bridge, and the real BLE peripheral.
- [elmulator vs ELM327-emulator](elmulator-vs-elm327-emulator.md): what each one is for.
- [Using elmulator with SwiftOBD2](testing-swiftobd2.md): the Wi-Fi path that works today, and two upstream changes for BLE.
- [FAQ](faq.md): short answers to common questions.
- [Roadmap](roadmap.md): what is planned and what is out of scope.
- [The Swift package](swift-package.md): products, imports, and executables.

For the scenario format, see [SPEC.md](../SPEC.md) and the JSON Schema in [spec/](../spec/).
