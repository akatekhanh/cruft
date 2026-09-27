// CruftChecks — dependency-free verification runner.
// `swift test` needs Xcode's XCTest/Testing runtime, which Command Line Tools
// lack; this executable runs the same assertions via `swift run CruftChecks`.
import Foundation
import CruftCore
import CruftInfra

var passed = 0, failed = 0
@MainActor func expect(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { passed += 1 } else { failed += 1; print("  FAIL(line \(line)): \(msg)") }
}
func section(_ name: String) { print("• \(name)") }

func item(_ path: String, _ size: Int64, _ cat: String, _ risk: RiskLevel) -> ScanItem {
    ScanItem(url: URL(fileURLWithPath: path), displayName: (path as NSString).lastPathComponent,
             sizeBytes: size, categoryID: cat, risk: risk)
}
func cat(_ id: String, _ risk: RiskLevel) -> CleanCategory {
    CleanCategory(id: id, name: id.uppercased(), detail: "d", consequence: "c",
                  risk: risk, systemImage: "folder")
}
struct FakeScanner: CategoryScanner {
    let category: CleanCategory
    let found: [ScanItem]
    func scan() async -> [ScanItem] { found }
}
final class FakeTrash: TrashService, @unchecked Sendable {
    var trashed: [URL] = []; var failOn: Set<String> = []
    func moveToTrash(_ url: URL) throws {
        if failOn.contains(url.path) {
            throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "nope"])
        }
        trashed.append(url)
    }
}
func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory
        .appendingPathComponent("CruftChecks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}
@discardableResult
func write(_ dir: URL, _ name: String, bytes: Int) throws -> URL {
    let u = dir.appendingPathComponent(name)
    try Data(repeating: 0x41, count: bytes).write(to: u)
    return u
}

// ── Catalog integrity ────────────────────────────────────────────────
section("Catalog integrity")
let ids = Catalog.categories.map(\.id)
expect(Set(ids).count == ids.count, "category ids unique")
expect(Set(Catalog.roles.map(\.id)).count == Catalog.roles.count, "role ids unique")
expect(Catalog.roles.count == 6, "6 role profiles")
for role in Catalog.roles {
    expect(!role.categoryIDs.isEmpty, "role \(role.id) non-empty")
    for cid in role.categoryIDs {
        expect(Catalog.category(cid) != nil, "role \(role.id) → unknown category \(cid)")
    }
    expect(role.categoryIDs.contains { Catalog.category($0)?.risk == .safe },
           "role \(role.id) has ≥1 safe category")
}
for c in Catalog.categories {
    expect(!c.detail.isEmpty && !c.consequence.isEmpty && !c.systemImage.isEmpty,
           "category \(c.id) has plain-language copy + icon")
}

// ── RiskLevel ────────────────────────────────────────────────────────
section("RiskLevel")
expect(RiskLevel.safe < .review && RiskLevel.review < .risky, "ordering")
expect(RiskLevel.allCases.sorted() == [.safe, .review, .risky], "allCases sorted")
for r in RiskLevel.allCases { expect(!r.label.isEmpty, "label for \(r)") }

// ── SelectionPolicy ──────────────────────────────────────────────────
section("SelectionPolicy")
let selResults = [
    CategoryScanResult(category: cat("a", .safe),
                       items: [item("/x1", 100, "a", .safe), item("/x2", 50, "a", .review)]),
    CategoryScanResult(category: cat("b", .risky), items: [item("/y1", 999, "b", .risky)]),
]
let defSel = SelectionPolicy.defaultSelection(in: selResults)
expect(defSel == ["/x1"], "default selection = safe items only")
expect(SelectionPolicy.selectedBytes(in: selResults, selection: defSel) == 100, "selectedBytes")
expect(SelectionPolicy.selectedBytes(in: selResults,
       selection: ["/x1", "/x2", "/y1"]) == 1149, "selectedBytes all")
let sorted = CategoryScanResult(category: cat("a", .safe),
    items: [item("/1", 5, "a", .safe), item("/2", 500, "a", .safe), item("/3", 50, "a", .safe)])
expect(sorted.items.map(\.sizeBytes) == [500, 50, 5] && sorted.totalBytes == 555,
       "items sorted desc, total sums")

// ── ScanUseCase ──────────────────────────────────────────────────────
section("ScanUseCase")
let scanUC = ScanUseCase(scanners: [
    FakeScanner(category: cat("small", .safe), found: [item("/s", 10, "small", .safe)]),
    FakeScanner(category: cat("empty", .safe), found: []),
    FakeScanner(category: cat("big", .safe), found: [item("/b", 1000, "big", .safe)]),
])
let role = RoleProfile(id: "r", name: "R", blurb: "", systemImage: "person",
                       categoryIDs: ["small", "empty", "big"])
let scanResults = await scanUC.run(for: role) { _ in }
expect(scanResults.map(\.id) == ["big", "small"], "empty filtered, sorted by size desc")
let roleOne = RoleProfile(id: "r1", name: "R", blurb: "", systemImage: "person",
                          categoryIDs: ["small"])
expect(scanUC.scanners(for: roleOne).map(\.category.id) == ["small"], "role filters scanners")
nonisolated(unsafe) var updates: [ScanProgress] = []
_ = await scanUC.run(for: roleOne) { updates.append($0) }
expect(updates.first?.finished == 0 && updates.first?.total == 1, "progress starts 0/1")
expect(updates.last?.finished == 1 && updates.last?.bytesFoundSoFar == 10, "progress ends 1/1, bytes")

// ── CleanUseCase ─────────────────────────────────────────────────────
section("CleanUseCase")
let fakeTrash = FakeTrash(); fakeTrash.failOn = ["/fail"]
let report = CleanUseCase(trash: fakeTrash).run(items: [
    item("/ok1", 100, "a", .safe), item("/fail", 999, "a", .safe), item("/ok2", 50, "a", .safe)])
expect(report.freedBytes == 150 && report.cleanedCount == 2, "freed bytes + count")
expect(report.failures.count == 1 && report.failures[0].item.id == "/fail", "failure collected")
expect(fakeTrash.trashed.map(\.path) == ["/ok1", "/ok2"], "only ok items trashed")

// ── ByteText ─────────────────────────────────────────────────────────
section("ByteText")
expect(!ByteText.string(0).isEmpty && !ByteText.string(1_500_000_000).isEmpty, "formats")

// ── Infra: DirectoryChildrenScanner ─────────────────────────────────
section("DirectoryChildrenScanner")
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    try write(d, "a.txt", bytes: 100); try write(d, "b.txt", bytes: 250)
    try write(d, ".hidden", bytes: 50)
    let items = await DirectoryChildrenScanner(category: cat("t", .safe), roots: [d.path]).scan()
    expect(items.count == 2, "2 visible children (hidden skipped), got \(items.count)")
    expect(items.allSatisfy { $0.sizeBytes > 0 }, "sizes > 0")
    let excl = await DirectoryChildrenScanner(category: cat("t", .safe), roots: [d.path],
        excludedChildNameContains: ["a.txt"]).scan()
    expect(excl.count == 1, "exclusion filter works")
} catch { expect(false, "DirectoryChildrenScanner setup: \(error)") }

