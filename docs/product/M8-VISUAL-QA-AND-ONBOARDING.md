# M8: onboarding, sharing and physical-screen audit

Reviewed 2026-09-30: all 11 supplied PNGs (image.png and image(1).png are duplicates).
Baseline: M7.2 / 0.24.0+29. Candidate: 0.25.0+30.

## Visual findings and next UI work

| Priority | Evidence | Planned change | Acceptance |
| --- | --- | --- | --- |
| P0 | image.png: offline banner, badge, error panel and repeated channel status | One actionable device-level offline notice, preserve last-known state on each output without repeating paragraphs | Never imply unavailable means off; one retry action |
| P1 | image.png + image(2): 9 outputs create a very long device card | Compact home summary, dedicated device detail screen with room/name/favorite management | Primary switch remains one tap; details retain all capabilities |
| P1 | image(5), image(8): scene selection/control mixed in a long form | Select outputs first, configure selected outputs second; persistent save summary | No lost edits, selected count, unsaved-change confirmation |
| P1 | image(10): weekday initials difficult to identify | Full Persian weekday labels (implemented in this candidate) | Saturday-first order, wrapping and accessible labels |
| P2 | image(2), image(8): inconsistent color controls | Reuse one color picker in live and scene editing | Same hue/white interaction, no extra saturation control |
| P2 | image(3), image(4), image(7), image(9): large text blocks and empty space | Shorter explanations, inline empty-state CTA, task-oriented settings | 360px and 200% text size, no clipped controls |
| P2 | all screens: fallback Persian typography | Bundle a licensed Persian font and validate before changing tokens | No network font dependency, legible numerals and 48dp targets |

## Implemented candidate flows

- Wi-Fi list: explicit Android runtime location permission, Wi-Fi/location-disabled messages, bounded scan, SSID deduplication, strength order, 2.4GHz guidance, stale-scan indication and manual hidden-network fallback.
- Credentials: flutter_secure_storage, exact SSID keys, restore last network, remember checkbox and per-network forget. Save after commissioning succeeds; never into device JSON/logs/QR. Android backup disabled for integrated app.
- NFC: foreground NDEF text/URI Matter payload only; bounded wait, cancellation, unsupported/disabled/invalid-tag errors. Requires a programmed physical NFC tag, not merely an NFC phone.
- BLE: show only Matter service FFF6, select advertised discriminator, require QR/NFC possession proof and verify discriminator before commissioning. Selecting BLE alone cannot securely reveal the Matter setup PIN.
- Sharing: explicit confirmation text, SDK enhanced commissioning window with random PIN, fresh QR after device acknowledgment, maximum 180s window, hide QR on background and expiry. Receiver explicitly selects shared-device mode and uses on-network commissioning with no Wi-Fi password. Does not copy fabric credentials or original QR.
- Sharing grants independent administrator control, not an account role or cloud invitation. Owner-side fabric revocation UI is future work; do not advertise role-based access.

## Mandatory physical acceptance (not replaced by CI)

1. Android 11 and 13+: permit/deny scan, location off, Wi-Fi off, throttled scan, hidden SSID, duplicate SSIDs, open and WPA networks.
2. Add first device, restart app, add second device without typing password; forget and verify empty field; wrong password must not replace stored credential.
3. NFC absent/disabled, valid UTF-8 NDEF text and URI, invalid tag, remove tag mid-read, background/cancel and retry.
4. BLE off/permission denied/no results/multiple devices; wrong QR rejected; correct QR selected device commissions; never auto-use a universal PIN.
5. Two real phones on same LAN: share, scan temporary QR, on-network commissioning, both phones independently control; expired QR fails; fabric-table-full error; device offline; no factory reset.
6. Re-run original commissioning/delete/re-add/readback/scene tests on board. CI cannot certify radio behavior or multi-admin firmware support.

## Primary references

- https://developer.android.com/develop/connectivity/wifi/wifi-scan
- https://developer.android.com/reference/android/nfc/NfcAdapter
- Matter SDK pinned to v1.5.1.0: src/controller/java/src/chip/devicecontroller/{ChipDeviceController,OpenCommissioningCallback}.java

## Delivery scope

Feature branch based on still-open M7.2 candidate; target develop. Do not merge PR20 or this candidate automatically. Visual architecture changes above are planned, not claimed complete. New hardware flows require real-device acceptance before release.
