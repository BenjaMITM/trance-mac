# Trance Swift migration

Source: `../trance-original-windows-dotnet`, C++17 (not .NET). Destination: this directory. The original checkout is preserved and excluded from the new workspace Git repository.

## Build and run

Open `Trance.xcodeproj`, select the Trance scheme and My Mac, and Run. Alternatively use `./script/build_and_run.sh --verify` or the Codex Run action. Minimum deployment target: macOS 15. Swift language mode: 6, strict concurrency complete, default isolation nonisolated. UI state is explicitly MainActor; source parsing runs on a loader actor; audio callbacks use a nonisolated factory and mutex-protected synthesis state.

If Xcode stalls in coordinated file access, use `TRANCE_BUILD_METHOD=swiftc ./script/build_and_run.sh --verify`. This builds the same native sources into `dist/Trance.app` with the installed Apple compiler. The Codex Run action currently selects this verified path.

Core tests: `swift test --package-path .`. Build output: `build/Build/Products/Debug/Trance.app`. CLI arguments follow the original `--name=value` spelling.

WebM and Ogg compatibility uses the existing, user-approved FFmpeg executable at `/opt/homebrew/bin/ffmpeg` or `/usr/local/bin/ffmpeg`. It converts assets into a temporary cache, leaving source media intact. This is a runtime dependency, not bundled software.

## Feature accounting

“Implemented” below means code exists. Only explicit validation notes establish behavior. This is an ongoing migration, not a declaration of full parity.

| Source feature | Swift implementation | Remaining parity work |
|---|---|---|
| Session JSON, atomic save/export | JSONValue, Session, editor | Strict schema and source repair implemented/tested; exact serialization and all edge fixtures remain |
| Relative-path validation | Session.resolve | Compare symlink and all source edge cases |
| Folder discovery, exclusions, inheritance | Session.scan, ThemePool | Matching-directory conversion and source text splitting implemented; exact extension classification remains |
| Weighted themes, two slots, runtime pins | PlaybackStore | Loading queue parity, source-tier zero-weight behavior, refresh and saved pins UI |
| Eight built-in patterns | Original recipes in BuiltinPatterns | Frame-by-frame C++ comparison; mirror tiling/projection parity |
| V3 parser/expressions/nested clocks/ramp/burst | PatternParser, PatternRuntime | Ancestor/ramp register scopes implemented/tested; sequence index/loop accounting and strict semantic limits remain |
| Images, GIF, WebM | PlayerCanvas, VideoFrameService, CodecService | Animation ownership/pause timing, asynchronous image decode/downsampling, cache diagnostics |
| Text, fonts, captions, subtext | PlayerCanvas | Exact layout/cadence, shadow/alpha compatibility |
| Spirals, warp/drunk | PlayerCanvas | Original shader/geometry parity; Metal renderer and performance validation |
| Playlist durations, branches, variables, subroutines | PlaylistRunner | Source stack timing/return/exhaustion/recursion tested; broader randomized comparison remains |
| Playlist audio play/stop/fade/loop/unused channels | AudioService | Cue ordering under async conversion; pause and stale-conversion checks |
| Theme audio | AudioService | Async replacement races and streamed buffering parity |
| Synthesized bed | AudioService | Unclipped calibration added; source exact calibration and transitions need comparison |
| Pause/mute/hide/show | PlaybackStore | Live acceptance across main window, settings, and multiple windows |
| Menu bar / tray equivalent | MenuBarExtra | Opacity menu presets and source exit semantics |
| Global Shift+F11 | HotkeyService | Live global-key acceptance |
| Click-through overlay | NSWindow controls | Live mouse/Spaces/fullscreen acceptance |
| F1/F2 diagnostics/control panel | SwiftUI views | Full loaded/failed/cache accounting and all graphical source editor controls |
| Full session editor | TextEditor with validation/save | Custom-pattern and playlist editors implemented; variable and theme media/exclusion editors remain |
| Program/audio settings and autosave | ProgramControls, AudioControls | Visual pins and native colors implemented; complete theme/program/system authoring remains |
| System JSON | PlaybackStore, Settings | Frozen legacy system.cfg importer; settings that change engine behavior |
| Legacy .session conversion | LegacyImporter | Frozen-schema field rejection, all escaping/list forms, enum numeric values and fixture comparisons |
| ZIP .trance export | ArchiveExporter | Independent ZIP integrity/roundtrip tests; large streaming ZIP/ZIP64 |
| Loopback line protocol | CommandService | Source status formatting/uptime, exact diagnostics, live all-command acceptance |
| MCP stdio | CommandService | Original 30 tool names plus generic command tool implemented; structured JSON-RPC errors and all-tool acceptance remain |
| Screenshot PNG | CommandService | Live composited frame acceptance |
| CLI lint and archive export | TranceDelegate | Headless entrypoint implemented/tested; default cold-start scan behavior remains |
| Windows OpenXR output | Deferred, non-essential | Begin only after the desktop app is completed, tested and production-packaged; preserve any existing headset code |
| Console progress and source diagnostics | Basic on-screen clocks only | Full coalesced stderr section/theme logging |