// ── Infra: AgedFilesScanner ─────────────────────────────────────────
section("AgedFilesScanner")
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    let old = try write(d, "old.txt", bytes: 10); try write(d, "new.txt", bytes: 10)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSinceNow: -200 * 86400)], ofItemAtPath: old.path)
    let items = await AgedFilesScanner(category: cat("t", .review), root: d.path,
                                       olderThanDays: 90).scan()
    expect(items.map(\.displayName) == ["old.txt"], "only old files, got \(items.map(\.displayName))")
} catch { expect(false, "AgedFilesScanner setup: \(error)") }

// ── Infra: NamePatternScanner ───────────────────────────────────────
section("NamePatternScanner")
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    try write(d, "Screenshot 2026.png", bytes: 10)
    try write(d, "screenshot lower.png", bytes: 10)
    try write(d, "photo.png", bytes: 10)
    let items = await NamePatternScanner(category: cat("t", .review), roots: [d.path],
                                         prefixes: ["Screenshot"]).scan()
    expect(items.count == 2, "case-insensitive prefix match, got \(items.count)")
} catch { expect(false, "NamePatternScanner setup: \(error)") }

// ── Infra: LargeFilesScanner ────────────────────────────────────────
section("LargeFilesScanner")
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    try write(d, "big.bin", bytes: 700_000); try write(d, "small.bin", bytes: 10)
    let items = await LargeFilesScanner(category: cat("t", .risky), roots: [d.path],
                                        minBytes: 500_000, maxDepth: 3).scan()
    expect(items.map(\.displayName) == ["big.bin"], "threshold respected")
    expect(items.allSatisfy { $0.risk == .risky }, "large files always risky")
} catch { expect(false, "LargeFilesScanner setup: \(error)") }

