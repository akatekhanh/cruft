# Sweep — Storage cleaner for every kind of Mac user

## 1. Product concept

One-click **Scan & Review** (never auto-clean). User picks a **role profile** at first
launch; the app scans only categories relevant to that role, then presents results
grouped by **risk level** for review before anything is moved to Trash.

**Safety invariants (non-negotiable):**
- Nothing is ever deleted permanently. Cleaning = `FileManager.trashItem` (recoverable).
- Nothing is pre-selected except `safe` items. `review`/`risky` are opt-in per item.
- Honest, calm language. No fake urgency, no red scare numbers, no auto-clean.

## 2. Role profiles (6)

| id | Name | Icon (SF Symbol) | Categories |
|----|------|------------------|-----------|
| developer | Developer | hammer.fill | xcode-derived, device-support, simulators, npm-cache, pip-cache, brew-cache, cocoapods-cache, gradle-cache, docker-data, user-caches, logs, trash |
| artist | Designer / Artist | paintpalette.fill | adobe-media-cache, font-caches, sketch-cache, user-caches, large-files, old-downloads, trash |
| video | Video / Content Creator | video.fill | adobe-media-cache, fcp-render, screen-recordings, large-files, old-downloads, user-caches, trash |
| office | Office worker | doc.text.fill | old-downloads, mail-downloads, browser-caches, desktop-screenshots, user-caches, logs, trash |
| marketing | Marketing | megaphone.fill | browser-caches, zoom-teams-cache, old-downloads, desktop-screenshots, large-files, user-caches, trash |
| general | Everyday user | person.fill | user-caches, logs, browser-caches, old-downloads, trash, large-files, ios-backups |

## 3. Categories & risk model

RiskLevel: `safe` (green — regenerated automatically, zero loss) ·
`review` (amber — safe but has a cost: re-download, rebuild, re-login) ·
`risky` (red — real potential data loss, but big space win; explicit opt-in).

Every category carries two plain-language strings: `detail` ("what this is") and
`consequence` ("what happens if you clean it"). No jargon.

A category also declares **how** its items leave: `removal: .trash` (the default
— recoverable) or `.external`, meaning another tool owns the data and removal is
permanent. Only Docker is `.external`. Two consequences fall out of that flag,
both enforced by tests: such items are never pre-selected even at `safe` risk,
and the commit button reads *Clean X* rather than *Move X to Trash* whenever one
is selected.

Items also carry `lastAccessed`, and the UI shows an "unused N months" badge
past three months. The access date is the useful one: a cache is written once and
read for years, so a recent read means it's live regardless of its age.

### iCloud

`isCloudManaged` marks items iCloud syncs. This is a third axis alongside risk
and removal method, because it changes the *scope* of a deletion rather than its
severity: trashing a synced file removes it from every device on the account.
Such items get a badge, get their own consequence line, and are excluded from
quick clean and from the default selection.

Detecting them is not what the documentation suggests. With "Desktop & Documents
Folders" enabled, `~/Desktop` is a firmlink to the real iCloud location, and
`isUbiquitousItemKey` / `ubiquitousItemDownloadingStatusKey` both report nil for
that path — only `~/Library/Mobile Documents/com~apple~CloudDocs/Desktop`
answers true (verified on macOS 26). Sweep therefore also treats
`~/Desktop`/`~/Documents` as cloud-managed when the matching folder exists under
`com~apple~CloudDocs`, which iCloud creates exactly when that sync is on.

### A pattern to avoid

At least one popular open-source cleaner deletes `History`, `Cookies` and
`Web Data` from a browser profile under the heading of clearing its cache. That
is browsing history and login state, not cache. Nothing in Sweep may point at a
path like that: if cleaning it would log the user out or lose their history, it
is not a cache, whatever folder it lives in.

