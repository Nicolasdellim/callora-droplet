# Feasibility and architecture decision — 5 November 2026

Research completed before implementation. Official SDK checkout: GitLab droppyformac1/droppykit, commit c417d8a, API 1.22.0. Website banner says 1.23.0; do not invent unpublished APIs. GitHub ccharname/droppy is a historical fork, not the current SDK target. Public Store source has no Meetings or Camera source folders; their documented behavior is not a public service available to third-party droplets.

| Requirement | Evidence / decision | Implementation boundary |
|---|---|---|
| Notch / notchless | SDK ShelfWidgetProviding + LiveActivityProviding | Compact activity opens shelf; makeExpanded is no longer mounted |
| Remote video | No public universal third-party stream API | ScreenCaptureKit user-selected window; always labeled window capture |
| Floating window | Droplets execute in-process, AppKit available | Nonactivating resizable NSPanel, no helper required |
| Permissions | Host permissions service, Accessibility APIs | Requests only from settings; no microphone or camera permission needed |
| Call detection | NSWorkspace + AX semantic call controls | Opt-in, bounded background scan; title alone never confirms a call |
| Incoming controls | No universal native incoming-call interface | Open source app; never pretend to answer |
| Camera / mic / end | No SDK Meetings bridge, provider controls not live validated | Do not enable these controls in initial build |
| Local camera | AVFoundation possible, competing camera access risk | Deferred; status and window capture remain useful |
| Video crop | SCStreamConfiguration.sourceRect | Normalized user crop, updated on source aspect changes |
| Cross-window animation | SwiftUI matched geometry cannot cross NSWindows | Animate panel frame from last real preview screen rectangle; fade fallback |
| Capture hidden/minimized | Depends on producer and WindowServer | Report stalled stream, never assert guaranteed minimized-window video |
| Protected content | OS may supply blank frames | No bypass; choose another source |
| Audio | Not required for a preview | capturesAudio=false, no microphone capture |
| Store icon | Current policy assigns final icon to Store maintainer | Custom artwork delivered for GitHub; Store handoff documented |
| Store intake | Store accepts a restricted single-package layout | GitHub includes tests/docs; stage sanitized submission separately |

## Provider capability matrix

All rows support opening the running source application and manual window selection. **No provider in this build claims verified incoming detection, caller identity, mic/camera state, accept, decline, hang-up, direct remote-stream access, or local-camera preview.** Window video is not a remote-stream API.

| Provider | Automatic active detection | Lifecycle | Capture |
|---|---|---|---|
| Zoom | Experimental AX: exact leave/end + audio/video controls in same window, two observations | Ends after three missing observations or app exit | User-selected window |
| Google Meet (Chrome/Safari/Edge/Brave) | Experimental AX: leave call + microphone/camera controls; visible accessible tab only | Same debounce; hidden/inaccessible tabs uncertain | User-selected browser window |
| Teams | Experimental AX: leave/hang up + microphone/camera controls | Same debounce | User-selected window |
| FaceTime | Experimental AX: end call + mute/video controls | Same debounce | User-selected window |
| Discord, WhatsApp | Manual only; no stable public call API assumed | Explicit manual session, ends when source app exits | User-selected window |
| Telegram, Slack, Webex, Signal | Manual only | Explicit manual session | User-selected window |
| Other browsers / arbitrary app | Manual generic provider | Explicit manual session, source exit cleanup | User-selected window |

Detection is evidence based, English semantic labels only; provider UI changes and localization can invalidate it. No real-call validation performed at research time. Never infer a call from app launch, title, or microphone use. Manual sessions explicitly say manual and do not imply provider verification.

## Sources

- https://getdroppy.app/docs/droppykit/add-spm
- https://gitlab.com/droppyformac1/droppykit
- https://gitlab.com/droppyformac1/droplets
- https://github.com/ccharname/droppy
- https://getdroppy.app/docs/droplets/meetings
- https://getdroppy.app/docs/droplets/camera
- https://getdroppy.app/docs/droppykit/live-activities
- https://getdroppy.app/docs/droppykit/icons
- https://developer.apple.com/documentation/screencapturekit
- https://developer.apple.com/documentation/applicationservices/axuielement