// ── Infra: Factory ──────────────────────────────────────────────────
section("CruftInfraFactory")
let all = CruftInfraFactory.makeAllScanners()
expect(all.count == Catalog.categories.count,
       "one scanner per category (\(all.count)/\(Catalog.categories.count))")
expect(all.map(\.category.id) == Catalog.categories.map(\.id), "factory order matches catalog")

// ── Infra: SystemTrashService (real, tiny temp file) ────────────────
section("SystemTrashService")
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    let f = try write(d, "cruft-check-trash-me.txt", bytes: 4)
    try SystemTrashService().moveToTrash(f)
    expect(!FileManager.default.fileExists(atPath: f.path), "file moved off original path")
} catch { expect(false, "trashItem threw: \(error)") }

// ── CleanUseCase: SpecialCleaner routing ────────────────────────────
section("SpecialCleaner routing")
final class FakeSpecial: SpecialCleaner, @unchecked Sendable {
    let categoryIDs: Set<String> = ["docker-x"]
    var cleaned: [String] = []
    func clean(_ item: ScanItem) throws { cleaned.append(item.id) }
}
let special = FakeSpecial()
let routeTrash = FakeTrash()
let routed = CleanUseCase(trash: routeTrash, specials: [special]).run(items: [
    item("/file", 100, "a", .safe),
    ScanItem(url: URL(string: "docker://local/image/abc")!, displayName: "abc",
             sizeBytes: 900, categoryID: "docker-x", risk: .safe),
])
expect(special.cleaned == ["/image/abc"], "docker item routed to special cleaner")
expect(routeTrash.trashed.map(\.path) == ["/file"], "file item still goes to Trash")
expect(routed.freedBytes == 1000 && routed.externallyRemovedBytes == 900,
       "external bytes reported separately")

// ── Docker: size parsing + df categorization ────────────────────────
section("DockerUsageParser")
expect(DockerUsageParser.parseSize("1.204GB") == 1_204_000_000, "GB decimal")
expect(DockerUsageParser.parseSize("63B") == 63, "bytes")
expect(DockerUsageParser.parseSize("10.5MB") == 10_500_000, "MB")
expect(DockerUsageParser.parseSize("2.1kB") == 2_100, "kB")
expect(DockerUsageParser.parseSize("N/A") == 0, "N/A → 0")
expect(DockerUsageParser.parseSize("12B (virtual 1.2GB)") == 12, "virtual suffix stripped")
expect(DockerUsageParser.parseSize(nil) == 0, "nil → 0")

