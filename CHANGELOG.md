# Changelog

Notable changes, newest first. Versions follow [SemVer](https://semver.org).
Per-release details are also generated from merged pull requests on the
[Releases page](https://github.com/akatekhanh/sweep/releases).

## [Unreleased]

### Fixed
- **iCloud-synced files are now identified and flagged.** Sweep listed files in
  `~/Desktop` and `~/Documents` without knowing iCloud syncs them, so trashing
  one would have removed it from the user's other devices with no warning. Such
  items now carry a badge and their own consequence line, and are excluded from
  quick clean and the default selection. Detection can't rely on the documented
  ubiquity keys: with "Desktop & Documents Folders" enabled, `~/Desktop` is a
  firmlink and those keys report nil for it — only the
  `~/Library/Mobile Documents` path answers true.

### Added
- **Container VM disks** (Colima, Lima, Podman, OrbStack, Rancher Desktop).
  On a Mac that runs containers in a VM this file is routinely the biggest
  object on the disk — 76 GB on the machine this was developed on — and no
  cache cleaner sees it, because it is one opaque file rather than a cache
  directory. It is also grow-only: `docker system prune` frees space inside
  the guest but never shrinks the host file, which is why pruning 30 GB can
  change nothing on your disk. Reported as Risky, with that distinction
  spelled out instead of a one-click fix.
- **Rust crates & toolchains** (`~/.cargo/registry`, `~/.rustup/toolchains`,
  `~/.cargo/git`), **Go modules & build cache**, **editor caches** (VS Code,
  Cursor, Windsurf, JetBrains — the cache subfolders only, never settings or
  extensions), and **chat app caches** (Slack, Discord, Signal — cache folders
  only, never message stores).
- `uv`'s cache joins the Python package category, which is where most of the
  gigabytes now live on a modern Python machine.
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
