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
}

let suite = CoreTests()
suite.testStatusSeparatesStreamsAndRenamePaths()
suite.testEncodingPreservesCRLFAndFinalNewline()
suite.testNonUTF8AndBinaryAreReadOnly()
suite.testWordHighlightRequiresSimilarContent()
try suite.testRealRepositoryStreamsAndRootDeduplication()
print("PASS: five core contracts, including real Git snapshots and file integrity")