let dfFixture = """
{"Images":[
  {"ID":"aaa111","Repository":"<none>","Tag":"<none>","Containers":"0","Size":"500MB","UniqueSize":"500MB"},
  {"ID":"bbb222","Repository":"postgres","Tag":"17","Containers":"0","Size":"600MB","UniqueSize":"400MB"},
  {"ID":"ccc333","Repository":"redis","Tag":"7","Containers":"1","Size":"100MB","UniqueSize":"100MB"}],
 "Containers":[
  {"ID":"ddd444","Names":"old-job","Image":"postgres:17","Status":"Exited (0) 2 days ago","Size":"63B"},
  {"ID":"eee555","Names":"live","Image":"redis:7","Status":"Up 3 hours","Size":"1MB"}],
 "Volumes":[
  {"Name":"orphan-vol","Links":"0","Size":"250MB"},
  {"Name":"used-vol","Links":"1","Size":"1GB"}],
 "BuildCache":[
  {"ID":"cache1","InUse":"false","Size":"300MB"},
  {"ID":"cache2","InUse":"true","Size":"999MB"}]}
"""
let buckets = DockerUsageParser.items(fromDF: dfFixture)
expect(buckets["docker-dangling-images"]?.count == 1, "1 dangling image")
expect(buckets["docker-unused-images"]?.map(\.displayName) == ["postgres:17"],
       "tagged unused image found; in-use image skipped")
expect(buckets["docker-unused-images"]?.first?.sizeBytes == 400_000_000,
       "unused image sized by UniqueSize (honest reclaim)")
expect(buckets["docker-stopped-containers"]?.count == 1
       && buckets["docker-stopped-containers"]?.first?.id.contains("ddd444") == true,
       "only the exited container")
expect(buckets["docker-unused-volumes"]?.map(\.displayName) == ["orphan-vol"],
       "only the unlinked volume")

// Volume naming: a hash tells the user nothing, so compose labels are used.
expect(DockerUsageParser.volumeLabel(
        name: "data-platform-core_spark_ivy",
        labels: "com.docker.compose.project=data-platform-core,com.docker.compose.volume=spark_ivy")
       == "data-platform-core / spark_ivy",
       "compose labels give a human-readable volume name")
let hashName = String(repeating: "a", count: 64)
expect(DockerUsageParser.volumeLabel(name: hashName, labels: "")
       == "Unnamed volume (aaaaaaaaaaaa…)",
       "anonymous volume is labelled and abbreviated")
expect(DockerUsageParser.volumeLabel(name: hashName,
                                     labels: "com.docker.compose.project=proj")
       == "proj / unnamed volume (aaaaaaaaaaaa…)",
       "anonymous volume still shows its project when known")
expect(DockerUsageParser.volumeLabel(name: "pgdata", labels: "") == "pgdata",
       "a plain named volume is left alone")
expect(DockerUsageParser.isAnonymousName("pgdata") == false, "named volume is not anonymous")
expect(DockerUsageParser.isAnonymousName(hashName), "64-hex name is anonymous")
expect(DockerUsageParser.parseLabels("a=1,b=2")["b"] == "2", "labels parse")
expect(DockerUsageParser.parseLabels("")["x"] == nil, "empty labels are harmless")
expect(DockerUsageParser.parseLabels("weird")["weird"] == nil, "a pair without = is skipped")
expect(buckets["docker-build-cache"]?.first?.sizeBytes == 300_000_000,
       "build cache sums only not-in-use entries")
expect(buckets["docker-unused-volumes"]?.first?.risk == .risky, "volumes stay risky")
let itemIDs = buckets.values.flatMap { $0 }.map(\.id)
expect(Set(itemIDs).count == itemIDs.count, "docker item ids unique")

// ── Docker: external removal is declared in the catalog ─────────────
section("Docker catalog honesty")
for cid in DockerUsageParser.categoryIDs {
    expect(Catalog.category(cid)?.removal == .external, "\(cid) declared external")
    expect(Catalog.category(cid)?.consequence.contains("not the Trash") == true,
           "\(cid) consequence admits it skips the Trash")
}
expect(DockerCleaner().categoryIDs == Set(DockerUsageParser.categoryIDs),
       "cleaner owns exactly the granular docker categories")
