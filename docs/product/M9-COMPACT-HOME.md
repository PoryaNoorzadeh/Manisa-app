# M9 — Compact daily controls

Design approved in conversation on 2026-10-14. Working branch:
`feature/m9-compact-home`, based on the M8.1 shared-state candidate.

## Intent and scope

Make everyday control easier for Persian-speaking households, including users
who are unfamiliar with smart homes. Preserve direct control, truthful device
state and the working Matter setup/sharing flows. Implement the approved bounded
Home increment first; do not replace navigation or controller architecture.

## Changes prepared

- Move output details into an accessible icon button in the control row. Keep
  favorites and the on/off switch visible; retain rename, color, brightness and
  energy controls inside the existing per-output disclosure.
- For an unavailable device with an error, show one amber notice and one retry
  action. Move connection guidance and diagnostic details into a dialog. Avoid
  a second availability badge and repeated offline wording on every output.
- Label preserved values as `آخرین وضعیت: روشن/خاموش`. Unknown state remains
  explicitly unknown; an unavailable or busy output cannot send a command.
- Let recovery actions wrap for larger text instead of competing for row width.

## Verification status

`git diff --check` passes. Updated existing recovery/detail tests and added a
nine-output layout/disclosure regression test. These Flutter tests have NOT run:
the local environment has no Flutter SDK, and the SDK download endpoint returned
404. Compilation, widget layout, semantics and hardware acceptance remain open.

Before delivering an APK, run `flutter analyze` and `flutter test` in
`apps/mobile`, then the integrated release workflow. Check Home at 360dp with
normal and 200% text, offline/unknown/pending states, independent output
disclosures, and two-phone updates on actual hardware.

## Remaining sequence

1. Complete CI and visual acceptance for this Home increment.
2. Introduce compact device summaries and a live device-detail screen, reusing
   the existing state owner so reports update both views. Decide how many
   favorite outputs remain directly visible on Home before implementation.
3. Split scene creation into output selection and action configuration; retain
   drafts and show a persistent selected-output/save summary.
4. Reuse a single color-control component in live control and scene editing.
5. Bundle a licensed Persian font, shorten empty states/settings copy, and run
   RTL, text scaling and target-size checks across all flows.

Each increment should have its own feature branch targeting develop. This work
does not merge earlier candidate PRs. GitHub publication and build must respect
the user's separate approval requirement.

## Benchmark rationale

Google Home's explicit favorites and separation of daily controls from deeper
controls support progressive disclosure. Apple Home's room organization supports
finding controls in familiar household terms. Apply these principles using
Manisa's teal/mint identity, Persian labels/digits and explicit stale-state
language; do not copy layouts or imply cloud roles/synchronization that the app
does not implement.

References reviewed 2026-10-14:
- https://support.google.com/googlehome/answer/7071794
- https://support.apple.com/en-gb/126180
