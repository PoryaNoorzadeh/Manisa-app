# M11 — Two-step scene editor

Authorized continuation on 2026-10-14. Implement inline without further approval
questions. Keep existing scene persistence, capability validation and execution
safety. No new dependencies, cloud behavior or automatic command execution.

## Design and implementation

1. New scene starts at output selection. Only checkboxes appear here. Display a
   persistent selected count; Next requires 1–32 selected outputs.
2. Configuration shows the name and only selected outputs with their existing
   on/off, optional brightness and color controls. Saving remains explicit and
   must not send commands. Existing scenes open directly at configuration.
3. Back from configuration returns to selection without losing the name or any
   retained output targets. Returning to configuration preserves the draft.
4. Back/cancel from selection asks to discard only when the draft changed.
   Protect system back as well as the visible back button. Save failure leaves
   the user at configuration with the complete draft and an explicit retry.
5. Footer actions wrap at narrow widths and 200% text. Removed output references
   remain visible/removable. Turning an output off clears optional light targets
   exactly as before. Use Persian labels and digits, 48dp actions and RTL.

## Work and verification

- Modify `apps/mobile/lib/src/matter/manual_scene_screen.dart` only for editor UX.
- Adapt existing persistence/lighting widget tests to Next; add step separation,
  retained draft, discard confirmation, empty/32-output guard and narrow-layout
  coverage. Keep at-most-once runner tests unchanged.
- Run full analysis/tests via authorized GitHub CI (local Flutter unavailable).
- Review diff independently, publish feature branch targeting develop, build
  integrated 0.28.0+34 APK and verify its version/checksum. Do not merge candidates.

Color component consolidation and Persian font work remain later increments.
