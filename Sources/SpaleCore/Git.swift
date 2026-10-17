import Foundation

public enum GitError: LocalizedError {
    case command(String)
    public var errorDescription: String? { if case .command(let value) = self { return value }; return nil }
}

public struct Git {
    public static func run(_ arguments: [String], at directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-c", "core.quotepath=false"] + arguments
        process.currentDirectoryURL = directory
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitError.command(String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    public static func string(_ arguments: [String], at directory: URL) throws -> String {
        String(decoding: try run(arguments, at: directory), as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    public static func root(containing url: URL) -> URL? {
        let real = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real.path, isDirectory: &isDirectory) else { return nil }
        let directory = isDirectory.boolValue ? real : real.deletingLastPathComponent()
        guard let path = try? string(["rev-parse", "--show-toplevel"], at: directory) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
    }

    public static func isMetadata(_ url: URL) -> Bool {
        let input = url.standardizedFileURL
        let target = input.resolvingSymlinksInPath().standardizedFileURL
        if [input, target].contains(where: { $0.pathComponents.contains(where: { $0.lowercased() == ".git" }) }) { return true }
        let destination = input.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(input.lastPathComponent).standardizedFileURL
        for candidate in Set([destination, target]) {
            var directory = candidate
            while true {
                if (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("HEAD").path)) != nil,
                   (try? run(["rev-parse", "--resolve-git-dir", directory.path], at: URL(fileURLWithPath: "/", isDirectory: true))) != nil { return true }
                if directory.path == "/" { break }
                directory = directory.deletingLastPathComponent().standardizedFileURL
            }
        }
        return false
    }
}

public enum Stream: String, CaseIterable, Sendable { case staged, unstaged }

public struct Change: Equatable, Sendable {
    public let path: String
    public let oldPath: String?
    public let status: Character
    public let stream: Stream
    public init(path: String, oldPath: String? = nil, status: Character, stream: Stream) {
        self.path = path; self.oldPath = oldPath; self.status = status; self.stream = stream
    }
    public var label: String { oldPath.map { "\($0) → \(path)" } ?? path }
}

public enum StatusParser {
    public static func parse(_ data: Data) -> [Change] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var result: [Change] = [], i = 0
        while i < fields.count {
            let field = fields[i]
            i += 1
            guard field.count >= 4 else { continue }
            let bytes = Array(field)
            let x = Character(UnicodeScalar(bytes[0])), y = Character(UnicodeScalar(bytes[1]))
            let path = String(decoding: bytes.dropFirst(3), as: UTF8.self)
            var old: String?
            if x == "R" || x == "C" || y == "R" || y == "C", i < fields.count {
                old = String(decoding: fields[i], as: UTF8.self); i += 1
            }
            if x == "?" && y == "?" { result.append(Change(path: path, status: "U", stream: .unstaged)); continue }
            if x != " " && x != "?" { result.append(Change(path: path, oldPath: old, status: normalized(x), stream: .staged)) }
            if y != " " && y != "?" { result.append(Change(path: path, oldPath: y == "R" ? old : nil, status: normalized(y), stream: .unstaged)) }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    private static func normalized(_ value: Character) -> Character { "AMDRU".contains(value) ? value : "M" }
}

public struct RepositorySnapshot: Sendable {
    public let root: URL
    public let branch: String
    public let name: String
    public let gitDirectory: URL
    public let commonDirectory: URL
    public let changes: [Change]
    public let files: [String: Data]
    public let index: [String: Data]
    public let head: [String: Data]

    public static func load(_ root: URL, extraPaths: Set<String> = []) throws -> RepositorySnapshot {
        let changes = StatusParser.parse(try Git.run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: root))
        let branch = (try? Git.string(["symbolic-ref", "--short", "-q", "HEAD"], at: root)) ?? "HEAD"
        let git = try Git.string(["rev-parse", "--absolute-git-dir"], at: root)
        let common = try Git.string(["rev-parse", "--path-format=absolute", "--git-common-dir"], at: root)
        let commonURL = URL(fileURLWithPath: common).resolvingSymlinksInPath()
        let isLinked = URL(fileURLWithPath: git).resolvingSymlinksInPath() != commonURL
        let mainName = commonURL.deletingLastPathComponent().lastPathComponent
        let name = isLinked ? "\(mainName) › \(root.lastPathComponent)" : root.lastPathComponent
        var files: [String: Data] = [:], index: [String: Data] = [:], head: [String: Data] = [:]
        for path in Set(changes.map(\.path)).union(extraPaths) {
            files[path] = try? Data(contentsOf: root.appendingPathComponent(path))
            index[path] = (try? Git.run(["show", ":\(path)"], at: root)) ?? Data()
            let oldPath = changes.first { $0.path == path && $0.stream == .staged }?.oldPath ?? path
            head[path] = (try? Git.run(["show", "HEAD:\(oldPath)"], at: root)) ?? Data()
        }
        return RepositorySnapshot(root: root, branch: branch, name: name, gitDirectory: URL(fileURLWithPath: git), commonDirectory: commonURL, changes: changes, files: files, index: index, head: head)
    }
}
