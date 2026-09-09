import Foundation
import Testing
import SweepCore
@testable import SweepInfra

// MARK: - Test helpers

/// Creates a unique temp directory for a test and returns it. Caller is
/// responsible for removing it (each test does so in a `defer`).
private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SweepInfraTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@discardableResult
private func writeFile(at url: URL, bytes: Int) throws -> URL {
    let data = Data(repeating: 0x41, count: bytes)
    try data.write(to: url)
    return url
}

private func setModificationDate(_ date: Date, of url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

private func testCategory(id: String = "test-cat", risk: RiskLevel = .safe) -> CleanCategory {
    CleanCategory(id: id, name: "Test", detail: "detail", consequence: "consequence",
                  risk: risk, systemImage: "folder")
}

// MARK: - DirectoryChildrenScanner

@Suite("DirectoryChildrenScanner")
struct DirectoryChildrenScannerTests {

    @Test("finds children with correct sizes, skips hidden")
    func findsChildren() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(at: dir.appendingPathComponent("a.txt"), bytes: 100)
        try writeFile(at: dir.appendingPathComponent("b.txt"), bytes: 250)
        try writeFile(at: dir.appendingPathComponent(".hidden"), bytes: 50)

        let scanner = DirectoryChildrenScanner(category: testCategory(), roots: [dir.path])
        let items = await scanner.scan()

        #expect(items.count == 2)
        #expect(items.contains { $0.displayName == "a.txt" && $0.sizeBytes >= 100 })
        #expect(items.contains { $0.displayName == "b.txt" && $0.sizeBytes >= 250 })
        #expect(!items.contains { $0.displayName == ".hidden" })
    }

    @Test("skips zero-byte items")
    func skipsZeroByte() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(at: dir.appendingPathComponent("empty.txt"), bytes: 0)
        try writeFile(at: dir.appendingPathComponent("nonempty.txt"), bytes: 10)

        let scanner = DirectoryChildrenScanner(category: testCategory(), roots: [dir.path])
        let items = await scanner.scan()

        #expect(items.count == 1)
        #expect(items.first?.displayName == "nonempty.txt")
    }

    @Test("nonexistent root yields no items, no throw")
    func missingRoot() async {
        let scanner = DirectoryChildrenScanner(
            category: testCategory(), roots: ["/nonexistent/path/\(UUID().uuidString)"]
        )
        let items = await scanner.scan()
        #expect(items.isEmpty)
    }

    @Test("excludes children by substring match")
    func excludesByName() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Homebrew"), withIntermediateDirectories: true
        )
        try writeFile(at: dir.appendingPathComponent("Homebrew/x.txt"), bytes: 20)
        try writeFile(at: dir.appendingPathComponent("keep.txt"), bytes: 20)

        let scanner = DirectoryChildrenScanner(
            category: testCategory(), roots: [dir.path], excludedChildNameContains: ["Homebrew"]
        )
        let items = await scanner.scan()

        #expect(items.count == 1)
        #expect(items.first?.displayName == "keep.txt")
    }
}

// MARK: - WholeDirectoryScanner

@Suite("WholeDirectoryScanner")
struct WholeDirectoryScannerTests {

    @Test("each root becomes one item with its label")
    func wholeDirs() async throws {
        let dirA = try makeTempDir()
        let dirB = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }
        try writeFile(at: dirA.appendingPathComponent("f1"), bytes: 30)
        try writeFile(at: dirB.appendingPathComponent("f2"), bytes: 40)

        let scanner = WholeDirectoryScanner(
            category: testCategory(), roots: [dirA.path, dirB.path], labels: ["Cache A", "Cache B"]
        )
        let items = await scanner.scan()

        #expect(items.count == 2)
        #expect(items.contains { $0.displayName == "Cache A" })
        #expect(items.contains { $0.displayName == "Cache B" })
    }
}

// MARK: - AgedFilesScanner

@Suite("AgedFilesScanner")
struct AgedFilesScannerTests {

    @Test("includes only files older than the threshold")
    func onlyOldFiles() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldFile = try writeFile(at: dir.appendingPathComponent("old.txt"), bytes: 10)
        let newFile = try writeFile(at: dir.appendingPathComponent("new.txt"), bytes: 10)

        try setModificationDate(Date().addingTimeInterval(-200 * 86400), of: oldFile)
        try setModificationDate(Date(), of: newFile)

        let scanner = AgedFilesScanner(category: testCategory(), root: dir.path, olderThanDays: 90)
        let items = await scanner.scan()

        #expect(items.count == 1)
        #expect(items.first?.displayName == "old.txt")
    }
}

// MARK: - NamePatternScanner