expect(Catalog.category("docker-data")?.removal == .trash, "whole-disk fallback stays trashable")

// ── Smart Clean + quick clean ───────────────────────────────────────
section("Smart Clean")
expect(Catalog.smartRole.categoryIDs == Catalog.categories.map(\.id),
       "smart role covers every category")
expect(Catalog.tabRoles.first?.id == "smart" && Catalog.tabRoles.count == 7,
       "tab roles = smart + 6 profiles")
expect(Catalog.role("smart")?.id == "smart", "role lookup resolves smart")
let quickResults = [
    CategoryScanResult(category: cat("logs", .safe), items: [
        item("/log1", 100, "logs", .safe), item("/old", 50, "logs", .review)]),
    CategoryScanResult(
        category: Catalog.category("docker-build-cache")!,
        items: [ScanItem(url: URL(string: "docker://local/build-cache/all")!,
                         displayName: "cache", sizeBytes: 999,
                         categoryID: "docker-build-cache", risk: .safe)]),
]
let quick = SelectionPolicy.quickCleanItems(in: quickResults)
expect(quick.map(\.id) == ["/log1"],
       "quick clean = safe AND trash-recoverable only (docker excluded)")
// A Safe-but-permanent item must never arrive pre-ticked: no undo, no default.
let quickDefault = SelectionPolicy.defaultSelection(in: quickResults)
expect(quickDefault == ["/log1"], "default selection excludes permanent removals")
expect(SelectionPolicy.selectedBytes(in: quickResults, selection: quickDefault) == 100,
       "headline selected bytes excludes docker bytes")

// ── iCloud-synced items are never swept along ───────────────────────
section("iCloud safety")
let cloudItem = ScanItem(url: URL(fileURLWithPath: "/Users/x/Desktop/report.key"),
                         displayName: "report.key", sizeBytes: 900, categoryID: "logs",
                         risk: .safe, isCloudManaged: true)
let localItem = ScanItem(url: URL(fileURLWithPath: "/Users/x/Library/Logs/app.log"),
                         displayName: "app.log", sizeBytes: 100, categoryID: "logs",
                         risk: .safe)
let cloudResults = [CategoryScanResult(category: cat("logs", .safe),
                                       items: [cloudItem, localItem])]
expect(SelectionPolicy.quickCleanItems(in: cloudResults).map(\.displayName) == ["app.log"],
       "quick clean skips iCloud items even at safe risk")
expect(SelectionPolicy.defaultSelection(in: cloudResults) == ["/Users/x/Library/Logs/app.log"],
       "default selection skips iCloud items too")
// Selecting one by hand still works — this is a default, not a prohibition.
expect(SelectionPolicy.selectedBytes(in: cloudResults,
        selection: ["/Users/x/Desktop/report.key"]) == 900,
       "a user can still choose an iCloud item deliberately")

// Detection on this machine must agree with what iCloud itself reports. The
// ubiquity keys return nil for ~/Desktop even when it is synced (the firmlink
// problem), so the check below is the one that has to hold.
let homeDir = FileManager.default.homeDirectoryForCurrentUser
let cloudDocs = homeDir.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
for folder in ["Desktop", "Documents"] {
    let synced = FileManager.default.fileExists(
        atPath: cloudDocs.appendingPathComponent(folder).path)
    let probe = homeDir.appendingPathComponent(folder).appendingPathComponent("some-file.txt")
    expect(FSHelpers.isCloudManaged(probe) == synced,
           "~/\(folder): isCloudManaged agrees with iCloud (synced=\(synced))")
}
// A cache path is never mistaken for a synced file.
expect(!FSHelpers.isCloudManaged(homeDir.appendingPathComponent("Library/Caches/x")),
       "caches are not reported as iCloud items")

