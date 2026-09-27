import Foundation
import CruftCore

/// Pure parsing of `docker system df -v --format '{{json .}}'` output into
/// `ScanItem`s per Docker category. Separated from I/O so it's testable with
/// a JSON fixture and no Docker installed.
///
/// Item URLs use a `docker://local/<kind>/<ref>` scheme; `ScanItem.id` (the URL
/// path) stays unique because the kind is part of the path, and `DockerCleaner`
/// parses the same URL back into the right removal command.
public enum DockerUsageParser {

    public static let buildCacheCategoryID = "docker-build-cache"
    public static let danglingImagesCategoryID = "docker-dangling-images"
    public static let stoppedContainersCategoryID = "docker-stopped-containers"
    public static let unusedImagesCategoryID = "docker-unused-images"
    public static let unusedVolumesCategoryID = "docker-unused-volumes"

    /// All category ids this parser can produce, in Catalog order.
    public static let categoryIDs = [
        buildCacheCategoryID, danglingImagesCategoryID, stoppedContainersCategoryID,
        unusedImagesCategoryID, unusedVolumesCategoryID,
    ]

    // MARK: - Size strings

    /// Docker prints sizes as decimal human strings ("1.204GB", "63B", "10.5MB",
    /// "N/A"), sometimes with a suffix ("12B (virtual 1.2GB)"). Unknown → 0.
    public static func parseSize(_ raw: String?) -> Int64 {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return 0 }
        if let paren = s.firstIndex(of: "(") {
            s = String(s[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        if s.uppercased() == "N/A" { return 0 }
        let units: [(String, Double)] = [
            ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1),
        ]
        let upper = s.uppercased()
        for (suffix, factor) in units where upper.hasSuffix(suffix) {
            let number = upper.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            guard let value = Double(number) else { return 0 }
            return Int64(value * factor)
        }
        return Int64(Double(s) ?? 0)
    }

    // MARK: - Inventory → items

    /// Parses the df JSON and buckets everything cleanable into categories.
    /// Tolerant of shape drift across Docker versions: fields may be strings or
    /// native numbers/bools; anything unreadable is skipped, never fatal.
    public static func items(fromDF json: String) -> [String: [ScanItem]] {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }

        var out: [String: [ScanItem]] = [:]

        // Images: dangling (untagged) are safe; tagged-but-unused need a look.
        // `df -v` prints one line per tag, so an image with several tags is
        // grouped by ID: one row, one removal, its tags listed in the name.
        // UniqueSize is what deleting the image is guaranteed to free; Size
        // also counts layers shared with other images and would overstate it.
        var tagsByID: [String: [String]] = [:]
        var sizeByID: [String: Int64] = [:]
        var order: [String] = []
        for image in dicts(root["Images"]) {
            let repo = str(image["Repository"])
            let tag = str(image["Tag"])
            let id = str(image["ID"])
            let containers = int(image["Containers"])
            guard containers == 0, !id.isEmpty else { continue }
            let unique = parseSize(str(image["UniqueSize"]))
            let size = unique > 0 ? unique : parseSize(str(image["Size"]))
            if tagsByID[id] == nil { order.append(id); tagsByID[id] = [] }
            sizeByID[id] = max(sizeByID[id] ?? 0, size)
            if !repo.isEmpty, repo != "<none>" {
                tagsByID[id]?.append(tag.isEmpty || tag == "<none>" ? repo : "\(repo):\(tag)")
            }
        }
        for id in order {
            guard let size = sizeByID[id], size > 0 else { continue }
            let tags = tagsByID[id] ?? []
            if tags.isEmpty {
                append(&out, danglingImagesCategoryID, item(
                    kind: "image", ref: id,
                    name: "Untagged image \(String(id.prefix(12)))",
                    size: size, categoryID: danglingImagesCategoryID))
            } else {
                append(&out, unusedImagesCategoryID, item(
                    kind: "image", ref: id, name: tags.joined(separator: ", "),
                    size: size, categoryID: unusedImagesCategoryID))
            }
        }

        // Containers: only ones that are not running.
        for container in dicts(root["Containers"]) {
            let status = str(container["Status"])
            let stopped = status.hasPrefix("Exited") || status.hasPrefix("Created")
                || status.hasPrefix("Dead")
            guard stopped else { continue }
            let id = str(container["ID"])
            guard !id.isEmpty else { continue }
            let names = str(container["Names"])
            let image = str(container["Image"])
            let label = names.isEmpty ? String(id.prefix(12)) : names
            append(&out, stoppedContainersCategoryID, item(
                kind: "container", ref: id,
                name: image.isEmpty ? label : "\(label) (\(image))",
                size: parseSize(str(container["Size"])),
                categoryID: stoppedContainersCategoryID))
        }

        // Volumes: not linked to any container. Risky — could be database data.
        for volume in dicts(root["Volumes"]) {
            guard int(volume["Links"]) == 0 else { continue }
            let name = str(volume["Name"])
            guard !name.isEmpty else { continue }
            append(&out, unusedVolumesCategoryID, item(
                kind: "volume", ref: name,
                name: volumeLabel(name: name, labels: str(volume["Labels"])),
                size: parseSize(str(volume["Size"])),
                categoryID: unusedVolumesCategoryID))
        }

        // Build cache: one aggregate row — `docker builder prune` is all-or-nothing.
        let cacheEntries = dicts(root["BuildCache"]).filter { !boolValue($0["InUse"]) }
        let cacheBytes = cacheEntries.reduce(Int64(0)) { $0 + parseSize(str($1["Size"])) }
        if cacheBytes > 0 {
            append(&out, buildCacheCategoryID, item(
                kind: "build-cache", ref: "all",
                name: "Build cache (\(cacheEntries.count) entries)",
                size: cacheBytes, categoryID: buildCacheCategoryID))
        }

        return out
    }

