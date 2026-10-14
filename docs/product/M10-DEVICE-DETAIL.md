# M10 — Device summary and live detail

Approved scope: 2026-10-14 conversation. User authorized implementation,
GitHub publication and APK delivery without further permission prompts.

## Design

Home retains room grouping and selected-output favorites. Single-output devices
retain direct on/off control; multi-output devices show name, room, availability,
confirmed on-count and unknown/stale qualification. All devices have an explicit
48dp `کنترل وسیله` action. Do not hide access behind long press.

The detail route shows all existing controls and management actions. Reuse
the existing Home state owner, command methods, recovery timers and report
subscriptions. Read the latest device object by node ID on every detail rebuild
so rename, capability discovery and removal do not leave captured stale metadata.
Notify the route on state changes; opening it performs no controller initialization
and no new subscriptions. After removal show an explicit removed state with a
return action; never retain active controls for a deleted node.

Counts use only known confirmed OnOff values. Offline counts are labeled last
known. If some outputs are unknown, show their count explicitly. Sensor-only,
color-only and power devices keep their existing panels on the detail route.
Text wraps in summaries and recovery actions. Keep Persian digits, RTL and 48dp
targets. Matter onboarding, sharing transport and command safety stay intact.

## Implementation plan

> Execute inline. No additional approval gates for this authorized increment.

Goal: compact Home and a detail screen that stays synchronized with live reports.
Architecture: presentation-only summary plus one shared-state route observer.
Stack: existing Flutter/Material, Dart and Android Matter bridge; no dependency.

- [ ] Test Home summary/unknown counts and navigation; update tests that now
  explicitly enter detail to inspect advanced controls.
- [ ] Extract summary widget into `apps/mobile/lib/src/matter/device_summary_card.dart`.
- [ ] Add detail route and a state-change notifier in `direct_matter_app.dart`;
  keep callbacks bound to latest node data and all existing capabilities.
- [ ] Test external reports, route return, deletion, no extra subscription on
  navigation, and 360dp with 200% text.
- [ ] Run analysis and full Flutter suite in CI; review diff and release build.
- [ ] Publish a feature branch targeting develop, version candidate 0.27.0+33,
  and deliver integrated arm64 APK. Do not merge other candidate PRs.

Review focus: stale route metadata, delayed reports after removal, unknown values
counted as off, duplicate subscription on navigation, large-text layout.

Local Flutter SDK unavailable; automated validation uses authorized GitHub CI.
Physical radio and visual acceptance remain a separate real-device check.
