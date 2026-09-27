# Changelog

Notable changes, newest first. Versions follow [SemVer](https://semver.org).
Per-release details are also generated from merged pull requests on the
[Releases page](https://github.com/akatekhanh/cruft/releases).

## [Unreleased]

### Added
- **Risk sub-tabs on the results screen.** Safe, Worth a look and Risky were
  stacked in one scrolling list, so the three colours mixed and a tier could not
  be reviewed on its own. A segmented control now offers **All** (grouped, as
  before) plus one tab per tier with its item count. A tier tab shows a header
  that spells out what cleaning that tier costs, totals, and a **Select all**
  for Safe and Worth a look. Select all skips items that a bulk tick should never
  reach — permanent removals (Docker, the Trash itself) and iCloud-synced files —
  and says how many were skipped; the Risky tier offers no bulk button at all.

### Fixed
- **Cleaning the Trash now actually frees space.** Items in `~/.Trash` were
  "cleaned" by moving them to the Trash, which macOS treats as a no-op that
  reports success: nothing was deleted, the Done screen claimed the bytes, and a
  rescan listed the same items. The category is now a permanent removal with its
  own cleaner, refuses anything outside `~/.Trash`, and stays out of Quick clean
  and the default selection like every other removal with no undo.
- **The same folder no longer appears under two categories.** Go, uv, Poetry,
  JetBrains, Zoom, Teams and several browser caches were listed both by their
  own category and by App caches, doubling totals and giving SwiftUI duplicate
  row ids. The exclusion list is complete again, and the scan now assigns every
  path to the first category that reports it, so no future category can
  reintroduce the problem.
- **Leftovers from deleted apps re-check what is installed on every scan.** The
  installed-apps index was built once, on the main thread, at launch; an app
  installed or launched afterwards was reported as gone on the next rescan. The
  index is now rebuilt inside the scan, off the main actor.
- **Old CLI tool versions never offers a staged update.** A release the tool has
  already downloaded but not switched to sorts newer than the active one; it was
  listed as safe cruft, and deleting it would have undone the pending update.
  Versions newer than the launcher's target are now skipped.
- **Docker results reflect what was just removed.** The inventory cache is
  dropped after every removal, so a rescan within its 15-second window no longer
  lists the deleted object and then fails to remove it a second time.
- **Docker image sizes are honest.** Untagged images were sized with shared
  layers included; an image carrying several tags was listed once per tag and
  removed by a single tag, which only untags. Images are now grouped by ID, sized
  by their unique bytes, and removed with all tags.
- **A chatty Docker daemon can no longer stall the scan.** stdout and stderr were
  drained one after the other; more than 64 KB of warnings on stderr blocked the
  read until the two-minute watchdog fired. Both pipes are read concurrently.
- **Old downloads considers when a file was last opened,** not only when it was
  last modified, so a PDF downloaded months ago and read yesterday is not
  offered.
- The scan progress bar can no longer step backwards when two categories finish
  back to back.
- **"Other" no longer swallows the disk.** The Overview measured five slices and
  left 145 GB of 189 GB used in a wedge labelled "Other" — the same thing macOS's
  own storage screen does, and just as useless. Two new slices account for most
  of it: **Developer data** (every dot-directory in the home folder plus `~/go`
  and Homebrew — `~/.colima` alone was 81 GB) and **System temp** (this user's
  tree under `/private/var/folders`). "Other" is now 46 GB and the chart explains
  in words that what's left is macOS itself.
- **APFS clones no longer inflate the totals.** Measuring the temp tree produced
  198 GB accounted for against 189 GB actually used. The cause: 39 Chrome
  code-signing clones, 1.4 GB each by every measurement macOS offers, sharing
  every block with the installed app. Deleting one freed exactly zero bytes. The
  clone directory is now excluded, and no category offers those clones — one that
  did would have promised 54 GB and delivered nothing.
- **iCloud-synced files are now identified and flagged.** Cruft listed files in
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
- **Old CLI tool versions**: self-updating tools like Claude Code install each
  release beside the last and never clean up — 1.19 GB in six stale copies on
  the machine this was written on, at ~200 MB per release. The live version is
  identified by resolving the launcher symlink rather than by timestamp,
  because these tools stage the next release *before* switching the symlink; a
  "keep the newest" rule would delete the binary you are running. If the
  launcher can't be resolved, nothing in that location is offered at all.
- **Rust crates & toolchains** (`~/.cargo/registry`, `~/.rustup/toolchains`,
  `~/.cargo/git`), **Go modules & build cache**, **editor caches** (VS Code,
  Cursor, Windsurf, JetBrains — the cache subfolders only, never settings or
  extensions), and **chat app caches** (Slack, Discord, Signal — cache folders
  only, never message stores).
- More paths for categories that already existed: Bun's install cache
  (JavaScript), Poetry artifacts and pre-commit environments (Python — but
  never Poetry's `virtualenvs`, which hold interpreters in use), Gradle
  distributions, and Brave / Arc / Opera / Vivaldi / Chromium browser caches.
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
- `CRUFT_LIVE=1 swift run CruftChecks` prints a real scan of the current
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

[Unreleased]: https://github.com/akatekhanh/cruft/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/akatekhanh/cruft/releases/tag/v0.1.0
