# Trance for macOS

Native SwiftUI/AppKit migration of the C++ trance player. Open **Trance.xcodeproj** in Xcode and run the **Trance** scheme on **My Mac**.

```sh
TRANCE_BUILD_METHOD=swiftc ./script/build_and_run.sh --verify
swift test --package-path .
```

Open an original session JSON, or choose a media folder. The player supports pattern-driven images/text, playlists, stereo synthesis, recorded audio, runtime controls and an editable session document. WebM/Ogg use the approved existing FFmpeg helper.

Migration is in progress. See [MIGRATION.md](MIGRATION.md) for the feature inventory, known parity gaps, validation evidence and continuation plan. The original C++ checkout remains intact next to this folder.
