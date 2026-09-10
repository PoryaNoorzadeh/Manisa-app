# Manisa

Manisa is a local-first smart-home platform built around Matter. The long-term product architecture keeps Manisa in control of the API, product model, device identity, UX, and automation model while using replaceable open-source protocol engines behind adapters.

The repository currently contains both the Hub-oriented Manisa platform and an Android Direct Matter hardware-validation path that can commission and control Matter-over-Wi-Fi devices without a Hub.

## Platform principles

- Local-first operation: basic device control must keep working without Internet access.
- Manisa owns the public API, device model, capability model, scenes, automations, and identities.
- Matter is the primary device interoperability layer.
- Matter Node IDs and Home Assistant entity IDs are external bindings, never canonical Manisa IDs.
- Open-source engines remain replaceable behind Manisa-owned interfaces.
- Cloud services are optional and must not sit in the critical path for local control.
- The mobile app does not depend directly on Home Assistant or raw Matter cluster schemas.

## Current architecture

### Hub mode

```text
Manisa Flutter App
        │
        │ local REST + WebSocket
        ▼
   Manisa Core (Go)
        │
        ├── SQLite
        │
        ├── MatterController adapter
        │        │
        │        ▼
        │   Matter Server
        │        │
        │        ├── Matter over Wi-Fi
        │        └── Matter over Thread
        │
        └── Home Assistant adapter (planned integration boundary)
```

Manisa Core is a modular monolith. Home Assistant, Matter Server, OTBR, and future cloud services are infrastructure dependencies behind adapters rather than product-facing APIs.

### Direct Matter Android mode

For early hardware validation, the repository also builds an Android Matter controller that does not require Manisa Hub or Manisa Core:

```text
Android Phone
      │
      │ BLE commissioning
      ▼
Matter Device
      │
      │ Matter over Wi-Fi
      ▼
Android Phone
      │
      ├── On
      ├── Off
      └── other supported Matter cluster commands
```

The Direct Matter APK is based on the official `project-chip/connectedhomeip` Android CHIPTool controller, currently pinned to `v1.5.1.0`, and is intended for development and physical-device validation while the native Matter controller is integrated into the final Manisa mobile experience.

## Technology stack

- **Manisa Core:** Go 1.27 modular monolith
- **Mobile App:** Flutter 3.47.2 / Dart
- **Hub database:** SQLite with WAL and foreign keys
- **Matter integration:** Matter Server behind a Manisa `MatterController` interface
- **Direct Android Matter validation:** ConnectedHomeIP / CHIPTool
- **Automation & integrations:** Home Assistant behind a future Manisa adapter
- **Thread:** OpenThread Border Router (OTBR), planned for Hub hardware
- **Hub deployment:** Linux ARM64 + containers
- **Cloud:** deferred; PostgreSQL planned when cloud services are introduced

## Repository layout

```text
.
├── apps/
│   └── mobile/                  # Flutter Manisa app
├── cmd/
│   └── manisa-core/             # Go service entry point
├── internal/
│   ├── application/             # application/use-case layer
│   ├── auth/                    # local client authentication
│   ├── capability/              # Manisa capability/product model
│   ├── discovery/               # Hub mDNS advertisement
│   ├── domain/                  # canonical Manisa models/interfaces
│   ├── events/                  # realtime event bus
│   ├── httpapi/                 # REST/WebSocket API
│   ├── matter/                  # Matter abstraction + adapter
│   ├── platform/                # platform utilities
│   └── storage/sqlite/          # SQLite implementation
├── docs/architecture/           # architecture decisions and milestones
├── compose.yaml
├── Dockerfile
└── .github/workflows/ci.yml
```

## Implemented backend capabilities

Manisa Core currently includes:

- liveness and readiness endpoints
- Home persistence and API
- Room persistence and API
- Device persistence and API
- stable Manisa device IDs independent of Matter Node IDs
- Matter commissioning boundary
- Matter command execution boundary
- Matter event listener and reconnect loop
- canonical device state storage
- realtime `device.state_changed` events over WebSocket
- mDNS Hub advertisement
- local Hub pairing and Bearer-token authentication
- SHA-256 token storage on the Hub
- product/capability descriptors for common smart-home devices

### Current device profiles

Initial product profiles include:

- `switch_1gang`
- `switch_2gang`
- `switch_3gang`
- `dimmer_1gang`
- `socket`
- `climate_sensor`
- `motion_sensor`
- `contact_sensor`

The mobile app consumes descriptors rather than raw Matter endpoints/clusters so UI behavior can be generated from Manisa capabilities.

## API snapshot

The current versioned API boundary is `/api/v1`.

```text
GET  /health/live
GET  /health/ready

POST /api/v1/pair

GET  /api/v1/homes
POST /api/v1/homes

GET  /api/v1/rooms?homeId=...
POST /api/v1/rooms

GET  /api/v1/devices?homeId=...
POST /api/v1/devices
GET  /api/v1/devices/{deviceId}/descriptor
GET  /api/v1/devices/{deviceId}/state
POST /api/v1/devices/{deviceId}/commands

GET  /api/v1/device-types
POST /api/v1/matter/commission
WS   /api/v1/events
```

