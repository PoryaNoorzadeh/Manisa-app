# Matter build time follow-up

The M5 follow-up reduces repeated native compilation with the SDK's supported
`--pw-command-launcher=/usr/bin/ccache` option. Every existing build and validation
step still runs: this is a compiler cache, not a previously built APK or SDK bundle.

## Identity and fallback

The exact key includes the checked-out SDK commit, host OS/architecture, ARM64
CHIPTool debug target, Android SDK/build-tools, NDK properties, Kotlin version,
ccache version and cache recipe. There is no broad restore prefix. ccache also
checks compiler contents, compilation options and source/header inputs. No relaxed
hashing options are enabled. A miss or eviction performs normal compilation.
Only compiler results are cached, at most 2 GiB; no credentials, signing material,
Gradle output, generated Android shell, APK or application source is restored.
Caches save only after successful jobs through actions/cache's default policy.

The integrated workflow also runs on develop when its build infrastructure changes,
so subsequent PRs can restore a base-branch cache. GitHub's normal PR cache isolation
is retained. Both official and integrated Matter builds use the same recipe.
App version remains 0.21.0+26 because this step changes build infrastructure only.

## Validation

Pending: cold build, warm rerun, measured cache hits and all existing CI gates.
Do not claim a speed improvement until measured; network/bootstrap and Java/Gradle
work remain outside the compiler cache. The first run still compiles everything.

References: pinned Matter SDK v1.5.1.0 `scripts/build/build_examples.py` and
`scripts/build/builders/android.py`; actions/cache v4 `action.yml`.

## Next product milestone

M6 minimal automation follows the scene hardware checks. Before executable
scheduling, document where execution lives (phone or hub), behavior when the app
is closed/offline, timezone changes, restart and missed-run policy. No background
execution reliability is implied by the completed manual-scene work.
