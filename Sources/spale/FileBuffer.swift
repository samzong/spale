import AppKit
import SpaleCore

final class FileBuffer: NSDocument {
    var content = TextContent(Data())
    var text = ""
    var diskData = Data()
    var conflict = false
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

    override func write(to url: URL, ofType typeName: String) throws {
        try content.encode(text).write(to: url, options: .atomic)
    }

    func receive(_ data: Data, observedAt: Double = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard observedAt >= lastSavedAt, data != diskData else { return false }
        diskData = data
        if isDocumentEdited { conflict = true }
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
        if let url = fileURL {
            do {
                let data = content.encode(text)
                try data.write(to: url, options: .atomic)
                lastSavedAt = ProcessInfo.processInfo.systemUptime
                diskData = data; content = TextContent(data); text = content.text; conflict = false
                updateChangeCount(.changeCleared); didChange?(); completion(true)
            } catch { NSApp.presentError(error); completion(false) }
        } else { saveAsNow(completion: completion) }
    }

    func saveAsNow(completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled"
        panel.begin { [weak self] result in
            guard result == .OK, let self, let url = panel.url else { completion(false); return }
            self.fileURL = url; self.path = url.path; self.saveNow(completion: completion)
        }
    }

    func useDisk() {
        content = TextContent(diskData); text = content.text; conflict = false
        undoManager?.removeAllActions(); updateChangeCount(.changeCleared); didChange?()
    }
}
