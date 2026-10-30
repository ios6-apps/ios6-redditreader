# Contributing

Thanks for looking. This app targets **iOS 6.0 and up on armv7** and has so far only been tried on an iPhone 5 running iOS 6.1.3. Anything that
only works on newer iOS has to be guarded or left out.

## Building

    tools/setup-sdk.sh                      # once: fetches and patches the public iOS 9.3 SDK stubs into ./.sdk
    export SDK93="$PWD/.sdk/iPhoneOS9.3.sdk"
    ./build.sh device                       # unsigned build/RedditReader.ipa
    ./build.sh sim                          # arm64 simulator build with preview hooks (see the README)

Installing the unsigned IPA needs a device that accepts unsigned apps (a jailbreak with AppSync Unified).

## Ground rules

- Objective-C, no Swift, no third-party package managers. Small vendored C libraries live in `third_party/` with their licence.
- Compile with ARC (`-fobjc-arc`), link without it: current Xcode has no `libarclite` for iOS 6 and the iOS 6 runtime already
  has the ARC entry points we use. In practice: `__weak` is fine, avoid anything that needs `libarclite`.
- Use only APIs that exist on iOS 6 (`UIAlertView`, `NSURLConnection`, `sizeWithFont:`, ... are right; `NSURLSession`,
  `UIAlertController`, `UIStackView` are not). A `-Wno-deprecated-declarations` build is expected.
- Keep it in the style of the surrounding code: short comments that say why, not what.
- No analytics, no tracking, no hard-coded credentials or personal addresses. Test data must be made up.
- Run the tests if the repo has any (`tests/run.sh`) and say in the PR how you tried the change (simulator and/or device).

## Reporting bugs

Please include the device model, iOS version and whether it is jailbroken, plus what you expected to happen.

## Releases

CI (`.github/workflows/ci.yml`) builds and tests every push to `main`. On `main` it then publishes the unsigned IPA twice: to a rolling `nightly` pre-release
(replaced each time) and, if `CFBundleShortVersionString` in `Info.plist` has no release yet, to a new versioned release `vX.Y.Z`.
To ship a version: raise `CFBundleShortVersionString` in `Info.plist`, add a `## [X.Y.Z] - date` section to `CHANGELOG.md` (its text becomes the release notes), and merge to `main`.
`CFBundleVersion` is set to the CI run number at build time; do not edit it by hand. Versions starting with `0.` are published as pre-releases.
