# Release gates and remaining work

This development build does **not** yet meet the product brief's complete Definition of Done. No release tag should be created until these gates are met.

- Host loading is verified for Callora 0.1.1 in Droppy 16.2.1-nightly.20261101 with SDK 1.21.0. Observe all real notch, island and camera-island surfaces next. The public stable Playground 1.0.29 remains too old.
- Validate at least one actual calling application: incoming/active/ended transitions, correct window identity, detach, drag, resize, dock, close without hang-up, end-call cleanup. The controlled local-window test does not satisfy this gate.
- Add app/version/locale-specific detection fixtures and live-call evidence. All automatic providers remain experimental. Title and device-use false positives are already rejected by unit tests.
- Test permission revocation, app crash, source replacement/minimization, sleep/wake, full-screen Spaces, multiple physical displays/scales, keyboard/VoiceOver, Reduce Motion and Increased Contrast.
- Profile capture, prolonged calls, multi-monitor motion and idle operation. No sustained CPU/battery benchmarks have been measured.
- Verify continuous drag/docking motion in the real host. Cross-window frame animation has a fallback; no guarantee of a seamless shared compositor surface.
- Implement reliable provider-specific controls only with supported APIs or validated accessible semantics. Incoming answer/decline, mic/camera, sharing state and hang-up are currently unavailable.
- Implement optional separately labeled local-camera preview only after shared-camera ownership and permission behavior are tested. The current build deliberately requests neither camera nor microphone permission.
- Refine source picking with thumbnails and direct visual crop selection. Current crop uses normalized sliders.
- Add auto-expansion preference and richer incoming/connecting/reconnecting presentations when real provider evidence supports them. The state model includes these phases; they are not claimed as live integrations.
- Add appearance variants beyond the current dark native shelf and black material panel, default size/location controls, controls-on-hover preference and magnetic docking feedback. Current layout and opacity settings are functional but do not cover every personalization item in the brief.
- Obtain the creator-approved avatar and final Store icon from the maintainer. Custom icon artwork in this repository is not Store-approved.
- Complete sanitized Store validation, signing, notarization/review and real release artifacts before tagging a release.
