# RedditReader - notes for Claude Code (and other coding agents)

It reads Reddit's logged-out Atom feeds and shares its TLS layer (`src/HNTLS.c`, `src/HNSecureProtocol.m`; the `HN` prefix is historical) with HNReader.
**Never remove or bypass the request queue in `RRFeed`**: it keeps the app inside Reddit's rate limit (about one request per 40 s). Do not hammer Reddit when testing; use cached results or the Saved list.
Prompts: use `RRPrompt` instead of `UIAlertView`, because some jailbreak tweaks hide alert views.

This is an iOS 6 app (armv7, deployment target 6.0, written for an iPhone 5 on iOS 6.1.3) built with a current Mac toolchain. Read `README.md` for what it does
and `CONTRIBUTING.md` for the ground rules; this file is the short version for working on it.

## Build

    tools/setup-sdk.sh                       # once; fetches and patches the iOS 9.3 SDK stubs into ./.sdk (git-ignored)
    export SDK93="$PWD/.sdk/iPhoneOS9.3.sdk"
    ./build.sh device                        # unsigned build/RedditReader.ipa, armv7
    ./build.sh sim                           # arm64 simulator app build/sim/RedditReader.app, compiled with -DRR_PREVIEW

Needs Xcode (or its command line tools) on macOS. There is no Xcode project; `build.sh` calls `clang` directly. Do not commit `build/` or `.sdk/`.
If the device link fails with `file not found: /usr/lib/system/liblaunch.dylib`, the SDK was not patched: run `tools/setup-sdk.sh` again.

## Test

Run `tests/run.sh`: the MP4 joiner (`tests/mux_test.c`), feed parsing (`tests/feed_test.m`, UIKit is shimmed), and, if `ffmpeg` with libx264 is installed, an end-to-end video join check.
The UI, TLS and networking are not covered by tests.

CI (`.github/workflows/ci.yml`) runs the simulator build and the tests on macOS, then the device build. Run the same before proposing a change.

## Rules that are easy to break

- **iOS 6 APIs only.** No `NSURLSession`, `UIAlertController`, `UIStackView`, Auto Layout-only code, `@available`, Swift or new frameworks. The simulator is much newer than the target,
  so code that runs in the simulator can still crash on iOS 6: check the API's availability, not just whether it compiles.
- **ARC is compiled in but not linked.** Files are built with `-fobjc-arc`; there is no `libarclite` for iOS 6, so avoid constructs that need it. `__weak` is fine.
- **The device build links against SDK stubs** with `-undefined dynamic_lookup`. A missing symbol shows up as a crash on the phone, not as a build error. Prefer `dlsym` for anything newer than iOS 6.
- **Preview hooks (`RR_PREVIEW`) exist only in the simulator build.** They read environment variables (listed in the README) so a screen can be reached without tapping. Keep new hooks inside `#ifdef RR_PREVIEW`, and never let them into the device build.
- **No fake data outside previews and tests, no credentials, no personal addresses, no analytics.** Test data must be made up.
- **Be careful with the network.** Only touch the services the README lists. Do not run discovery sweeps or tests against hosts you do not own.
- Match the surrounding style: short comments that say why, not what.

## Layout

See the project layout table in `README.md`. Sources are in `src/`, drawing is done in code (no image assets except the icon and launch images, which `make_assets.py` draws; it needs Pillow).

## Before you finish

Say how you checked the change: which tests, simulator and/or a real device. Do not claim a fix works on a device you did not run it on.
