# Trance for macOS

Native SwiftUI/AppKit migration of the C++ trance player. Open **Trance.xcodeproj** in Xcode and run the **Trance** scheme on **My Mac**.

```sh
TRANCE_BUILD_METHOD=swiftc ./script/build_and_run.sh --verify
swift test --package-path .
```

Open an original session JSON, or choose a media folder. The player supports pattern-driven images/text, playlists, stereo synthesis, recorded audio, runtime controls and an editable session document. WebM/Ogg use the approved existing FFmpeg helper.

Migration is in progress. See [MIGRATION.md](MIGRATION.md) for the feature inventory, known parity gaps, validation evidence and continuation plan. The original C++ checkout remains intact next to this folder.

Native graphical/audio acceptance: `python3 script/run_acceptance.py`. Test details and the actual-window capture are in [Reports/ACCEPTANCE.md](Reports/ACCEPTANCE.md).

Local packaging: `python3 script/package_local.py --app /absolute/path/to/Trance.app`. This uses the approved installed codec helper and creates a new release directory without removing previous releases. The current installed helper requires macOS 27, so this Apple Silicon package requires macOS 27. Public notarized distribution is not configured.
