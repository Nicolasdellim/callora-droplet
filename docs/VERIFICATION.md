# Verification — 5 November 2026

Environment: Apple Silicon Mac, macOS 26, Xcode toolchain Swift 6.3.3. SDK 1.22.0 pinned to c417d8a54cc45fb798b06b8a5b88dfa4761f5938. Published SDK checkout and SwiftPM pin agree.

| Check | Result | Evidence / boundary |
|---|---|---|
| Model unit tests | Passed | Six tests: transitions, false positives, debounce, capability honesty, crop bounds, settings roundtrip |
| Native panel test | Passed | Nonactivating/resizable/full-screen auxiliary NSPanel; close calls hide only |
| Real ScreenCaptureKit integration | Passed | Existing OS grant; captured a generated local AppKit window, received real frames, resized source, observed changed stream dimensions, showed/resized a native panel, stopped capture and cleared buffers; source window remained open |
| Combined latest local run | Passed | Eight Swift Testing tests; 5.902 seconds including five-second source resize tracking wait |
| Universal official build | Passed | arm64 + x86_64; official build script, framework linkage and minAPI ledger |
| Development-layout validation | Passed | `droppykit validate --no-submission`; manifest, Icon Composer references, avatar, linkage, API and architectures |
| Official harness | Passed | Eleven actual rendered pages; activation error null; problems empty; shelf-widget, live-activity and settings-pane provided |
| Actual Playground host load | Blocked | Downloaded stable 1.0.29 embeds API 1.20.1 and refuses Callora minAPI 1.22.0; no host activation claimed |
| Real third-party call | Not performed | No claim of reliable app-specific detection, incoming controls or complete real-call lifecycle |
| Physical multi-monitor / full-screen / sleep tests | Not performed | Code paths exist; hardware/user scenarios remain release gates |
| Battery / sustained CPU benchmarks | Not performed | Idle default starts no detection or capture timer; no measured battery/CPU claims |
| GitHub Actions CI | Passed | [Run 42089959932](https://github.com/Nicolasdellim/callora-droplet/actions/runs/42089959932): tests, universal build, validation, all harness renders/report and artifact upload succeeded; capture integration requires a local OS grant and is skipped in CI |
| Store submission / signed release | Not performed | Development source and build only; requires release gates and Store review |

Observed loader refusal: `apiTooNew(bundleMinimum: 1.22.0, host: 1.20.1)`. The stable update manifest also advertises Playground 1.0.29. Lowering the requirement would create missing-symbol failures and was not used as a workaround.

`floating-capture-test.png` is an actual window screenshot from the real capture integration test, showing its generated local test source inside Callora's real floating view. It contains no call or remote participant. `screenshots/` contains actual SDK harness renders in the idle/unconfigured state. Neither kind of image proves integration with a live calling application.

No public release tag was created. The complete product Definition of Done remains open; see ROADMAP.md. The linked GitHub run independently validates the code; the real capture test was run locally with an existing Screen Recording grant.
