# Changelog

## [0.2.0] - 2026-11-05

- Made the dedicated Droppy expanded notch surface the primary call presentation.
- Opened detected incoming/active calls and manually selected video sources in the notch.
- Kept floating panels exclusive to explicit detach actions; dock returns to the actual notch surface.
- Added French incoming/active-call labels and experimental semantic scans for listed calling apps.
- Matched automatic capture to the detected AX window geometry instead of choosing an arbitrary app window.
- Preserved existing preferences while migrating the requested automatic notch workflow.
- Added host-backed regression tests and real capture in the notch without a shelf widget or panel.

## [0.1.1] - 2026-11-05

- Replaced API 1.22-only header layout and button sizing helpers with an API 1.21-compatible shelf presentation.
- Kept the header beneath the host's camera clearance so the build can load in Droppy hosts embedding SDK 1.21.

## [0.1.0] - 2026-11-05

Unreleased development build.

- Added a DroppyKit shelf widget, compact call activity and native settings pane.
- Added user-selected ScreenCaptureKit window capture without audio or recording.
- Added a native floating panel, docking, persistent presentation settings and crop controls.
- Added conservative opt-in Accessibility detection and a manual generic provider.
- Added lifecycle, false-positive, crop, panel and opt-in real-window capture tests.
- Documented unverified integrations, host API compatibility and release blockers.