// ── Orphaned app data: the false-positive rules ─────────────────────
section("OrphanedAppDataScanner")
let fakeIndex = InstalledAppsIndex(bundleIDs: ["com.acme.editor", "com.figma.desktop"])
func orphan(_ name: String) -> String? {
    OrphanedAppDataScanner.orphanedBundleID(forFolderName: name, index: fakeIndex)
}
expect(orphan("com.deadapp.thing") == "com.deadapp.thing", "leftover of a missing app is reported")
expect(orphan("com.acme.editor") == nil, "installed app is never reported")
expect(orphan("com.acme.editor.helper") == nil,
       "helper of an installed app survives (prefix match)")
expect(orphan("com.apple.Safari") == nil, "Apple ids are never touched")
expect(orphan("com.apple.dt.Xcode.something") == nil, "nested Apple ids either")
expect(orphan("Firefox") == nil, "plain folder names are not bundle ids")
expect(orphan("Google") == nil, "one-word vendor folders are not candidates")
expect(orphan("com.google") == nil, "two-label names are too generic to act on")
expect(orphan("My Cool App.stuff.here") == nil, "names with spaces are not bundle ids")
expect(orphan("com.deadapp.thing.savedState") == "com.deadapp.thing",
       "savedState suffix is stripped before matching")
expect(orphan("com.deadapp.thing.plist") == "com.deadapp.thing",
       "plist suffix is stripped before matching")
expect(orphan("com.microsoft.autoupdate.helper") == nil,
       "known non-app owners are excluded")
expect(orphan("com.google.keystone.agent") == nil, "updaters are excluded")
expect(OrphanedAppDataScanner.bundleID(fromFolderName: "com.a.b") == "com.a.b",
       "three-label name parses")

// The real index must at least know the apps that are running right now —
// otherwise every running app's data would look orphaned.
let realIndex = InstalledAppsIndex.current()
expect(!realIndex.bundleIDs.isEmpty, "installed-apps index is not empty")
expect(realIndex.isInstalled("com.apple.finder"), "Finder is seen as installed")

// End-to-end against a real directory tree: the rules above are only useful
// if the scanner actually finds the leftover and leaves the live app alone.
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    for folder in ["com.deadapp.gone", "com.acme.editor", "com.apple.Something", "PlainFolder"] {
        let sub = d.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write(sub, "blob.bin", bytes: 2_000_000)
    }
    // Below the floor: a tiny leftover is not worth asking about.
    let small = d.appendingPathComponent("com.deadapp.tiny")
    try FileManager.default.createDirectory(at: small, withIntermediateDirectories: true)
    try write(small, "x.bin", bytes: 1_000)

    let found = await OrphanedAppDataScanner(
        category: cat("orphaned-app-data", .review),
        roots: [d.path], minBytes: 1_000_000, index: fakeIndex
    ).scan()
    expect(found.map(\.displayName) == ["com.deadapp.gone"],
           "finds only the leftover of the uninstalled app, got \(found.map(\.displayName))")
    expect(found.first?.sizeBytes ?? 0 >= 2_000_000, "reports the real size")
} catch { expect(false, "OrphanedAppDataScanner live-tree setup: \(error)") }

// ── Idle age (last used) ────────────────────────────────────────────
section("monthsSinceLastUse")
func aged(_ days: Int) -> ScanItem {
    ScanItem(url: URL(fileURLWithPath: "/tmp/x"), displayName: "x", sizeBytes: 1,
             categoryID: "a", risk: .safe,
             lastModified: Date(timeIntervalSinceNow: -Double(days) * 86400),
             lastAccessed: nil)
}
expect(aged(0).monthsSinceLastUse == 0, "fresh item = 0 months")
expect(aged(95).monthsSinceLastUse == 3, "95 days ≈ 3 months")
expect(aged(400).monthsSinceLastUse == 13, "400 days ≈ 13 months")
expect(ScanItem(url: URL(fileURLWithPath: "/tmp/y"), displayName: "y", sizeBytes: 1,
                categoryID: "a", risk: .safe).monthsSinceLastUse == nil,
       "no dates → unknown, not zero")
