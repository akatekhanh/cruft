# Changelog

Notable changes, newest first. Versions follow [SemVer](https://semver.org).
Per-release details are also generated from merged pull requests on the
[Releases page](https://github.com/akatekhanh/sweep/releases).

## [Unreleased]

## [0.1.0] — 2026-09-09

First public release.

### Scanning
- Role profiles: Developer, Designer/Artist, Video creator, Office work,
  Marketing, Everyday use — each scans only what's relevant to that work.
- **Smart Clean**: one tab that looks at every category.
- **Overview** tab: machine name, chip, RAM, macOS version, and a stacked
  storage breakdown (Apps · App data & caches · Documents · Media ·
  Downloads & Desktop · Other · Free).
- Docker, scanned granularly through `docker system df` when the daemon is
  running: build cache and dangling images (Safe), stopped containers and
  unused images (Worth a look), unused volumes (Risky). When Docker isn't
  running, only the whole virtual disk file is offered.
- Local AI model stores: Ollama, LM Studio, Hugging Face, PyTorch, Whisper.
- Developer caches (Xcode DerivedData, iOS device support, simulators, npm/
  yarn/pnpm, pip, Homebrew, CocoaPods, Gradle/Maven), creative caches (Adobe
  media cache, Final Cut render files, Sketch/Figma, fonts), browser and
  meeting-app caches, old downloads, screenshots, screen recordings, Mail
  attachment cache, large files, iOS backups, Trash.

### Cleaning
- Everything goes to the Trash via `FileManager.trashItem` and stays
  restorable. Docker objects are the single documented exception: they are
  removed by Docker itself, permanently, and every piece of UI text about them
  says so.
- **Quick clean**: one button that cleans every Safe, Trash-recoverable item
  found. It is the only bulk control — there is no "select all".
- Pre-selection is Safe **and** recoverable, so nothing without an undo is ever
  ticked for you.

[Unreleased]: https://github.com/akatekhanh/sweep/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/akatekhanh/sweep/releases/tag/v0.1.0
