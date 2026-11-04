# OBD-II Reader for macOS

Native SwiftUI app that talks to an ELM327-compatible OBD-II USB adapter.
Features: live sensor data (Mode 01), trouble codes read/clear (Modes 03/07/0A/04),
CSV logging, vehicle info (VIN and calibration IDs, Mode 09), raw command console,
and a built-in adapter/vehicle simulator for development without hardware.

## Layout

- `OBDKit/` — Swift package with everything that is not UI. Builds and tests from the CLI.
  - `Transport/` — `OBDTransport` protocol, POSIX `SerialPortTransport`, port discovery, baud detection.
  - `ELM/` — `ELM327Session` actor (command serialization, response parsing).
  - `OBD/` — `OBDClient` actor (typed API + poll loop), PID registry, DTC decoder, Mode 09 parsers.
  - `Simulator/` — `ELM327Emulator` state machine and `SimulatedVehicle`.
  - `Logging/CSVLogger.swift`
  - `Sources/obdcli` — command-line probe tool.
- `App/` — SwiftUI app sources. The Xcode project is generated from `project.yml`.

## Build

```sh
# Xcode's toolchain (the Command Line Tools toolchain is flaky with swift-testing macros)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Core package
cd OBDKit && swift test && cd ..

# App
brew install xcodegen          # once
xcodegen generate
xcodebuild -project OBDII.xcodeproj -scheme OBDII -configuration Debug build
# or: open OBDII.xcodeproj and press Run
```

Developer launch flags: `OBDII --autoconnect [--simulate] [--poll] [--smoke <seconds>]`.
`--smoke` connects, polls, reads/clears codes, reads the VIN, prints the state and exits 0 on success:

```sh
.build/DerivedData/Build/Products/Debug/OBDII.app/Contents/MacOS/OBDII --autoconnect --simulate --poll --smoke 3
```

## CLI

```sh
cd OBDKit
swift run obdcli ports                                  # list /dev/cu.* ports
swift run obdcli sim --seconds 5                        # full probe against the simulator
swift run obdcli probe --port /dev/cu.usbserial-XXXX --baud auto --poll 20   # add live polling
```

## First run with real hardware

1. Plug in the adapter. `ls -l /dev/cu.*` should show a new `usbserial-*` (FTDI) or similar device.
   If nothing appears: `system_profiler SPUSBDataType` and look for the vendor ID
   (FTDI 0403, CH340 1A86, CP210x 10C4 are supported by macOS; PL2303 067B needs the Prolific driver).
2. Manual check: `screen /dev/cu.usbserial-XXXX 38400`, type `ATZ` and Enter. Expect `ELM327 v1.x` and `>`.
   No reply: `Ctrl-A K` to quit, retry at 9600 and 115200. Then `ATRV` (battery voltage, needs the car),
   `ATSP0`, `0100` (expect `SEARCHING...` then `41 00 ...`, ignition on).
3. `swift run obdcli probe --port /dev/cu.usbserial-XXXX --baud auto` should reproduce the manual results.
4. In the app: turn off Simulator, pick the port, Baud = Auto (or the rate found), Connect.
5. If the adapter never answers `ATZ` at any baud, the cable is not an ELM327 device.
6. Some adapters ship with a non-standard rate. The OBDLink SX used here answers only at
   1,000,000 baud, so that rate is in the Baud menu and in auto detection. macOS termios
   rejects non-standard rates; `SerialPortTransport` sets them with the `IOSSIOSPEED` ioctl.
   Any genuine ELM327 v1.4b/2.x or an OBDLink SX will work with this app unchanged.

## Notes

- App Sandbox is off so the app can open `/dev/cu.*`. Hardened Runtime is on; the build is ad-hoc signed.
- Spaces are left on in adapter output (no `ATS0`) so the console stays readable; the parser accepts both.
- Serial I/O is pure POSIX (termios + poll) on a private dispatch queue; `close()` wakes a pending read via a self-pipe.

## License

Copyright 2026 BD Himes.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.
