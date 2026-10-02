# Changelog

## Unreleased

### Added
- Native macOS Xcode app with SwiftUI controls and an AppKit playback canvas.
- Swift session, playlist and v3 pattern implementations using the original eight built-in recipes.
- Recorded audio and stereo synthesis, menu bar controls, overlay, global hide/show, loopback commands and MCP transport.
- JSON editing, legacy session import and portable ZIP export.
- Core tests and a shared build/run entrypoint.

- Dedicated custom-pattern and playlist editors, native color pickers and visual pin controls.
- Headless session lint and archive export without starting the UI or audio engine.

### Fixed
- Core Audio callback isolation causing startup crashes in the first build.
- Exhausted subroutines restarting, incorrect playlist reference handling, and permissive malformed session fields.
- Named ancestor image-register addressing and shared ramp-segment registers.
- Audio cue conversion ordering and stale theme-audio replacement.

### Known limitations
- Feature parity is under active verification; see MIGRATION.md before relying on existing sessions.
