import Foundation
import Testing
@testable import SweepCore

// MARK: - Catalog integrity

@Test func catalogIDsAreUnique() {
    let ids = Catalog.categories.map(\.id)
    #expect(Set(ids).count == ids.count)
    let roleIDs = Catalog.roles.map(\.id)
    #expect(Set(roleIDs).count == roleIDs.count)
}

@Test func everyRoleCategoryExists() {
    let known = Set(Catalog.categories.map(\.id))
    for role in Catalog.roles {
        for id in role.categoryIDs {
            #expect(known.contains(id), "role \(role.id) references unknown category \(id)")
        }
        #expect(!role.categoryIDs.isEmpty)
    }
}

@Test func everyRoleHasAtLeastOneSafeCategory() {
    for role in Catalog.roles {
        let hasSafe = role.categoryIDs.contains {
            Catalog.category($0)?.risk == .safe
        }
        #expect(hasSafe, "role \(role.id) has no safe category")
    }
}

@Test func categoriesHavePlainLanguageCopy() {
    for c in Catalog.categories {
        #expect(!c.detail.isEmpty && !c.consequence.isEmpty && !c.systemImage.isEmpty)
    }
}

// MARK: - RiskLevel

@Test func riskOrdering() {
    #expect(RiskLevel.safe < .review)
    #expect(RiskLevel.review < .risky)
    #expect(RiskLevel.allCases.sorted() == [.safe, .review, .risky])
    for r in RiskLevel.allCases { #expect(!r.label.isEmpty) }
}

// MARK: - Helpers

private func item(_ path: String, _ size: Int64, _ cat: String, _ risk: RiskLevel) -> ScanItem {
    ScanItem(url: URL(fileURLWithPath: path), displayName: (path as NSString).lastPathComponent,
             sizeBytes: size, categoryID: cat, risk: risk)
}
private let catSafe = CleanCategory(id: "a", name: "A", detail: "d", consequence: "c",
                                    risk: .safe, systemImage: "trash")
private let catRisky = CleanCategory(id: "b", name: "B", detail: "d", consequence: "c",
                                     risk: .risky, systemImage: "trash")

// MARK: - SelectionPolicy

@Test func defaultSelectionPicksOnlySafeItems() {
    let results = [
        CategoryScanResult(category: catSafe, items: [
            item("/tmp/x1", 100, "a", .safe), item("/tmp/x2", 50, "a", .review)]),
        CategoryScanResult(category: catRisky, items: [item("/tmp/y1", 999, "b", .risky)]),
    ]
    let sel = SelectionPolicy.defaultSelection(in: results)
    #expect(sel == ["/tmp/x1"])
    #expect(SelectionPolicy.selectedBytes(in: results, selection: sel) == 100)
    let all = Set(["/tmp/x1", "/tmp/x2", "/tmp/y1"])
    #expect(SelectionPolicy.selectedBytes(in: results, selection: all) == 1149)
}

@Test func categoryResultSortsItemsBySizeDescending() {
    let r = CategoryScanResult(category: catSafe, items: [
        item("/1", 5, "a", .safe), item("/2", 500, "a", .safe), item("/3", 50, "a", .safe)])
    #expect(r.items.map(\.sizeBytes) == [500, 50, 5])
    #expect(r.totalBytes == 555)
}

// MARK: - ScanUseCase

private struct FakeScanner: CategoryScanner {
    let category: CleanCategory
    let found: [ScanItem]
    func scan() async -> [ScanItem] { found }
}

@Test func scanUseCaseFiltersEmptyAndSortsBySize() async {
    let small = CleanCategory(id: "small", name: "S", detail: "d", consequence: "c",
                              risk: .safe, systemImage: "trash")
    let big = CleanCategory(id: "big", name: "B", detail: "d", consequence: "c",
                            risk: .safe, systemImage: "trash")
    let empty = CleanCategory(id: "empty", name: "E", detail: "d", consequence: "c",
                              risk: .safe, systemImage: "trash")
    let role = RoleProfile(id: "r", name: "R", blurb: "", systemImage: "person",
                           categoryIDs: ["small", "empty", "big"])
    let useCase = ScanUseCase(scanners: [
        FakeScanner(category: small, found: [item("/s", 10, "small", .safe)]),
        FakeScanner(category: empty, found: []),
        FakeScanner(category: big, found: [item("/b", 1000, "big", .safe)]),
    ])
    let results = await useCase.run(for: role) { _ in }
    #expect(results.map(\.id) == ["big", "small"])
}

@Test func scanUseCaseReportsProgressAndOnlyRoleCategories() async {
    let a = CleanCategory(id: "a", name: "A", detail: "d", consequence: "c",
                          risk: .safe, systemImage: "trash")
    let b = CleanCategory(id: "b", name: "B", detail: "d", consequence: "c",
                          risk: .safe, systemImage: "trash")
    let role = RoleProfile(id: "r", name: "R", blurb: "", systemImage: "person",
                           categoryIDs: ["a"])
    let useCase = ScanUseCase(scanners: [
        FakeScanner(category: a, found: [item("/a", 7, "a", .safe)]),
        FakeScanner(category: b, found: [item("/b", 9, "b", .safe)]),
    ])
    #expect(useCase.scanners(for: role).map(\.category.id) == ["a"])
    nonisolated(unsafe) var updates: [ScanProgress] = []
    let results = await useCase.run(for: role) { updates.append($0) }
    #expect(results.count == 1 && results[0].totalBytes == 7)
    #expect(updates.first?.finished == 0 && updates.first?.total == 1)
    #expect(updates.last?.finished == 1 && updates.last?.bytesFoundSoFar == 7)
}

// MARK: - CleanUseCase

private final class FakeTrash: TrashService, @unchecked Sendable {
    var trashed: [URL] = []
    var failOn: Set<String> = []
    func moveToTrash(_ url: URL) throws {
        if failOn.contains(url.path) {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "nope"])
        }
        trashed.append(url)
    }
}