// Access date wins when it is newer than the modification date: a cache
// written long ago but read yesterday is in active use.
let readRecently = ScanItem(url: URL(fileURLWithPath: "/tmp/z"), displayName: "z",
                            sizeBytes: 1, categoryID: "a", risk: .safe,
                            lastModified: Date(timeIntervalSinceNow: -400 * 86400),
                            lastAccessed: Date())
expect(readRecently.monthsSinceLastUse == 0, "recent read beats an old write")

// ── Old CLI versions: never delete the running binary ───────────────
section("CLIVersionsScanner")
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    let versions = d.appendingPathComponent("versions")
    let bin = d.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    for v in ["1.0.0", "1.0.1", "1.0.2"] {
        let dir = versions.appendingPathComponent(v)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write(dir, "binary", bytes: 1_000_000)
    }
    // The launcher points at 1.0.1 while 1.0.2 is newer on disk — exactly the
    // staged-release case that a "keep the newest" rule would get wrong.
    let launcher = bin.appendingPathComponent("tool")
    try FileManager.default.createSymbolicLink(
        at: launcher, withDestinationURL: versions.appendingPathComponent("1.0.1"))

    expect(CLIVersionsScanner.activeVersion(versionsDir: versions, launcher: launcher) == "1.0.1",
           "active version comes from the symlink, not the timestamp")

    let tool = CLIVersionsScanner.Tool(name: "Tool", versionsDir: versions.path,
                                       launcher: launcher.path)
    let found = await CLIVersionsScanner(
        category: cat("cli-old-versions", .safe), tools: [tool]).scan()
    expect(Set(found.map(\.displayName)) == ["Tool 1.0.0"],
           "lists only versions older than the running one — the staged 1.0.2 is a pending update, got \(found.map(\.displayName))")
    expect(CLIVersionsScanner.isNewer("2.1.266", than: "2.1.9")
           && !CLIVersionsScanner.isNewer("2.1.9", than: "2.1.266")
           && !CLIVersionsScanner.isNewer("1.0.1", than: "1.0.1"),
           "version comparison is numeric per component")

    // Fail closed: with no launcher there is no way to know what is live, so
    // nothing may be offered.
    let noLauncher = CLIVersionsScanner.Tool(name: "Tool", versionsDir: versions.path,
                                             launcher: bin.appendingPathComponent("missing").path)
    let none = await CLIVersionsScanner(
        category: cat("cli-old-versions", .safe), tools: [noLauncher]).scan()
    expect(none.isEmpty, "no launcher → nothing reported")

    // A launcher pointing outside the versions directory proves nothing either.
    let stray = bin.appendingPathComponent("stray")
    try FileManager.default.createSymbolicLink(at: stray, withDestinationURL: d)
    expect(CLIVersionsScanner.activeVersion(versionsDir: versions, launcher: stray) == nil,
           "a launcher outside the versions dir yields no active version")
} catch { expect(false, "CLIVersionsScanner setup: \(error)") }

// ── Live scan (opt-in) ──────────────────────────────────────────────
// `CRUFT_LIVE=1 swift run CruftChecks` scans this machine for real and prints
// what each category found. Not part of the pass/fail suite — it touches the
// user's disk and its output depends on the machine — but it is the only way
// to judge a scanner's false-positive rate before shipping it.
if ProcessInfo.processInfo.environment["CRUFT_LIVE"] != nil {
    section("LIVE scan of this machine")
    let all = CruftInfraFactory.makeAllScanners()
    for scanner in all {
        let items = await scanner.scan()
        guard !items.isEmpty else { continue }
        let total = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        print("  \(scanner.category.name) — \(ByteText.string(total)) in \(items.count) items")
        let cloud = items.filter(\.isCloudManaged).count
        if cloud > 0 { print("      ↳ \(cloud) of these are iCloud-synced") }
        for item in items.sorted(by: { $0.sizeBytes > $1.sizeBytes }).prefix(8) {
            let idle = item.monthsSinceLastUse.map { " (idle \($0)m)" } ?? ""
            let icloud = item.isCloudManaged ? " [iCloud]" : ""
            print("      \(ByteText.string(item.sizeBytes))\t\(item.displayName)\(idle)\(icloud)")
        }
    }
}

