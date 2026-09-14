# Branch map and development workflow

Updated 2026-09-14.

| Ref | Role | Policy |
| --- | --- | --- |
| main | Integration/release target and canonical test register | Promote reviewed candidates by PR; green CI alone does not establish hardware acceptance |
| develop | Current development baseline | Includes validated M3.2.1 merge c2d43fc; active feature work targets this branch |
| codex/m1-persian-onboarding | Historical M1–M3.2 development line | Superseded by develop; retained as rollback reference; no new work |
| codex/m1-baseline-startup-recovery | Historical hardware-tested M1 recovery | Retained; fully ancestral to current development |
| feature/m1-direct-matter-mobile | Historical initial mobile integration | Retained; fully ancestral to current development |
| codex/fix-matter-commissioning-issue | Abandoned commissioning attempt | Contains one commit excluded by the recovery path; do not merge into develop |
| architecture/m0-foundation | M0 historical source | PR #1 already merged; divergent ancestry is not proof of missing work |

Use short-lived feature/m3-<scope> or fix/<scope> branches targeting develop.
The immediate feature scope is M3.3 capability-based power/energy readings.
Do not continue app implementation on the historical branches. Close superseded
PRs with a link to the current integration PR; preserve their discussions and
commit references. Historical refs have not been deleted or force-updated.

main has independent documentation history (including the canonical test record).
A future integration merge must retain it; replacing main with the develop tree
would lose that history. The canonical register remains
[main:docs/testing/M1-test-register.md](https://github.com/PoryaNoorzadeh/Manisa-app/blob/main/docs/testing/M1-test-register.md).

Validated candidate: 0.12.1+17 at c2d43fc29637e06af0c34e0e7bb5c5272d274776. Previous rollback candidate: 0.12.0+16 at 5f7470564c9044c7e4c468d0786737193603a960.
[Integrated build](https://github.com/PoryaNoorzadeh/Manisa-app/actions/runs/34807457773),
[CI](https://github.com/PoryaNoorzadeh/Manisa-app/actions/runs/34807457695),
[Runner](https://github.com/PoryaNoorzadeh/Manisa-app/actions/runs/34807457725).
Hardware dimmer testing and external LevelControl state subscription remain open.
