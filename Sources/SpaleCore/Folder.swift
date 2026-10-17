import Foundation

public struct OpenTarget: Equatable, Sendable {
    public let root: URL?
    public let file: URL?
    public let isRepository: Bool

    public static func resolve(_ input: URL) throws -> OpenTarget {
        let metadata = Git.isMetadata(input)
        let url = metadata ? input.standardizedFileURL : input.standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { throw CocoaError(.fileNoSuchFile) }
        guard !metadata || !directory.boolValue else { throw CocoaError(.fileReadNoPermission) }
        let repository = metadata ? nil : Git.root(containing: url)
        return OpenTarget(root: repository ?? (directory.boolValue ? url : nil), file: directory.boolValue ? nil : url, isRepository: repository != nil)
    }
}

public struct FolderEntry: Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let isEmpty: Bool
    public var isHidden: Bool { (path as NSString).lastPathComponent.hasPrefix(".") }
}

public struct FolderListing: Sendable {
    public let entries: [FolderEntry]
    public let truncated: Bool
    public static let limit = 2_000

    private static func contents(_ directory: URL) throws -> FileManager.DirectoryEnumerator {
        guard FileManager.default.isReadableFile(atPath: directory.path), FileManager.default.isExecutableFile(atPath: directory.path) else { throw CocoaError(.fileReadNoPermission) }
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey], options: [.skipsSubdirectoryDescendants]) else { throw CocoaError(.fileReadNoPermission) }
        return enumerator
    }

    private static func isEmpty(_ directory: URL) -> Bool {
        guard let enumerator = try? contents(directory) else { return false }
        for case let url as URL in enumerator where url.lastPathComponent.lowercased() != ".git" {
            return false
        }
        return true
    }

    public static func load(root: URL, path: String = "", limit: Int = limit) throws -> FolderListing {
        let directory = root.appendingPathComponent(path, isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnknown) }
        let real = directory.resolvingSymlinksInPath(), realRoot = root.resolvingSymlinksInPath()
        guard real == realRoot || real.path.hasPrefix(realRoot.path + "/"), !path.split(separator: "/").contains(where: { $0.lowercased() == ".git" }) else { throw CocoaError(.fileReadNoPermission) }
        let enumerator = try contents(directory)
        var entries: [FolderEntry] = []
        var truncated = false
        for case let url as URL in enumerator {
            if url.lastPathComponent.lowercased() == ".git" { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard values.isDirectory == true || values.isRegularFile == true || values.isSymbolicLink == true else { continue }
            if entries.count >= max(0, limit) { truncated = true; break }
            let relative = path.isEmpty ? url.lastPathComponent : path + "/" + url.lastPathComponent
            let directory = values.isDirectory == true && values.isSymbolicLink != true
            entries.append(FolderEntry(path: relative, isDirectory: directory, isSymbolicLink: values.isSymbolicLink == true, isEmpty: directory && isEmpty(url)))
        }
        return FolderListing(entries: entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            let left = ($0.path as NSString).lastPathComponent.lowercased(), right = ($1.path as NSString).lastPathComponent.lowercased()
            return left == right ? $0.path < $1.path : left < right
        }, truncated: truncated)
    }
}