| id | risk | paths (expand ~) |
|----|------|------------------|
| trash | safe | ~/.Trash |
| logs | safe | ~/Library/Logs |
| user-caches | review | ~/Library/Caches (children as items) |
| xcode-derived | safe | ~/Library/Developer/Xcode/DerivedData |
| device-support | review | ~/Library/Developer/Xcode/iOS DeviceSupport |
| simulators | review | ~/Library/Developer/CoreSimulator/Caches, .../Devices unavailable |
| npm-cache | safe | ~/.npm, ~/Library/Caches/Yarn, ~/Library/pnpm/store |
| pip-cache | safe | ~/Library/Caches/pip, ~/.cache/pip |
| brew-cache | safe | ~/Library/Caches/Homebrew |
| cocoapods-cache | safe | ~/Library/Caches/CocoaPods |
| gradle-cache | review | ~/.gradle/caches, ~/.m2/repository |
| rust-cache | review | ~/.cargo/registry, ~/.rustup/toolchains, ~/.cargo/git |
| go-cache | safe | ~/go/pkg/mod, ~/Library/Caches/go-build |
| editor-caches | safe | Code/Cursor/Windsurf `Cache`, `CachedData`, `CachedExtensionVSIXs`; ~/Library/Caches/JetBrains, ~/Library/Logs/JetBrains — cache-shaped subfolders only, never settings or extensions |
| chat-app-caches | review | Slack `Cache` + `Service Worker/CacheStorage` + `Code Cache`, Discord `Cache`/`Code Cache`/`GPUCache`, Signal `Cache`. Message stores are siblings of these and never listed. Telegram is omitted: its media cache sits behind a per-account path these scanners can't glob |
| container-vm-disks | risky | ~/.colima/_lima, ~/.lima, ~/.local/share/containers/podman/machine, ~/.orbstack/data, rancher-desktop/lima, ~/.docker/desktop/vms. **Usually the largest single object on a dev Mac** (76 GB on the author's). Grow-only: pruning Docker frees space *inside* the guest, not on the host — reclaiming it means recreating the VM |
| docker-build-cache | safe · **external** | `docker system df -v` → BuildCache not in use (one aggregate item; `docker builder prune`) |
| docker-dangling-images | safe · **external** | untagged images with no container |
| docker-stopped-containers | review · **external** | containers whose status is Exited/Created/Dead |
| docker-unused-images | review · **external** | tagged images with no container (sized by UniqueSize — what deleting really frees) |
| docker-unused-volumes | risky · **external** | volumes with `Links == 0`; labelled `project / volume` from Compose labels |
| docker-data | risky | ~/Library/Containers/com.docker.docker/Data/vms — **only when the daemon is unreachable**, otherwise the five categories above cover the same bytes |
| ai-models | review | ~/.ollama/models (whole), ~/.cache/huggingface/hub, ~/.lmstudio/models, ~/.cache/lm-studio/models, ~/.cache/torch, ~/.cache/whisper |
| orphaned-app-data | review | bundle-id-shaped folders in ~/Library/{Application Support, Caches, Containers, Saved Application State, HTTPStorages, WebKit} with no installed or running app — excludes `com.apple.*`, helpers of live apps, updaters, and anything under 1 MB |
| adobe-media-cache | review | ~/Library/Application Support/Adobe/Common/Media Cache Files, .../Media Cache |
| font-caches | safe | ~/Library/Application Support/Adobe/CoreSync? no — use ~/Library/Caches/com.apple.FontRegistry |
| sketch-cache | safe | ~/Library/Caches/com.bohemiancoding.sketch3, ~/Library/Caches/com.figma.Desktop |
| fcp-render | review | ~/Movies/*.fcpbundle/**/Render Files (top-level bundles only) |
| screen-recordings | review | ~/Desktop + ~/Movies files matching "Screen Recording*" |
| browser-caches | review | Chrome/Safari/Firefox/Edge cache dirs |
| zoom-teams-cache | review | ~/Library/Application Support/zoom.us/AutoUpdater + data, Teams caches |
| old-downloads | review | ~/Downloads items not modified in 90 days |
| desktop-screenshots | review | ~/Desktop files matching "Screenshot*"/"Ảnh chụp*" |
| mail-downloads | review | ~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads |
| large-files | risky | files > 500 MB in ~/Downloads, ~/Desktop, ~/Documents, ~/Movies (depth ≤ 3) |
| ios-backups | risky | ~/Library/Application Support/MobileSync/Backup (each backup = item) |

## 4. UX flow & layout (research-informed)

1. **Onboarding sheet** (first launch): "Who is this Mac for?" — grid of 6 role cards
   (icon, name, one-line description). Changeable later from toolbar.
2. **Dashboard** (pre-scan): disk gauge (used/free from FileManager), current role chip,
   one big `Scan` button. Matter-of-fact copy.
3. **Scanning**: determinate progress by category, live running total found.
4. **Results** — `NavigationSplitView`:
   - Sidebar: categories with size + risk dot, "All results" on top.
   - Detail: sections ordered Safe → Review → Risky. Each row: SF icon, name,
     `consequence` subtitle, size (monospaced digits), checkbox.
     Safe pre-checked. Risky section collapsed by default behind a disclosure
     ("Show risky items") — progressive disclosure, no triple-confirm.
   - Footer bar: "Selected: X GB" + primary button **"Move X GB to Trash"**.
5. **Done**: calm summary "Moved X GB to Trash. You can restore anything from the
   Trash." + "Open Trash" secondary button.

## 5. Visual design

- Native macOS look: SF Symbols, system materials, automatic dark mode.
- Accent: teal `Color(red:0.06,green:0.65,blue:0.63)` (light) — friendly, not alarming.
- Risk semantics only: `.green`/`.orange`/`.red` system colors, used as small dots &
  badges, never full-row fills. Neutral text via `.primary`/`.secondary`.
- Typography: system font; sizes via `.title2/.headline/.subheadline/.caption`;
  numbers `.monospacedDigit()`.
- Avoid: red totals, urgency copy, auto-checked risky items, fake "health scores".

## 6. Architecture — Clean Architecture, 3 targets

```
SweepCore   (domain: entities, ports, use cases, catalog — Foundation only)
SweepInfra  (adapters: file-system scanners, trash service — depends on SweepCore)
SweepApp    (SwiftUI + MVVM view models — depends on Core + Infra; DI at composition root)
Tests/SweepCoreTests (Swift Testing)
```

Dependency rule: inward only. UI knows use cases, never FileManager. Scanners are
`CategoryScanner` port implementations injected into `ScanUseCase`.
