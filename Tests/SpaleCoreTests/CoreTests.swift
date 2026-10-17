import Foundation
import SpaleCore

final class CoreTests {
    func testStatusSeparatesStreamsAndRenamePaths() {
        let data = Data("MM source.swift\0R  new name.txt\0old name.txt\0 D deleted.txt\0?? fresh.txt\0A  binary.dat\0".utf8)
        let changes = StatusParser.parse(data)
        precondition(changes.filter { $0.path == "source.swift" }.map(\.stream) == [.staged, .unstaged])
        precondition(changes.first { $0.status == "R" }?.oldPath == "old name.txt")
        precondition(changes.first { $0.path == "fresh.txt" }?.status == "U")
        precondition(changes.first { $0.path == "deleted.txt" }?.stream == .unstaged)
        precondition(changes.first { $0.path == "binary.dat" }?.stream == .staged)
    }
    func testEncodingPreservesCRLFAndFinalNewline() {
        for original in ["a\nb\n", "a\nb", "a\r\nb\r\n", "a\r\nb", ""] {
            let content = TextContent(Data(original.utf8))
            precondition(content.editable)
            precondition(content.encode(content.text) == Data(original.utf8))
            precondition(content.encode(content.text.replacingOccurrences(of: "b", with: "β")) == Data(original.replacingOccurrences(of: "b", with: "β").utf8))
        }
        precondition(TextContent(Data("a\n".utf8)).encode("edited") == Data("edited\n".utf8))
        precondition(TextContent(Data("a".utf8)).encode("edited\n") == Data("edited".utf8))
    }
    func testNonUTF8AndBinaryAreReadOnly() {
        precondition(!(TextContent(Data([0xff, 0xfe, 0x41])).editable))
        precondition(!(TextContent(Data([0x41, 0, 0x42])).editable))
        precondition(TextContent(Data("λ".utf8)).editable)
    }
    func testWordHighlightRequiresSimilarContent() {
        precondition(WordDiff.ranges(before: "", after: "content") == nil)
        precondition(WordDiff.ranges(before: "content", after: "") == nil)
        precondition(WordDiff.ranges(before: "openButton.isBordered = true; openButton.bezelStyle = .rounded\n", after: "word.alignment = .center\n") == nil)
        precondition(WordDiff.ranges(before: "  alpha(beta);\n", after: "  gamma(delta);\n") == nil)
        precondition(WordDiff.ranges(before: "   {}\n", after: " {}\n") == nil)
        precondition(WordDiff.ranges(before: "short name\n", after: "short name with many unrelated additional words\n") == nil)
        let before = "let title = \"harbor\"\n", after = "let title = \"garden\"\n"
        let changes = WordDiff.ranges(before: before, after: after)!
        precondition(changes.removed.map { (before as NSString).substring(with: $0) } == ["harbor"])
        precondition(changes.inserted.map { (after as NSString).substring(with: $0) } == ["garden"])
        for (before, after, removed, inserted) in [("foo(a, b)", "foo(a, c)", "b", "c"), ("let x = 10", "let x = 12", "10", "12")] {
            let changes = WordDiff.ranges(before: before, after: after)!
            precondition(changes.removed.map { (before as NSString).substring(with: $0) } == [removed])
            precondition(changes.inserted.map { (after as NSString).substring(with: $0) } == [inserted])
        }
        let oldUnicode = "let 🌿 = café + café\n", newUnicode = "let 🌿 = café + cacao\n"
        let unicode = WordDiff.ranges(before: oldUnicode, after: newUnicode)!
        precondition(unicode.removed.map { (oldUnicode as NSString).substring(with: $0) } == ["café"])
        precondition(unicode.inserted.map { (newUnicode as NSString).substring(with: $0) } == ["cacao"])
        precondition(WordDiff.ranges(before: String(repeating: "a ", count: 2048), after: "a b") == nil)
    }
    func testRealRepositoryStreamsAndRootDeduplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) throws { _ = try Git.run(args, at: root) }
        try git(["init", "-q"])
        try git(["config", "user.name", "Fixture"]); try git(["config", "user.email", "fixture@example.invalid"])
        let file = root.appendingPathComponent("note.txt")
        try Data("head\n".utf8).write(to: file)
        try git(["add", "."]); try git(["commit", "-qm", "Fixture"])
        try Data("index\n".utf8).write(to: file); try git(["add", "."])
        try Data("disk\n".utf8).write(to: file)
        try Data([0x00, 0xff]).write(to: root.appendingPathComponent("binary.bin"))
        let snapshot = try RepositorySnapshot.load(root)
        precondition(snapshot.changes.filter { $0.path == "note.txt" }.count == 2)
        precondition(snapshot.head["note.txt"] == Data("head\n".utf8))
        precondition(snapshot.index["note.txt"] == Data("index\n".utf8))
        precondition(snapshot.files["note.txt"] == Data("disk\n".utf8))
        precondition(snapshot.changes.first { $0.path == "binary.bin" }?.status == "U")
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        precondition(Git.root(containing: link) == Git.root(containing: file))
        precondition(Git.root(containing: root.appendingPathComponent("missing")) == nil)
        precondition(!(FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/index.lock").path)))
    }
    func testGitMetadataIncludesAliasesAndRepositoryLayouts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func repository(_ path: String, bare: Bool) throws -> URL {
            let url = root.appendingPathComponent(path)
            for directory in ["objects", "refs"] { try FileManager.default.createDirectory(at: url.appendingPathComponent(directory), withIntermediateDirectories: true) }
            try Data("ref: refs/heads/main\n".utf8).write(to: url.appendingPathComponent("HEAD"))
            try Data("[core]\nrepositoryformatversion = 0\nbare = \(bare)\n".utf8).write(to: url.appendingPathComponent("config"))
            return url
        }
        let ordinary = try repository("working/.git", bare: false)
        let bare = try repository("archive.git", bare: true)
        let separate = try repository("metadata", bare: false)
        let work = root.appendingPathComponent("separate-work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Data("gitdir: \(separate.path)\n".utf8).write(to: work.appendingPathComponent(".git"))
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: separate)
        for url in [ordinary, bare, separate, ordinary.appendingPathComponent("config"), bare.appendingPathComponent("HEAD"), bare.appendingPathComponent("objects/new"), separate.appendingPathComponent("config"), alias.appendingPathComponent("config"), work.appendingPathComponent(".git"), ordinary.appendingPathComponent("new/deep/file")] {
            precondition(Git.isMetadata(url), url.path)
        }
        let externalConfig = root.appendingPathComponent("config-source")
        let config = bare.appendingPathComponent("config")
        try FileManager.default.moveItem(at: config, to: externalConfig)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: externalConfig)
        precondition(Git.isMetadata(config))
        precondition(!Git.isMetadata(externalConfig))
        try Data("[broken\n".utf8).write(to: externalConfig)
        precondition(Git.isMetadata(bare.appendingPathComponent("HEAD")))
        precondition(Git.isMetadata(config))
        let ordinaryFile = root.appendingPathComponent("working/note.txt")
        let sibling = root.appendingPathComponent("metadata-notes/note.txt")
        for url in [ordinaryFile, sibling, root.appendingPathComponent("working/.gitignore"), root.appendingPathComponent("outside.txt")] {
            precondition(!Git.isMetadata(url), url.path)
        }
        let changingAlias = root.appendingPathComponent("changing-alias")
        try Data("note\n".utf8).write(to: ordinaryFile)
        try FileManager.default.createSymbolicLink(at: changingAlias, withDestinationURL: ordinaryFile)
        precondition(!Git.isMetadata(changingAlias))
        try FileManager.default.removeItem(at: changingAlias)
        try FileManager.default.createSymbolicLink(at: changingAlias, withDestinationURL: bare.appendingPathComponent("HEAD"))
        precondition(Git.isMetadata(changingAlias))
        let linked = separate.appendingPathComponent("worktrees/review")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try Data("ref: refs/heads/review\n".utf8).write(to: linked.appendingPathComponent("HEAD"))
        try Data("../..\n".utf8).write(to: linked.appendingPathComponent("commondir"))
        try Data("\(work.path)/.git\n".utf8).write(to: linked.appendingPathComponent("gitdir"))
        precondition(Git.isMetadata(linked.appendingPathComponent("HEAD")))
        precondition(Git.isMetadata(URL(fileURLWithPath: "/private" + bare.appendingPathComponent("HEAD").path)))
        for name in ["archive\n", "archive\r"] {
            let unusual = try repository(name, bare: true)
            precondition(Git.isMetadata(unusual.appendingPathComponent("HEAD")))
        }
        let legacy = try repository("legacy.git", bare: true)
        try FileManager.default.removeItem(at: legacy.appendingPathComponent("HEAD"))
        try FileManager.default.createSymbolicLink(atPath: legacy.appendingPathComponent("HEAD").path, withDestinationPath: "refs/heads/main")
        precondition(Git.isMetadata(legacy.appendingPathComponent("config")))
    }

    func testMarkdownDiffPreservesProseAndChangedBlocks() {
        let before = "# Ledger\n\nA **clear** paragraph with café 🌿.\n\n- First\n- Second\n\n```swift\nlet total = 40\n```\n"
        let after = before.replacingOccurrences(of: "clear", with: "short").replacingOccurrences(of: "40", with: "45")
        let changes = MarkdownDiff.changes(before: before, after: after)
        precondition(changes.map(\.kind) == [.context, .deletion, .addition, .context, .deletion, .addition])
        let rendered = changes.map { String($0.block.content.characters) }
        precondition(rendered[0] == "Ledger")
        precondition(rendered[1] == "A clear paragraph with café 🌿.")
        precondition(rendered[2] == "A short paragraph with café 🌿.")
        precondition(rendered[3] == "FirstSecond")
        precondition(rendered[4] == "let total = 40\n" && rendered[5] == "let total = 45\n")
        precondition(changes[2].block.content.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        precondition(changes[4].oldLine == 8 && changes[5].newLine == 8)
        precondition(MarkdownDiff.changes(before: before, after: "").allSatisfy { $0.kind == .deletion })
        precondition(MarkdownDiff.changes(before: "", after: after).allSatisfy { $0.kind == .addition })
        precondition(MarkdownDiff.changes(before: before, after: before).allSatisfy { $0.kind == .context })
        let reference = "[Guide][guide]\n\n[guide]: https://example.invalid\n"
        precondition(MarkdownDiff.blocks(reference).first?.content.runs.first?.link?.absoluteString == "https://example.invalid")
        let links = "[Guide][g]\n\nOther text.\n\n[g]: https://example.invalid/one\n"
        let linkChanges = MarkdownDiff.changes(before: links, after: links.replacingOccurrences(of: "/one", with: "/two"))
        precondition(linkChanges.map(\.kind) == [.deletion, .addition, .context])
        precondition(linkChanges[1].block.content.runs.first?.link?.absoluteString == "https://example.invalid/two")
        precondition(MarkdownDiff.changes(before: "# Heading\n", after: "## Heading\n").map(\.kind) == [.deletion, .addition])
        precondition(MarkdownDiff.changes(before: "1. First\n2. Second\n", after: "3. First\n4. Second\n").map(\.kind) == [.deletion, .addition])
        precondition(MarkdownDiff.changes(before: "A paragraph.\n", after: "A\nparagraph.\n").map(\.kind) == [.context])
        precondition(MarkdownDiff.changes(before: "- ab\n- c\n", after: "- a\n- bc\n").map(\.kind) == [.deletion, .addition])
        precondition(MarkdownDiff.changes(before: "|ab|c|\n|-|-|\n|d|e|\n", after: "|a|bc|\n|-|-|\n|d|e|\n").map(\.kind) == [.deletion, .addition])
    }
}

let suite = CoreTests()
suite.testStatusSeparatesStreamsAndRenamePaths()
suite.testEncodingPreservesCRLFAndFinalNewline()
suite.testNonUTF8AndBinaryAreReadOnly()
suite.testWordHighlightRequiresSimilarContent()
try suite.testRealRepositoryStreamsAndRootDeduplication()
try suite.testGitMetadataIncludesAliasesAndRepositoryLayouts()
suite.testMarkdownDiffPreservesProseAndChangedBlocks()
print("PASS: seven core contracts, including Git metadata protection and Markdown block changes")
