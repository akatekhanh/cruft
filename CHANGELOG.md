# Changelog

Notable changes, newest first. Versions follow [SemVer](https://semver.org).
Per-release details are also generated from merged pull requests on the
[Releases page](https://github.com/akatekhanh/sweep/releases).

## [Unreleased]

### Added
- **Leftovers from deleted apps**: finds `~/Library` data belonging to apps that
  are no longer installed, by matching bundle-identifier-shaped folder names
  against installed *and* running apps. Deliberately conservative — Apple ids,
  helpers of live apps, updaters (Keystone, GoogleUpdater, Sparkle, Edge) and
  anything under 1 MB are never reported.
- **"Unused N months" badge** on items nothing has read in a while, from the
  filesystem access date. A recent read beats an old write, so a long-lived
  cache still in use is not flagged.
- **Docker volumes now show their Compose project** (`myproject / pgdata`)
  instead of a 64-character hash; anonymous volumes say so and are abbreviated.
- `SWEEP_LIVE=1 swift run SweepChecks` prints a real scan of the current
  machine — the only way to judge a scanner's false-positive rate before
  shipping it. (It caught GoogleUpdater being mislabelled as a leftover.)

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
