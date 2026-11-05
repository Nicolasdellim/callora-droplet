# Contributing

Use Xcode 26 or later and Swift 6.2+. Pin DroppyKit to the published version in Package.swift. Run `swift test`, the official `droppykit build`, `droppykit validate --no-submission`, and the harness shots/report. Read docs/FEASIBILITY.md before adding integrations.

Every provider must report only capabilities backed by verified behavior. Include app version, macOS version, locale and reproduction evidence when promoting detection or controls from experimental. Never use microphone activity or a window title alone as proof of a call. Never add a call-ending side effect to preview close.

Keep AX I/O on its dedicated queue and all AppKit mutations on the main actor. Cancel tasks, unregister shortcuts and stop capture in deactivation. Add meaningful lifecycle, permission-denial and false-positive tests. No captured-call fixtures, secrets or real participant images in commits.

Use small focused pull requests with the observed problem, final behavior and actual checks performed. Submit Store changes from a sanitized staging directory, not the full development repository.