    /// A volume name a person can act on. Compose stamps the project and the
    /// declared volume name into labels, which is the difference between
    /// "data-platform-core / spark_ivy" and a 64-character hash the user has no
    /// way to judge. Anonymous volumes (a bare hash, no labels) are labelled as
    /// such and abbreviated, because their full name carries no information.
    public static func volumeLabel(name: String, labels raw: String) -> String {
        let labels = parseLabels(raw)
        let project = labels["com.docker.compose.project"]
        let declared = labels["com.docker.compose.volume"]
        if let project, let declared {
            return "\(project) / \(declared)"
        }
        if isAnonymousName(name) {
            let short = String(name.prefix(12))
            if let project {
                return "\(project) / unnamed volume (\(short)…)"
            }
            return "Unnamed volume (\(short)…)"
        }
        return name
    }

    /// `docker system df -v` renders labels as one `k=v,k=v` string.
    public static func parseLabels(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...])
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    /// Docker names an anonymous volume with a 64-character hex digest.
    public static func isAnonymousName(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy { $0.isHexDigit }
    }

    /// `docker://local/<kind>/<ref>` — see type comment.
    public static func url(kind: String, ref: String) -> URL {
        var comps = URLComponents()
        comps.scheme = "docker"
        comps.host = "local"
        comps.path = "/\(kind)/\(ref)"
        return comps.url ?? URL(fileURLWithPath: "/dev/null")
    }

    // MARK: - Tolerant JSON access

    private static func dicts(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }
    private static func str(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }
    private static func int(_ value: Any?) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        return Int(str(value)) ?? 0
    }
    private static func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        return str(value).lowercased() == "true"
    }

    private static func item(kind: String, ref: String, name: String,
                             size: Int64, categoryID: String) -> ScanItem {
        let risk = Catalog.category(categoryID)?.risk ?? .risky
        return ScanItem(url: url(kind: kind, ref: ref), displayName: name,
                        sizeBytes: size, categoryID: categoryID, risk: risk)
    }
    private static func append(_ out: inout [String: [ScanItem]],
                               _ key: String, _ item: ScanItem) {
        out[key, default: []].append(item)
    }
}
