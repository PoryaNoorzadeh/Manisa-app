# M13: Manisa home design

Base: remote feature/m12-loading-refresh at 2130afb. The native Matter bridge,
controller, existing persisted device schema and commissioning sequence are retained.

Implemented presentation: approved indigo/ink surfaces, original ribbon brand mark
with correctly spelled native مانیسا / MANISA text, unified top add menu, room
filters, actual sensor summaries, editable home name, tasks and settings.

Persian is the first-launch default. English/Arabic selection persists separately
from device data. User-assigned names and Wi-Fi credentials stay unchanged.
Vazirmatn is bundled under the OFL license in assets/fonts.

Backlights: explicitly select the RGB endpoints controlling switch backlights.
Home color applies to selected endpoints outside rooms with overrides. Room colors
are independent. Settings are intent, not proof that a device changed. Loading,
selecting, moving a slider or reconnecting never sends a saved color automatically.
Apply issues color-only commands through the existing controller and checks actual
readback. Explicit retry targets only unconfirmed endpoints. Brightness and power
are independent. All unavailable/partial outcomes stay visible.

Validation status and hardware acceptance are recorded in the final handoff.
The UI follows existing local-first capabilities: schedules need the app active;
there is no new cloud service or always-on scheduler.

## Validation — 18 October 2026

- Baseline before redesign: 161 Flutter tests passed.
- Current implementation: 175 Flutter tests passed, including added language,
  persistence, backlight, selected-room deletion, raw user-name, generated copy
  and visual tests. Static analysis reports no issues.
- Three-language phone renders inspected using bundled Vazirmatn and icon fonts.
- Independent review found selected-room deletion and user-name localization bugs;
  both were reproduced as failing tests, fixed and included in the green suite.
- Matter controller, native Kotlin bridge, device persistence format and protocol
  models have no implementation changes.
- Adaptive/legacy launcher resources omit an added white backing disc; Android
  launchers still choose their outer mask. New XML and build YAML parse correctly.
- A local release bundle attempt was blocked by missing Android SDK, not a Dart
  compilation error. No new APK is claimed. The existing integrated Android CI
  workflow is prepared with M13 version/artifact labels.
- GitHub branch exists; code publication was denied by automatic approval review
  pending explicit user permission. Implementation is committed locally.
- Physical phone/switch acceptance (including launcher masks) remains pending.