// ── Storage breakdown: where "Other" comes from ──────────────────────
section("DirectorySizer")
let devPaths = DirectorySizer.developerDataPaths()
expect(!devPaths.isEmpty, "developer data paths found on this machine")
expect(devPaths.allSatisfy { $0.hasPrefix(NSHomeDirectory()) },
       "developer data stays inside the home folder")
expect(!devPaths.contains { $0.hasSuffix("/.Trash") },
       ".Trash is excluded — it has its own slice and its own category")

// The per-user temp tree must never include the code-signing clone directory:
// its files report full size while sharing blocks with the installed app, and
// counting them pushed the Overview's total past the disk's own used figure.
let tempPaths = DirectorySizer.systemTempPaths()
expect(!tempPaths.contains { $0.hasSuffix("/X") },
       "the clone directory is excluded from system temp, got \(tempPaths)")
expect(DirectorySizer.cloneDirectoryNames.contains("X"), "X is a known clone directory")
if !tempPaths.isEmpty {
    expect(tempPaths.allSatisfy { $0.contains("/var/folders/") },
           "system temp paths live under /var/folders")
}

// Every slice must be measurable without exceeding what the disk says is used;
// the reverse means something is being counted twice or is not really there.
let allGroups = ["/Applications", "~/Library", "~/Documents", "~/Movies", "~/Pictures",
                 "~/Music", "~/Downloads", "~/Desktop"] + devPaths + tempPaths
let measuredTotal = DirectorySizer.totalSize(ofPaths: allGroups)
let volumeValues = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
    .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
let usedOnDisk = Int64(volumeValues?.volumeTotalCapacity ?? 0)
    - (volumeValues?.volumeAvailableCapacityForImportantUsage ?? 0)
expect(measuredTotal <= usedOnDisk,
       "measured slices (\(ByteText.string(measuredTotal))) fit inside used space "
       + "(\(ByteText.string(usedOnDisk)))")

// ── Live storage breakdown (opt-in) ─────────────────────────────────
if ProcessInfo.processInfo.environment["CRUFT_LIVE"] != nil {
    section("LIVE storage breakdown")
    let groups: [(String, [String])] = [
        ("Apps", ["/Applications"]),
        ("App data & caches", ["~/Library"]),
        ("Developer data", DirectorySizer.developerDataPaths() + DirectorySizer.homebrewPaths()),
        ("Documents", ["~/Documents"]),
        ("Media", ["~/Movies", "~/Pictures", "~/Music"]),
        ("Downloads & Desktop", ["~/Downloads", "~/Desktop"]),
        ("System temp", DirectorySizer.systemTempPaths()),
    ]
    var accounted: Int64 = 0
    for (name, paths) in groups {
        let bytes = DirectorySizer.totalSize(ofPaths: paths)
        accounted += bytes
        print("  \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(ByteText.string(bytes))")
    }
    let url = URL(fileURLWithPath: "/")
    let values = try? url.resourceValues(forKeys: [
        .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
    let total = Int64(values?.volumeTotalCapacity ?? 0)
    let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
    let used = max(0, total - available)
    print("  \("Other".padding(toLength: 22, withPad: " ", startingAt: 0)) \(ByteText.string(max(0, used - accounted)))")
    print("  \("— accounted for".padding(toLength: 22, withPad: " ", startingAt: 0)) \(ByteText.string(accounted)) of \(ByteText.string(used)) used")
}

// ── Summary ─────────────────────────────────────────────────────────
print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
