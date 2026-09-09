// SweepChecks — dependency-free verification runner.
// `swift test` needs Xcode's XCTest/Testing runtime, which Command Line Tools
// lack; this executable runs the same assertions via `swift run SweepChecks`.
import Foundation
import SweepCore
import SweepInfra

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
        .appendingPathComponent("SweepChecks-\(UUID().uuidString)", isDirectory: true)
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
section("SweepInfraFactory")
let all = SweepInfraFactory.makeAllScanners()
expect(all.count == Catalog.categories.count,
       "one scanner per category (\(all.count)/\(Catalog.categories.count))")
expect(all.map(\.category.id) == Catalog.categories.map(\.id), "factory order matches catalog")

// ── Infra: SystemTrashService (real, tiny temp file) ────────────────
section("SystemTrashService")
do {
    let d = try tempDir(); defer { try? FileManager.default.removeItem(at: d) }
    let f = try write(d, "sweep-check-trash-me.txt", bytes: 4)
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

// ── Summary ─────────────────────────────────────────────────────────
print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
