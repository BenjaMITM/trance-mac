# Desktop acceptance — 2026-10-02

Validated on Apple Silicon, macOS 27.0.1, Xcode 27, Swift 6.4.

## Passing checks

- 33 Swift core tests: schemas, source fixture compatibility, playlist stack/timing, variable/theme/program reference updates, pattern parsing/evaluation, invalid-recipe fallback and portable ZIP integrity.
- Three native XCTest audio checks: the production synthesis callback runs through AVAudioEngine's offline renderer; stereo channels differ, settled levels stay within asserted RMS/peak bounds, samples remain finite, mute/pause produce silence, resume restores output and removing layers settles to silence.
- Recorded WAV playback runs through AVAudioPlayer on the audio device. Playback time advances, looping is enabled, pause holds time, mute sets zero gain, fades reach their requested level and stop releases the channel.
- Generated Ogg/Opus and WebM/VP9 fixtures convert through the approved FFmpeg helper. Decoded WAV samples contain signal; the converted movie is playable with a positive duration.
- Native XCUITest launches the real app and clicks pause/resume, mute/unmute, controls visibility, section expansion and program duplication. It reads the saved session to confirm the duplicate. The actual window screenshot contains more than 100 sampled colored pixels from the generated media; image, spiral, caption and editor are visible in the retained attachment.

## Fixes prompted by testing

- Startup now initializes session state independently of the first view appearing, restores a player window and creates one if SwiftUI restoration omits it.
- Visuals can collapse. Section headers accept clicks across their full row.
- Program action labels use separate rows to avoid truncation in a narrow sidebar.
- The codec service prefers a packaged helper and invalidates conversion tasks when source modification time/size changes.

## Evidence and limits

Xcode result bundles are retained locally at `/private/tmp/trance-acceptance-final.xcresult` (complete audio/UI suite) and `/private/tmp/trance-acceptance-layout.xcresult` (final action-layout UI check). The screenshot is `desktop-acceptance.png` in this folder.

Automated checks establish rendered signal, decoded assets, device-player progression and the specific UI interactions above. They do not constitute a human listening assessment, exhaustive interaction coverage, sustained memory/load testing, or proof of every feature's parity. Remaining migration work remains in MIGRATION.md. Headset support is deferred.

The local release is ad-hoc signed, not notarized. Its bundled installed FFmpeg requires macOS 27, so the self-contained local package requires macOS 27 and Apple Silicon. The application source still targets macOS 15, and the app executable builds for Intel and Apple Silicon. Public distribution/source-license and Developer ID/notarization work remains separate.

## Packaged artifact verification

The local package was extracted to a fresh location. Deep/strict signature verification, bundled-helper startup, Ogg/WebM conversion through the relocated helper, session lint, portable ZIP integrity, DMG checksums and published SHA-256 checksums all passed. The extracted app launched and responded to status/pause/resume/visual/screenshot commands. This confirms the local package's tested paths; it is not notarized public distribution.

Reproduce native acceptance with `python3 script/run_acceptance.py` from this app directory. It runs `xcodebuild test -scheme Trance -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` against a clean project snapshot and retains the log/result bundle under `build/`. Core checks use `swift test`. Rebuild a local package with `python3 script/package_local.py --app /absolute/path/to/Trance.app`.
