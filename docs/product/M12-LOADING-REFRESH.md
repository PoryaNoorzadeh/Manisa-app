# M12 — Loading and refresh experience

Authorized 2026-10-14: continue without approval prompts. Includes the completed
M11 scene wizard. Scope this increment to Home, live device detail and descriptive
loading feedback in scenes/schedules; preserve commissioning/command safety.

## UX contract

- Restore saved Home metadata before waiting on the native controller. Show
  a labeled loading placeholder only while local storage is loading, then show
  saved cards with an explicit connecting/checking status. Never present unknown
  values as off or declare Home ready before the first state check.
- Bound native startup; on failure preserve saved cards and offer explicit retry.
  Retry must not reload already restored metadata or duplicate event subscriptions.
  Block radio operations until controller setup succeeds; metadata can stay visible.
- Keep existing content and confirmed control values while refreshing. Existing
  ready outputs remain usable; only the refresh action shows progress/is disabled.
- Join overlapping per-node and all-device refresh requests. Pull-to-refresh
  completes only after the actual in-flight read/discovery task completes.
- Show localized progress in Home and detail, plus the last completed Home check
  time. This is an attempt time, not a claim that every optional value is fresh.
- Pull-to-refresh works on short/empty Home and on detail. Preserve scroll and
  output disclosure state while reports or refresh progress arrive.
- Scenes and schedules use the same descriptive loading notice rather than an
  unexplained full-screen spinner. No fake percentage or artificial delay.

## Verification and delivery

Test delayed native startup with saved metadata visible; initialization failure
and retry; blocked premature radio operations; refresh coalescing/completion;
preserved controls, detail progress and disposal safety. Retain existing late-read
revision guards and radio/hardware acceptance requirements. Run full CI, independent
review and integrated arm64 build, candidate 0.29.0+35. Feature branch targets
develop; no automatic merge. Local Flutter unavailable; use authorized GitHub CI.