@Test func cleanUseCaseSumsFreedBytesAndCollectsFailures() {
    let trash = FakeTrash()
    trash.failOn = ["/fail"]
    let report = CleanUseCase(trash: trash).run(items: [
        item("/ok1", 100, "a", .safe),
        item("/fail", 999, "a", .safe),
        item("/ok2", 50, "a", .safe),
    ])
    #expect(report.freedBytes == 150)
    #expect(report.cleanedCount == 2)
    #expect(report.failures.count == 1)
    #expect(report.failures[0].item.id == "/fail")
    #expect(trash.trashed.map(\.path) == ["/ok1", "/ok2"])
}

// MARK: - SpecialCleaner routing

private final class FakeSpecial: SpecialCleaner, @unchecked Sendable {
    let categoryIDs: Set<String> = ["docker-x"]
    var cleaned: [String] = []
    func clean(_ item: ScanItem) throws { cleaned.append(item.id) }
}

@Test func cleanUseCaseRoutesSpecialCategoriesAndReportsExternalBytes() {
    let special = FakeSpecial()
    let trash = FakeTrash()
    let dockerItem = ScanItem(url: URL(string: "docker://local/image/abc")!,
                              displayName: "abc", sizeBytes: 900,
                              categoryID: "docker-x", risk: .safe)
    let report = CleanUseCase(trash: trash, specials: [special]).run(items: [
        item("/file", 100, "a", .safe), dockerItem,
    ])
    #expect(special.cleaned == ["/image/abc"])
    #expect(trash.trashed.map(\.path) == ["/file"])
    #expect(report.freedBytes == 1000)
    #expect(report.externallyRemovedBytes == 900)
}

@Test func dockerCategoriesAreHonestAboutPermanentRemoval() {
    let dockerIDs = ["docker-build-cache", "docker-dangling-images",
                     "docker-stopped-containers", "docker-unused-images",
                     "docker-unused-volumes"]
    for id in dockerIDs {
        #expect(Catalog.category(id)?.removal == .external, "\(id) must be external")
        #expect(Catalog.category(id)?.consequence.contains("not the Trash") == true)
    }
    #expect(Catalog.category("docker-unused-volumes")?.risk == .risky)
    #expect(Catalog.category("docker-data")?.removal == .trash)
}

// MARK: - ByteText

@Test func byteTextFormats() {
    #expect(ByteText.string(0) == "Zero KB")
    #expect(!ByteText.string(1_500_000_000).isEmpty)
}
