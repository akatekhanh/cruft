# Contributing to Cruft

Thanks for looking. This is a small, opinionated project — the fastest way to
get a change merged is to know what it's opinionated *about*.

## Before you write code

Open an issue first for anything bigger than a bug fix. That's not
bureaucracy: most of the design decisions here are deliberate and documented
(see [docs/DESIGN.md](docs/DESIGN.md)), and it's no fun to write a PR only to
learn the behaviour was intentional.

## The rules a PR has to respect

These are the product, not preferences. A change that breaks one of them will
be turned down however good the code is:

1. **Nothing is cleaned without an explicit click.** No auto-clean, no
   "optimize on launch", no scheduled sweeps.
2. **Only Safe *and* recoverable items are pre-selected.** If an item can't be
   restored from the Trash, it does not arrive pre-ticked — no matter how
   harmless it is to delete.
3. **Cleaning means the Trash** (`FileManager.trashItem`). The one exception is
   Docker, which has no trash: those categories are declared
   `removal: .external`, and every piece of UI text about them says the removal
   is permanent. If you add another external-tool integration, it follows the
   same rule.
4. **Say what happens after cleaning, in plain language.** Every category has a
   `consequence` string. "Frees up space" is not a consequence; "Next build of
   each project takes longer, one time" is.
5. **No dark patterns.** No urgency copy, no red totals, no health scores, no
   fake progress, no "your Mac is at risk". If a design makes the user anxious
   to make them click, it's wrong.
6. **Scanners never mutate the disk.** They read. Cleaning happens in one place.
7. **A folder's name is not evidence of what's inside it.** Never add a path
   because it contains "cache" or "tmp". `~/.gemini/tmp` holds real conversation
   checkpoints; Slack's message store sits next to its cache folders; Raycast
   keeps clipboard history inside its `Caches` bundle. Point at the exact
   subfolder you have verified, and if you can't reach it without a glob the
   scanners don't support, leave it out rather than approximate.
8. **Respect iCloud.** A synced file deleted here disappears from the user's
   other devices, so items under a File-Provider-managed folder are flagged in
   the UI and excluded from quick clean. Note that the ubiquity APIs report
   nothing for `~/Desktop` even when it *is* synced — see
   `FSHelpers.isCloudManaged` for why and what to check instead.

## Adding a category

Most contributions are "please also clean X". That's usually three small edits:

1. `Sources/CruftCore/Catalog.swift` — add the `CleanCategory` (id, plain
   `detail`, honest `consequence`, a risk level, an SF Symbol) and put its id
   in the roles it belongs to.
2. `Sources/CruftInfra/CruftInfraFactory.swift` — wire the id to a scanner.
   Reuse an existing one if you can: whole-directory, directory-children,
   name-pattern, aged-files, large-files, or composite.
3. `Sources/CruftChecks/main.swift` — the catalog checks are exhaustive, so
   they'll tell you what you forgot.

Pick the risk level honestly: **Safe** = regenerates itself with no user-visible
loss · **Worth a look** = safe but has a real cost (re-download, rebuild,
re-login) · **Risky** = actual user data.

## Running things

```sh
swift build                 # build
swift run CruftChecks       # the full check suite — no Xcode needed
swift test                  # same assertions via Swift Testing (needs Xcode)
swift run CruftApp          # run the app
./scripts/make-app.sh       # release bundle → dist/Cruft.app
CRUFT_SNAPSHOT_DIR=docs/screenshots swift run CruftApp   # regenerate screenshots
```

`swift run CruftChecks` must pass before you open a PR. It's the same suite CI
runs, and it needs nothing but the Command Line Tools.

## Style

Match the file you're editing. A few conventions worth naming:

- Comments explain **why**, not what. If a line needs a comment to say what it
  does, the line usually needs rewriting instead.
- Domain code (`CruftCore`) imports Foundation and nothing else. It never
  touches the filesystem — that's `CruftInfra`.
- User-facing strings are plain English a non-developer can read. No jargon in
  the UI, even when the thing being cleaned is developer-only.

## Commits and PRs

Small and focused beats large and thorough. Describe what changes for the user,
not which files you touched — the diff already says that. If your change is
visual, include a before/after screenshot.
