import AppKit
import SpaleCore

final class FileBuffer: NSDocument {
    var content = TextContent(Data())
    var text = ""
    var diskData = Data()
    var conflict = false
    var unavailable = false
    var lastSavedAt = -Double.infinity
    var path = ""
    var didChange: (() -> Void)?
    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override var autosavingFileType: String? { nil }
    override var isEntireFileLoaded: Bool { true }

    override init() { super.init() }

    convenience init(url: URL?, data: Data, register: Bool = true) {
        self.init()
        fileURL = url; fileType = "public.plain-text"
        content = TextContent(data); text = content.text; diskData = data
        if let url { path = url.path }
        if register { NSDocumentController.shared.addDocument(self) }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        content = TextContent(data); text = content.text; diskData = data
    }

    override func data(ofType typeName: String) throws -> Data { content.encode(text) }

    private func validateDestination(_ url: URL) throws {
        guard content.editable else { throw CocoaError(.fileWriteNoPermission) }
        guard !Git.isMetadata(url) else {
            throw NSError(domain: "us.samzong.spale", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Git metadata is read-only.",
                                     NSLocalizedRecoverySuggestionErrorKey: "Save this text outside the Git metadata directory."])
        }
    }

    override func write(to url: URL, ofType typeName: String) throws {
        try validateDestination(url)
        try content.encode(text).write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        try validateDestination(url)
        try super.writeSafely(to: url.resolvingSymlinksInPath(), ofType: typeName, for: saveOperation)
    }

    func receive(_ data: Data?, observedAt: Double = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard observedAt >= lastSavedAt else { return false }
        guard let data else {
            guard !unavailable else { return false }
            unavailable = true
            return true
        }
        guard unavailable || data != diskData else { return false }
        unavailable = false
        let changed = data != diskData
        diskData = data
        if isDocumentEdited { conflict = conflict || changed }
        else { content = TextContent(data); text = content.text; undoManager?.removeAllActions() }
        return true
    }

    func replace(_ range: NSRange, with replacement: String, manager: UndoManager?) {
        guard content.editable, NSMaxRange(range) <= (text as NSString).length else { return }
        let old = (text as NSString).substring(with: range)
        let newRange = NSRange(location: range.location, length: (replacement as NSString).length)
        manager?.registerUndo(withTarget: self) { target in target.replace(newRange, with: old, manager: manager) }
        text = (text as NSString).replacingCharacters(in: range, with: replacement)
        updateChangeCount(manager?.isUndoing == true ? .changeUndone : .changeDone)
        didChange?()
    }

    func saveNow(completion: @escaping (Bool) -> Void) {
        guard content.editable else { completion(false); return }
        if let url = fileURL { save(to: url, completion: completion) }
        else { saveAsNow(completion: completion) }
    }

    private func save(to url: URL, completion: @escaping (Bool) -> Void) {
        do {
            let data = content.encode(text)
            try write(to: url, ofType: fileType ?? "public.plain-text")
            fileURL = url.resolvingSymlinksInPath(); path = fileURL!.path
            lastSavedAt = ProcessInfo.processInfo.systemUptime
            diskData = data; content = TextContent(data); text = content.text; conflict = false; unavailable = false
            updateChangeCount(.changeCleared); didChange?(); completion(true)
        } catch { NSApp.presentError(error); completion(false) }
    }

    func saveAsNow(completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled"
        panel.begin { [weak self] result in
            guard result == .OK, let self, let url = panel.url else { completion(false); return }
            self.save(to: url, completion: completion)
        }
    }

    func useDisk() {
        guard !unavailable else { return }
        content = TextContent(diskData); text = content.text; conflict = false
        undoManager?.removeAllActions(); updateChangeCount(.changeCleared); didChange?()
    }
}