## Verification and checkpoints

- First native app build succeeded with Xcode 27 / Swift 6.4.
- Eight core tests passed, including system unzip integrity/roundtrip, non-destructive legacy import and subroutine return. Five initial tests cover: all eight built-ins parse/evaluate for 4096 frames each; weighted tickets; named clocks/cadence entry; JSON preservation/path rejection; conditional playlist timing.
- Initial launch crashed in the Core Audio callback due to inherited MainActor isolation. Fixed with a nonisolated callback factory; subsequent runtime command and screenshot verification succeeded. Explicit presented scene launch fixes an additional no-window startup condition.
- First loopback smoke attempt failed with connection refused because of that crash. Subsequent native builds launch successfully and live status/theme/pause/resume/visual/text/bed/hide/show/overlay commands returned successful replies. Screenshot PNG captured and inspected: generated image, spiral and caption visible. SwiftUI control text is not present in the cached screenshot; UI acceptance still needs a direct screen capture.
- Computer Use was authorized for Xcode but rejected Trance access; visual UI acceptance is not yet verified.
- Save point `153b2bc` is the initial compiling migration; it predates the audio callback runtime fix. Do not describe that commit as runtime verified.

- Latest native build/run verification succeeded with no compiler warnings.
- MCP live stdio initialize, 31-tool listing, status and bed-layer-add calls passed.
- FFmpeg smoke converted generated WebM and Ogg inputs into MOV/WAV cache files; animation session status and screenshot succeeded. Audible output was deliberately muted and is not verified.

## Desktop completion order

Headset work is explicitly deferred by the user. Desktop production readiness is a prerequisite, not a parallel workstream. Preserve any headset code that already exists; do not add or progress headset support until the desktop release has passed its gates.

1. Finish session, system and legacy compatibility plus deterministic pattern/playlist comparison coverage.
2. Complete desktop authoring: themes/media/exclusions/weights, variables, programs, system settings. Custom-pattern and playlist editors are now implemented.
3. Finish rendering/animation/cache/audio parity, all-command/MCP acceptance and desktop hotkey/window acceptance.
4. Profile playback and verify resource bounds, codec failure recovery, malformed input and long-running playback.
5. Package a self-contained desktop distribution, account for FFmpeg and its licensing/runtime libraries, complete release builds, signing/notarization as applicable, and installation/launch acceptance. No production-ready claim until these checks pass.
6. Only then investigate headset feasibility and implement/validate optional headset support.

## Current desktop increment

- Playlist execution now matches the source stack machine: exhausted subroutines hold without restarting; recursion is bounded; handoffs reset the clock rather than carrying overflow. Immediate zero-duration cycles produce an actionable error instead of hanging.
- Recursive JSON schema/type/enum/color/path validation rejects malformed inputs. Comment keys are ignored. Missing programs, empty maps, invalid branches, variable defaults and weighted fallback rules follow the source repair behavior. Missing numeric/color fields still use protobuf-style zero defaults.
- Theme discovery no longer expands explicit weights when auto-discovery is disabled. Matching nonempty theme directories convert explicit pools into scans. Scanned phrases uppercase and split near the middle space.
- Named ancestor image registers resolve to their owning pattern; sampled ramp segments have independent register scopes.
- Custom-pattern editor supports recipe copying, validation, source editing, enabled/weight/pin controls, preview and save with collision-free filenames.
- Playlist editor supports standard items, durations, ordered/duplicate subroutine children, weighted conditional branches, channel audio play/stop/fade/loop cues, entry points and reference-preserving rename.
- Native color pickers avoid persisting incomplete typed hex colors. Program selection remains effective as a runtime override until the next playlist item, with a Follow Playlist action.
- Recorded audio conversions are queued in cue order. Canceled session work and stale theme-audio conversion results are prevented from changing new playback state.
- Lint and archive export run before SwiftUI/Core Audio initialization.
- 26 core tests pass, including the original repository session fixture, malformed-schema cases, repairs, exhausted/recursive subroutines, register scopes, pattern save/rename/collision behavior and playlist rename.
- Optimized Xcode Release build succeeds for arm64 and x86_64 using an isolated copy of the same project. Xcode reports only the optional AppIntents metadata-extraction notice; no AppIntents dependency is needed by the app. Signing was disabled for verification.
- Native app build passes without compiler warnings. Headless lint, ZIP integrity and live status/pause/resume/visual/screenshot/hide/show/overlay smoke checks pass. Graphical editor interaction and audible output remain unverified by direct user/GUI acceptance.

## Rollback

Use Git history to compare increments and restore specific files from a save point on a separate branch. Keep session backups before editing: autosave writes the loaded session. JSON writes are atomic per file; assets and pattern files are separate transactions. Do not overwrite or delete the source checkout. No push, deployment, release tag, or distribution signing has been performed.