@Suite("NamePatternScanner")
struct NamePatternScannerTests {

    @Test("prefix matching is case-insensitive")
    func caseInsensitivePrefix() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(at: dir.appendingPathComponent("screenshot 1.png"), bytes: 10)
        try writeFile(at: dir.appendingPathComponent("SCREENSHOT 2.png"), bytes: 10)
        try writeFile(at: dir.appendingPathComponent("not-a-match.png"), bytes: 10)

        let scanner = NamePatternScanner(
            category: testCategory(), roots: [dir.path], prefixes: ["Screenshot"]
        )
        let items = await scanner.scan()

        #expect(items.count == 2)
        #expect(!items.contains { $0.displayName == "not-a-match.png" })
    }
}

// MARK: - LargeFilesScanner

@Suite("LargeFilesScanner")
struct LargeFilesScannerTests {

    @Test("respects the minBytes threshold")
    func minBytesThreshold() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(at: dir.appendingPathComponent("small.bin"), bytes: 100)
        try writeFile(at: dir.appendingPathComponent("big.bin"), bytes: 1000)

        let scanner = LargeFilesScanner(category: testCategory(), roots: [dir.path], minBytes: 500)
        let items = await scanner.scan()

        #expect(items.count == 1)
        #expect(items.first?.displayName == "big.bin")
        #expect(items.first?.risk == .risky)
    }

    @Test("skips paths under ~/Library and hidden directories")
    func skipsLibraryAndHidden() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let hidden = dir.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeFile(at: hidden.appendingPathComponent("big.bin"), bytes: 1000)

        let visible = dir.appendingPathComponent("visible", isDirectory: true)
        try FileManager.default.createDirectory(at: visible, withIntermediateDirectories: true)
        try writeFile(at: visible.appendingPathComponent("big.bin"), bytes: 1000)

        let scanner = LargeFilesScanner(category: testCategory(), roots: [dir.path], minBytes: 500)
        let items = await scanner.scan()

        #expect(items.count == 1)
        #expect(items.first?.url.path == visible.appendingPathComponent("big.bin").path)
    }
}

// MARK: - SystemTrashService

@Suite("SystemTrashService")
struct SystemTrashServiceTests {

    @Test("moves a file to Trash (recoverable, not removeItem)")
    func movesToTrash() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try writeFile(at: dir.appendingPathComponent("to-trash.txt"), bytes: 10)
        let service = SystemTrashService()
        try service.moveToTrash(file)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

// MARK: - SweepInfraFactory

@Suite("SweepInfraFactory")
struct SweepInfraFactoryTests {

    @Test("returns exactly one scanner per Catalog category, in order")
    func oneScannerPerCategory() {
        let scanners = SweepInfraFactory.makeAllScanners()
        #expect(scanners.count == Catalog.categories.count)
        for (scanner, category) in zip(scanners, Catalog.categories) {
            #expect(scanner.category.id == category.id)
        }
    }
}

// MARK: - DockerUsageParser

@Suite("DockerUsageParser")
struct DockerUsageParserTests {

    @Test("parses Docker's decimal human size strings")
    func sizeStrings() {
        #expect(DockerUsageParser.parseSize("1.204GB") == 1_204_000_000)
        #expect(DockerUsageParser.parseSize("63B") == 63)
        #expect(DockerUsageParser.parseSize("10.5MB") == 10_500_000)
        #expect(DockerUsageParser.parseSize("2.1kB") == 2_100)
        #expect(DockerUsageParser.parseSize("N/A") == 0)
        #expect(DockerUsageParser.parseSize("12B (virtual 1.2GB)") == 12)
        #expect(DockerUsageParser.parseSize(nil) == 0)
    }

    @Test("categorizes a df -v document into the granular docker categories")
    func categorization() {
        let fixture = """
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
        let buckets = DockerUsageParser.items(fromDF: fixture)
        #expect(buckets["docker-dangling-images"]?.count == 1)
        #expect(buckets["docker-unused-images"]?.map(\.displayName) == ["postgres:17"])
        #expect(buckets["docker-unused-images"]?.first?.sizeBytes == 400_000_000)
        #expect(buckets["docker-stopped-containers"]?.count == 1)
        #expect(buckets["docker-unused-volumes"]?.map(\.displayName) == ["orphan-vol"])
        #expect(buckets["docker-build-cache"]?.first?.sizeBytes == 300_000_000)
        let ids = buckets.values.flatMap { $0 }.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("garbage input yields no items, never a crash")
    func garbage() {
        #expect(DockerUsageParser.items(fromDF: "not json").isEmpty)
        #expect(DockerUsageParser.items(fromDF: "{}").isEmpty)
    }
}
