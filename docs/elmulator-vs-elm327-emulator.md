# elmulator vs ELM327-emulator

Both are emulators for ELM327 OBD2 adapters, so you can build and test OBD2 software without a car or a physical adapter. They fit different setups. The short version: [ELM327-emulator](https://github.com/Ircama/ELM327-emulator) is a mature Python emulator for TCP and serial with a deep built-in ECU simulation and an interactive prompt. elmulator adds Bluetooth LE and a way to run an app's Bluetooth code in CI, and it is MIT licensed.

## At a glance

| | elmulator | ELM327-emulator |
|---|---|---|
| License | MIT | CC-BY-NC-SA 4.0 (no commercial use) |
| Bluetooth LE (GATT) | Yes: a real BLE peripheral on macOS, plus an in-process mock | No: its Bluetooth is an RFCOMM serial port (classic Bluetooth), which iOS apps do not use |
| TCP | Yes | Yes |
| Serial and pty | No | Yes |
| In-process test double for unit tests | Yes (Swift) | No |
| Bridge for testing real CoreBluetooth code | Yes (CoreBluetooth-Mock) | No |
| Emulator language | Swift and Python | Python |
| How you define behavior | JSON scenario files, each also a test fixture | Python dictionaries and plugins, plus an interactive prompt |
| Built-in ECU and PID simulation | basic; you script what you need | extensive, built in |
| Interactive prompt | No | Yes |
| Maturity | newer, focused on BLE and CI | older, broad, widely used |

## When to use which

Use ELM327-emulator if you connect over TCP or serial, you want its deep built-in simulation and interactive prompt, and a non-commercial license is fine for your project.

Use elmulator if you need Bluetooth LE, you are testing an iOS app, you want the Bluetooth path to run in CI with no hardware, you want scenarios kept as version-controlled fixtures, or you need a permissive license for a commercial app.

They both speak standard OBD2 over TCP, so you can use ELM327-emulator for broad TCP simulation and elmulator for the Bluetooth and CI parts in the same project.

## Questions

**Does ELM327-emulator support Bluetooth LE?**
No. It can be reached over Bluetooth, but only as an RFCOMM serial port (classic Bluetooth SPP). Consumer OBD2 apps on iOS connect over Bluetooth LE (GATT), which it does not emulate. elmulator does.

**Can I use ELM327-emulator in a commercial product?**
Its license is CC-BY-NC-SA 4.0, which does not allow commercial use. elmulator is MIT, so commercial use is fine.

**Which one is more mature?**
ELM327-emulator has been around longer and has a deeper built-in ECU simulation and an interactive prompt. elmulator is newer and focused on Bluetooth LE and testing in CI.

**Can I use both in the same project?**
Yes. Both speak standard OBD2 (SAE J1979 / ISO 15765-4) over TCP, so an app can point at either one.

Facts about ELM327-emulator were checked against its repository in 2026.
