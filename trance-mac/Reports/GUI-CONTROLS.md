# GUI controls overhaul — 2026-10-02

Version 0.2.0 organizes controls into Playback, Picture & text, Sound, Media libraries, Playlist, Saved programs, Custom patterns, Playlist conditions and Session files. Playback and sound buttons show their actions in words; a persistent status panel shows the current program, visual and selection mode. Controls explain units, automatic selection, temporary choices and saved settings. Save feedback and timestamps make changes observable.

Media libraries support file/folder pickers and individual phrase editors. Program drafts survive page changes. Synthesized tones show pitch, stereo difference, pulse and volume units. Inactive legacy display/headset settings remain preserved with an explicit compatibility explanation.

## Verification

- 33 Swift core tests passed.
- Three native audio acceptance tests passed during this overhaul: synthesized signal and mute/pause behavior, recorded playback and codec conversion. Audio engine implementation is unchanged.
- Final native UI acceptance passed with zero failures. It clicked pause/resume, sound on/mute, exclusive visual selection, manual visual playback and automatic selection, spiral reversal, tone enable/add/disable, and program copying. It read the saved JSON to verify applicable changes and checked draft preservation across pages.
- The retained window capture contains rendered colored pixels from generated test media.
- Final universal Release build passed for Intel and Apple Silicon. The self-contained local package is Apple Silicon/macOS 27 because the approved installed FFmpeg requires that platform.

Evidence: `gui-controls-results.json`, `gui-controls.png`, `gui-playback.png`; final local result bundle `/private/tmp/trance-controls-acceptance-final.xcresult`. Core log `/private/tmp/trance-controls-core-tests.log`; final Release log `/private/tmp/trance-controls-release-final.log`.

These checks cover the listed interactions, not exhaustive GUI coverage, human listening assessment or complete source feature parity. Headset implementation remains deferred. Local packaging uses ad-hoc signing and is not notarized.
