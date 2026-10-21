# M14: retry recovery and responsive controls

Version 0.31.0+37, based on M13 f843afc. Changes are isolated on
feature/m14-responsive-controls. Device records and fabric storage are preserved.

## Connection recovery

The v1.5.1.0 Java Matter controller keeps a BLE connection-id guard. The bridge
owned the BLE callback without forwarding close notifications, and cancellation
left GATT open after MTU negotiation. A failed attempt could therefore block the
next attempt until Activity restart.

The bridge now forwards close callbacks, closes/deregisters GATT, stops failed
pairing, and clears the Java BLE guard. Native attempt identity, native pointer
ownership for attestation, a 20-second BLE setup deadline and a 120-second
commissioning deadline bound each attempt. Callbacks without a node ID are
nonterminal diagnostics: a delayed callback must not fail a newer attempt.

The app offers Stop connecting, retains Wi-Fi inputs for retry, and bounds its
wait at 140 seconds. Cancellation returns whether commissioning already succeeded;
that result is saved rather than discarded. An old cancelled/disposed Dart timer
cannot cancel a newer attempt. Optional endpoint discovery has an 8-second
fallback after commissioning success. Some SDK-only errors may await the bounded
native deadline; the explicit stop action remains available.

Pinned primary reference:
https://github.com/project-chip/connectedhomeip/blob/v1.5.1.0/src/controller/java/src/chip/devicecontroller/ChipDeviceController.java

## Quiet refresh and direct control

Background recovery reads only unavailable nodes. Explicit refresh retains visible
feedback; background repair does not replace home text with repeated refresh
messages. Unchanged OnOff reads no longer rebuild all device controls.

Accessory power actions replace output SwitchListTile controls, including
favorites. Warm amber shows confirmed On; neutral surfaces show Off. Unknown and
unavailable states remain distinct and cannot imply a successful command.

The circular hue/saturation wheel previews locally, including white at its center.
It commits once on release, discards cancelled drags and keeps the reported color
separate from preview. Only the newest unsent color selection is retained during a
color write. Failed writes discard queued intent. Other endpoint commands disable
the wheel rather than silently dropping color selection. Home/room backlights
retain explicit Apply; no saved color is automatically replayed.

Interaction references:
https://support.apple.com/guide/iphone/control-accessories-iph0a717a8fd/27/ios/27
https://support.google.com/googlehome/answer/7073578?hl=en

## Verification

- 189 Flutter tests passed. Static analysis reports no issues.
- Native Kotlin commissioning ownership checks cover single-flight, retry, stale
  callbacks, retained successful outcome and exactly-once completion.
- Existing native sensor/power/removal checks are retained.
- Actual BLE source compiles against Android API jar and pinned Matter API surface
  stubs; complete native linking is still subject to the integrated Android CI.
- Actual Flutter renders inspected for power actions and wheel, alongside the
  existing Persian/English/Arabic walkthrough.
- Physical failed-add -> retry and device-response latency acceptance remain pending.
