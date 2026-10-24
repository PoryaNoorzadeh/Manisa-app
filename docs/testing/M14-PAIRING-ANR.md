# M14.1 pairing regression recovery (0.31.1+38)

User evidence: Android's “Manisa isn't responding” dialog during Wi-Fi
commissioning on build 37, plus reported process exits. No device logcat or
tombstone was supplied, so the exact native crash signature remains unconfirmed.

## Findings and changes

* M14 moved GATT notifications onto the main Handler but queued the mutable
  BluetoothGattCharacteristic object. SDK v1.5.1.0 reads its value only at delivery;
  two queued notifications could deliver the second packet twice. Snapshot the
  bytes before posting, forward those bytes through AndroidChipPlatform with the
  SDK's big-endian UUID encoding, and support the API 33 value-bearing callback.
  Null/empty data is rejected before JNI dereferences an array.
* MainActivity used runOnUiThread in attestation/completion callbacks. Unlike
  Handler.post this may run inline when already on main. Always defer JNI
  continuation, endpoint discovery, and completion cleanup to leave native
  callback/lock scopes before re-entering the controller. Preserve per-attempt
  ownership and the current-pointer check.
* BLE setup failure removed GATT before notifying its owner to stop pairing.
  Notify the owner first and guarantee idempotent cleanup in finally.

## Regression evidence

`check_commissioning_reentrancy.py` compiles the actual Activity callback methods
against a non-reentrant JNI boundary and deterministic queue. Before the fix,
attestation, success discovery, failure cleanup and stale-attestation cases all
failed on inline native re-entry; afterward all four pass. This is a boundary
simulation, not a physical Matter integration test.

`ManisaBleCommissionerTest.kt` compiles the actual transport with Android boundary
test doubles. The original code overwrote packets, missed API 33 delivery and
removed GATT before owner cleanup. The corrected code passes five cases including
cancelled packet suppression. Existing ownership checks also remain passing.

CI runs these checks before compiling the complete bridge against actual pinned
SDK v1.5.1.0, and runs Flutter analysis plus the full Flutter suite.

## Hardware acceptance still required

Pair a reset device; cancel and retry; fail Wi-Fi credentials and retry; pair a
second device without reopening the app. Confirm the UI responds throughout.
If a process exit persists, capture Android logcat/ANR trace for that build;
do not interpret host tests or a successful APK build as hardware acceptance.
