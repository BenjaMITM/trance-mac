# Changelog

## Unreleased

### Added
- Native macOS Xcode app with SwiftUI controls and an AppKit playback canvas.
- Swift session, playlist and v3 pattern implementations using the original eight built-in recipes.
- Recorded audio and stereo synthesis, menu bar controls, overlay, global hide/show, loopback commands and MCP transport.
- JSON editing, legacy session import and portable ZIP export.
- Core tests and a shared build/run entrypoint.

### Fixed
- Core Audio callback isolation causing startup crashes in the first build.

### Known limitations
- Feature parity is under active verification; see MIGRATION.md before relying on existing sessions.