Except for health and bootstrap pairing, local API access is authenticated.

## Realtime state model

Raw Matter attributes are normalized before they reach the application. Examples include:

```text
Matter OnOff                  -> Manisa on_off
Matter LevelControl           -> Manisa level (0-100)
Matter TemperatureMeasurement -> Manisa temperature (°C)
Matter HumidityMeasurement    -> Manisa humidity
Matter OccupancySensing       -> Manisa motion
Matter BooleanState           -> Manisa contact
```

A state update flows through:

```text
Matter device
   ↓
Matter Server
   ↓
Matter listener
   ↓
Manisa capability mapper
   ↓
SQLite state store
   ↓
device.state_changed event
   ↓
Flutter WebSocket client
```

## Mobile app status

The Flutter application currently has the foundations for:

- automatic Hub discovery with mDNS
- secure local Hub pairing
- secure token storage on the phone
- Home creation
- Home/Room/Device loading
- descriptor-driven device UI
- current device-state loading
- realtime WebSocket updates
- On/Off command execution
- dimmer level control
- Matter QR scanning
- Add Device onboarding for Matter devices

The Hub-mode Flutter app and the Direct Matter Android controller are currently separate development paths. Direct Matter hardware validation is being used to prove commissioning and command behavior on real devices before folding native Matter-controller functionality into the final Manisa Flutter application.

## Direct Matter hardware test

This is currently the fastest path for testing a Matter-over-Wi-Fi touch switch without a Hub.

Prerequisites:

- Android ARM64 phone
- Bluetooth enabled
- Wi-Fi enabled
- Matter-over-Wi-Fi device with a valid Matter QR/setup code
- device factory-reset and placed in commissioning mode

Typical flow:

```text
1. Install the Manisa Direct Matter debug APK.
2. Factory-reset the Matter device.
3. Put the device in Matter commissioning mode.
4. Start commissioning from the Android controller.
5. Scan or enter the Matter setup payload.
6. Provision the device onto Wi-Fi.
7. Discover the On/Off endpoint(s).
8. Send On/Off commands and validate physical relay/touch-state behavior.
```

For multi-gang switches, each gang may be represented by a separate Matter endpoint. Endpoint layout must be validated against the actual device implementation rather than assumed from the number of physical buttons.

## CI

GitHub Actions currently validates/builds multiple paths:

```text
Go
 ├── go mod tidy
 ├── gofmt
 ├── go vet
 ├── race tests
 └── build

Flutter
 ├── pub get
 ├── dart format
 ├── flutter analyze
 └── flutter test

Android
 ├── Flutter debug APK
 └── Direct Matter Android APK
```

The Direct Matter workflow builds the controller from the pinned Matter SDK and uploads `manisa-direct-matter-apk` as a GitHub Actions artifact.

## Local Hub configuration

Manisa Core requires a local pairing code and should never be deployed with an unauthenticated LAN API.

Example development environment:

```bash
export MANISA_PAIRING_CODE='replace-with-a-real-provisioning-code'
export MANISA_HTTP_ADDR=':8080'
export MANISA_DB_PATH='./data/manisa.db'
```

Do not commit real production pairing codes, Wi-Fi credentials, device setup codes, access tokens, fabric credentials, or private keys to the repository.

## Milestones

| Milestone | Outcome |
| --- | --- |
| M0 Foundation | Core repo, API, SQLite, CI, containers, architecture boundaries |
| M1 First Light | Commission a real Matter switch and control On/Off |
| M2 Product Model | Home, Room, Device, capabilities, rename, realtime state |
| M3 Switch / Socket | Multi-gang, dimmer, socket, power/energy |
| M4 Sensors | Temperature, humidity, motion, contact |
| M5 Scenes | Local scenes |
| M6 Automation | Manisa DSL with Home Assistant executor |
| M7 Thread | OTBR and first Matter-over-Thread sensor |
| M8 Production | Secure update, rollback, recovery, hardening |
| M9 Cloud | Optional remote access, push, backup |
| M10 Fleet | Hub/device/firmware fleet management |

## Current status

The project has moved beyond initial M0 scaffolding. The Go Core, storage, versioned API, capability model, Matter adapter boundary, realtime state path, local pairing, Flutter application foundation, QR onboarding, and Direct Matter Android validation build are now in place.

The immediate engineering target is **M1 First Light on real hardware**: commission the prepared Matter-over-Wi-Fi touch switch from Android, identify its endpoint layout, and validate reliable per-gang On/Off control. After that, the same direct Matter-controller capability will be integrated into the branded Manisa mobile application so the phone can operate Matter-over-Wi-Fi devices without requiring a Hub when that product mode is desired.

## License / development status

Manisa is currently under active development. Production security, certification, release signing, OTA strategy, recovery, fleet management, and final commercial licensing/policy decisions are not yet complete.
