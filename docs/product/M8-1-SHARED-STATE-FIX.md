# M8.1 shared-state recovery and connected Wi-Fi

Candidate: 0.25.1+31. Local branch: fix/m8-shared-state-current-wifi.
Baseline: delivered M8 / 0.25.0+30 (PR21, still unmerged; develop is M7.1).

## Outcome

- Standalone BLE discovery entry point removed from the add-device UI and Android method channel. QR/NFC commissioning retains the proven internal BLE rendezvous transport.
- OnOff and Level terminal subscription failures now reach Flutter with node identity. Repairs coalesce per node, wait two seconds, reset only that node's subscriptions, and read/discover controls to restore subscriptions. Foreground and deletion guards prevent stale repairs.
- A foreground-only 30-second watchdog reads controllable OnOff/Level/Color state to reconcile a silent report gap. It does not run scenes, replay writes, or poll sensor-only devices/power snapshots. Device reports remain the fast path.
- OnOff and Level revision guards protect newer reports and local commands from older in-flight refresh/readback results. Existing Color guards are retained.
- At the Wi-Fi step, Android reads the currently connected SSID using runtime location permission. It supersedes the previously used network and loads only that SSID's secure stored password. Unknown/denied connection data falls back to explicit network selection or entry. Native code does not expose or extract Android's saved passwords.
- Existing explicit commissioning action remains required; detecting a network alone never commissions a device. Shared-device on-network commissioning remains password-free.

## Verification

- git diff --check passes.
- Widget coverage added/updated: connected SSID supersedes last network; password cleared for an unknown new SSID; NFC and network-list fallback preserved; old read cannot overwrite external OnOff report; terminal report failure repairs affected node without writes; silent gaps reconcile only in foreground.
- Flutter analyze/tests and integrated Android compilation NOT RUN locally: Flutter/Dart SDK absent. Do not claim hardware acceptance or a finished APK.
- No GitHub push/merge performed: user's October 10 instruction requires approval for GitHub mutations.

## Physical acceptance

Install the candidate on two phones with independent fabrics. Change OnOff, brightness and RGB from each phone in both directions; verify the other phone follows reports, including after background/resume and Wi-Fi interruption. Check rapid alternating writes and network changes. Silent-report fallback can take up to 30 seconds plus reads; firmware must emit Matter dirty-attribute reports for prompt updates.

Names, rooms, favorites and local scenes are app metadata; Matter attribute subscriptions do not replicate them. This change addresses actual device control state, not household/account metadata synchronization.
