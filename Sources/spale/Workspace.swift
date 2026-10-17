import AppKit
import SpaleCore

final class WorkspaceWindow: NSWindow {
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        guard let workspace = windowController as? Workspace else { return }
        coder.encode((workspace.root ?? workspace.standalone?.fileURL)?.path, forKey: "spalePath")
        coder.encode(workspace.fullPath, forKey: "spaleFullPath")
        coder.encode(workspace.stream.rawValue, forKey: "spaleStream")
        coder.encode(workspace.sidebarVisible, forKey: "spaleSidebar")
    }
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        guard let workspace = windowController as? Workspace else { return }
        workspace.fullPath = coder.decodeObject(of: NSString.self, forKey: "spaleFullPath") as String?
        if let stream = coder.decodeObject(of: NSString.self, forKey: "spaleStream") as String? {
            workspace.stream = SpaleCore.Stream(rawValue: stream) ?? .unstaged
        }
        workspace.sidebarVisible = coder.decodeBool(forKey: "spaleSidebar")
        workspace.recompute(); workspace.layout()
    }
}

final class WorkspaceRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder, completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        guard let path = state.decodeObject(of: NSString.self, forKey: "spalePath") as String?,
              FileManager.default.fileExists(atPath: path), let app = AppDelegate.shared else { completionHandler(nil, nil); return }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        app.open(url)
        let workspace = app.workspaces.first { ($0.root ?? $0.standalone?.fileURL) == url }
        completionHandler(workspace?.window, nil)
    }
}

final class Workspace: NSWindowController, NSWindowDelegate {
    let root: URL?
    var standalone: FileBuffer?
    var snapshot: RepositorySnapshot?
    var externalCues: [String: (Date, Set<Int>)] = [:]
    var sidebarCounts: [String: (Int, Int)] = [:]
    var stream: SpaleCore.Stream = .unstaged
    var fullPath: String?
    var selectedPath: String?
    var buffers: [String: FileBuffer] = [:]
    var sections: [String: FileSection] = [:]
    var visibleSections: [FileSection] = []
    var watcher: Watcher?
    var sidebarVisible = true
    var busy = false
    var refreshAgain = false
    var generation = 0
    let worker = DispatchQueue(label: "spale.repository", qos: .userInitiated)
    let surface = Surface()
    let chrome = Surface()
    let titleLabel = label("")
    let sidebar = Surface()
    let sidebarScroll = NSScrollView()
    let sidebarContent = Surface()
    let reader = NSScrollView()
    let readerContent = Surface()
    let windowBar = Surface()
    let back = ActionButton("Back", symbol: "arrow.left", action: {})
    let previous = ActionButton("Previous change", symbol: "chevron.up", action: {})
    let next = ActionButton("Next change", symbol: "chevron.down", action: {})
    let fullButton = ActionButton("Read full file", symbol: "doc.text", action: {})
    var scrollPositions: [String: NSPoint] = [:]
    var afterLayout: (() -> Void)?
    var shown = false
    var pendingCaret: (String, Int)?
    var displayName: String { snapshot?.name ?? standalone?.fileURL?.lastPathComponent ?? "Untitled" }
    var edited: Bool { allBuffers.contains { $0.isDocumentEdited } }
    var allBuffers: [FileBuffer] { standalone.map { [$0] } ?? Array(buffers.values) }
    var stateKey: String { fullPath.map { "full:\($0)" } ?? stream.rawValue }

    init(root: URL?, file: URL? = nil, data: Data? = nil) {
        self.root = root
        let window = WorkspaceWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 420)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; window.contentView = surface; window.center()
        window.isRestorable = true; window.restorationClass = WorkspaceRestoration.self
        window.identifier = NSUserInterfaceItemIdentifier((root ?? file)?.path ?? UUID().uuidString)
        window.backgroundColor = Theme.bg
        chrome.fill = Theme.bg; sidebar.fill = Theme.bg; windowBar.fill = Theme.bg
        sidebar.rightBorder = true; windowBar.topBorder = true
        sidebar.wantsLayer = true; sidebar.clipsToBounds = true
        [chrome, sidebar, reader, windowBar].forEach { surface.addSubview($0) }
        [titleLabel, back, previous, next, fullButton].forEach { chrome.addSubview($0) }
        titleLabel.font = Theme.uiMedium
        sidebar.addSubview(sidebarScroll)
        sidebarScroll.documentView = sidebarContent; sidebarScroll.hasVerticalScroller = true; sidebarScroll.autohidesScrollers = true; sidebarScroll.drawsBackground = false
        reader.documentView = readerContent; reader.hasVerticalScroller = true; reader.autohidesScrollers = true
        reader.drawsBackground = false; reader.contentView.drawsBackground = false
        readerContent.postsFrameChangedNotifications = true
        back.actionBlock = { [weak self] in self?.returnToStream() }
        previous.actionBlock = { [weak self] in self?.navigate(-1) }
        next.actionBlock = { [weak self] in self?.navigate(1) }
        fullButton.actionBlock = { [weak self] in self?.openFull(self?.selectedPath ?? self?.visibleSections.first?.path) }
        if let root {
            if let file, file.path.hasPrefix(root.path + "/") {
                let path = String(file.path.dropFirst(root.path.count + 1)); fullPath = path; selectedPath = path
            }
            refresh()
        } else {
            let initial = data ?? file.flatMap { try? Data(contentsOf: $0) } ?? Data()
            standalone = FileBuffer(url: file, data: initial)
            standalone?.didChange = { [weak self] in self?.renderStandalone() }
            if let file { watcher = Watcher(paths: [file.deletingLastPathComponent().path]) { [weak self] in
                guard let self, let buffer = self.standalone, let url = buffer.fileURL else { return }
                if buffer.receive((try? Data(contentsOf: url)) ?? Data()) { self.renderStandalone() }
            } }
            renderStandalone()
        }
        layout()
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        shown = true
        layout(); AppDelegate.shared?.updateWindowBars()
    }
    func windowDidResize(_ notification: Notification) { layout() }
    func windowDidBecomeKey(_ notification: Notification) { AppDelegate.shared?.updateWindowBars() }
    func windowWillClose(_ notification: Notification) {
        watcher = nil
        allBuffers.forEach { NSDocumentController.shared.removeDocument($0) }
        AppDelegate.shared?.remove(self)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard edited else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "Your unsaved changes will be lost."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Don’t Save")
        alert.beginSheetModal(for: sender) { [weak self] result in
            guard let self else { return }
            if result == .alertThirdButtonReturn { self.allBuffers.forEach { $0.updateChangeCount(.changeCleared) }; sender.close() }
            else if result == .alertFirstButtonReturn { self.saveAll { if $0 { sender.close() } } }
        }
        return false
    }

    func refresh() {
        guard let root else { return }
        if busy { refreshAgain = true; return }
        busy = true
        let extra = Set(buffers.keys).union(fullPath.map { [$0] } ?? [])
        let priorFiles = snapshot?.files
        let observedAt = ProcessInfo.processInfo.systemUptime
        worker.async { [weak self] in
            let result = Result {
                let snapshot = try RepositorySnapshot.load(root, extraPaths: extra)
                let counts = Dictionary(uniqueKeysWithValues: snapshot.changes.map { change in
                    let before = TextContent((change.stream == .staged ? snapshot.head : snapshot.index)[change.path] ?? Data()).text
                    let after = TextContent((change.stream == .staged ? snapshot.index : snapshot.files)[change.path] ?? Data()).text
                    let rows = LineDiff.rows(before: before, after: after)
                    return (change.stream.rawValue + ":" + change.path, (rows.filter { $0.kind == .addition }.count, rows.filter { $0.kind == .deletion }.count))
                })
                var cues: [String: Set<Int>] = [:]
                if let priorFiles {
                    for (path, data) in snapshot.files where priorFiles[path] != nil && priorFiles[path] != data {
                        let rows = LineDiff.rows(before: TextContent(priorFiles[path]!).text, after: TextContent(data).text)
                        cues[path] = Set(rows.filter { $0.kind == .addition }.compactMap(\.newLine))
                    }
                }
                return (snapshot, counts, cues)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let result):
                    let (snapshot, counts, cues) = result
                    if self.buffers.values.contains(where: { $0.lastSavedAt > observedAt }) {
                        self.refreshAgain = false; self.refresh(); return
                    }

                    self.sidebarCounts = counts
                    var changed = Set<String>()
                    for (path, data) in snapshot.files {
                        if let buffer = self.buffers[path] {
                            if buffer.receive(data, observedAt: observedAt) {
                                changed.insert(path)
                                if let lines = cues[path], !buffer.conflict { self.externalCues[path] = (Date(), lines) }
                            }
                        }
                    }
                    self.snapshot = snapshot
                    if self.watcher == nil {
                        self.watcher = Watcher(paths: Array(Set([root.path, snapshot.gitDirectory.path, snapshot.commonDirectory.path]))) { [weak self] in self?.refresh() }
                    }
                    for path in changed { self.sections.values.filter { $0.path == path }.forEach { $0.collapsed = false } }
                    self.recompute()
                case .failure(let error):
                    self.showMessage(error.localizedDescription)
                }
                if self.refreshAgain { self.refreshAgain = false; self.refresh() }
            }
        }
    }

    func buffer(for path: String) -> FileBuffer {
        if let buffer = buffers[path] { return buffer }
        let buffer = FileBuffer(url: root?.appendingPathComponent(path), data: snapshot?.files[path] ?? Data())
        buffer.path = path
        bind(buffer)
        buffers[path] = buffer
        return buffer
    }

    func bind(_ buffer: FileBuffer) {
        buffer.didChange = { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            for section in self.visibleSections where section.buffer === buffer { section.synchronize() }
            self.layout(); self.recompute()
        }
    }

    func recompute() {
        guard let snapshot else { return }
        generation += 1
        let token = generation, currentStream = stream, currentFull = fullPath
        var changes = snapshot.changes.filter { $0.stream == currentStream }
        if currentStream == .unstaged {
            for (path, buffer) in buffers where buffer.isDocumentEdited && !changes.contains(where: { $0.path == path }) {
                changes.append(Change(path: path, status: "M", stream: .unstaged))
            }
        }
        if let path = currentFull { changes = [snapshot.changes.first { $0.path == path } ?? Change(path: path, status: "M", stream: .unstaged)] }
        changes.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let entries = changes.map { change -> (Change, String, String, Bool) in
            let buffer = buffer(for: change.path)
            let before = TextContent((currentFull != nil || currentStream == .staged ? snapshot.head : snapshot.index)[change.path] ?? Data()).text
            let after = currentFull != nil || currentStream == .unstaged ? buffer.text : TextContent(snapshot.index[change.path] ?? Data()).text
            return (change, before, after, buffer.isDocumentEdited)
        }
        updateTitle(); buildSidebar()
        worker.async { [weak self] in
            let rendered = entries.map { ($0.0, LineDiff.rows(before: $0.1, after: $0.2), $0.1 == $0.2, $0.3) }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                if currentFull == nil && currentStream == .unstaged, let match = rendered.first(where: { $0.2 && $0.3 }) {
                    if let section = self.visibleSections.first(where: { $0.path == match.0.path }) {
                        let position = section.caretAfterEdit ?? Projection.sourceRange(for: section.code.selectedRange(), segments: section.segments, sourceLength: (section.buffer.text as NSString).length)?.location ?? 0
                        self.pendingCaret = (match.0.path, position)
                    }
                    self.fullPath = match.0.path; self.selectedPath = match.0.path; self.recompute(); return
                }
                for (change, rows, _, _) in rendered where currentFull == nil {
                    self.sidebarCounts[currentStream.rawValue + ":" + change.path] = (rows.filter { $0.kind == .addition }.count, rows.filter { $0.kind == .deletion }.count)
                }
                self.apply(rendered.map { ($0.0, $0.1) })
                self.buildSidebar()
            }
        }
    }

    var currentCueAllowed: Bool { stream == .unstaged || fullPath != nil }

    func apply(_ renders: [(Change, [DiffRow])]) {
        let anchor = captureAnchor()
        let responder = window?.firstResponder
        visibleSections.forEach { $0.removeFromSuperview() }
        visibleSections = []
        readerContent.subviews.filter { !($0 is FileSection) }.forEach { $0.removeFromSuperview() }
        for (change, rows) in renders {
            let key = stateKey + ":" + change.path
            let section = sections[key] ?? FileSection(key: key, path: change.path, buffer: buffer(for: change.path))
            sections[key] = section
            section.header.topBorder = !visibleSections.isEmpty
            section.onCollapse = { [weak self] in self?.layout() }
            section.onFocus = { [weak self] in self?.selectedPath = change.path }
            section.code.escape = { [weak self] in self?.returnToStream() }
            let wasResponder = responder === section.code
            let data = stream == .staged && fullPath == nil ? snapshot?.index[change.path] ?? Data() : section.buffer.diskData
            if stream == .staged && fullPath == nil { section.buffer = FileBuffer(url: nil, data: data, register: false) }
            if let caret = pendingCaret, caret.0 == change.path { section.caretAfterEdit = caret.1 }
            if currentCueAllowed, let cue = externalCues[change.path], !section.buffer.conflict {
                section.code.showCue(started: cue.0, lines: cue.1)
            }
            section.configure(rows: rows, status: change.status, title: change.label, full: fullPath != nil, readOnly: stream == .staged && fullPath == nil || change.status == "D" && fullPath == nil)
            readerContent.addSubview(section); visibleSections.append(section)
            if wasResponder || pendingCaret?.0 == change.path { window?.makeFirstResponder(section.code) }
            if pendingCaret?.0 == change.path { pendingCaret = nil }
        }
        if renders.isEmpty {
            let clean = snapshot?.changes.isEmpty == true
            showMessage(clean ? "No changes. A little room to think." : stream == .staged ? "No staged changes." : "No unstaged changes.")
        }
        layout()
        restoreAnchor(anchor)
        if let afterLayout { self.afterLayout = nil; afterLayout() }
        AppDelegate.shared?.updateWindowBars()
    }

    func renderStandalone() {
        guard let buffer = standalone else { return }
        let section = sections["single"] ?? FileSection(key: "single", path: buffer.path, buffer: buffer)
        sections["single"] = section
        section.configure(rows: LineDiff.rows(before: buffer.content.text, after: buffer.text), status: "M", title: "", full: true, readOnly: false, single: true)
        if section.superview == nil { readerContent.addSubview(section) }
        visibleSections = [section]; layout(); updateTitle(); AppDelegate.shared?.updateWindowBars()
    }

    func buildSidebar() {
        sidebarContent.subviews.forEach { $0.removeFromSuperview() }
        guard let snapshot else { return }
        let unique = Set(snapshot.changes.map(\.path)).count
        let heading = label("CHANGED FILES", color: Theme.muted)
        heading.frame = NSRect(x: 16, y: 16, width: 240, height: 18)
        sidebarContent.addSubview(heading)
        let count = label("\(unique)", color: Theme.muted); count.alignment = .right
        count.frame = NSRect(x: 270, y: 16, width: 30, height: 18); sidebarContent.addSubview(count)
        var y: CGFloat = 46
        for group in SpaleCore.Stream.allCases {
            let groupButton = ActionButton(group == .staged ? "Staged" : "Unstaged") { [weak self] in self?.switchStream(group) }
            groupButton.title = ""
            let groupTitle = label(group == .staged ? "Staged" : "Unstaged", color: group == stream ? Theme.strong : Theme.muted, font: group == stream ? Theme.uiMedium : Theme.ui)
            groupTitle.frame = NSRect(x: 8, y: 8, width: 288, height: 18)
            groupButton.addSubview(groupTitle)
            groupButton.frame = NSRect(x: 8, y: y, width: 304, height: 34)
            sidebarContent.addSubview(groupButton); y += 34
            for change in snapshot.changes.filter({ $0.stream == group }) {
                let button = ActionButton(change.label) { [weak self] in
                    guard let self else { return }
                    self.selectedPath = change.path
                    if self.fullPath != nil { self.fullPath = change.path; self.recompute() }
                    else {
                        self.switchStream(group)
                        self.afterLayout = { [weak self] in self?.scrollToFile(change.path) }
                        self.scrollToFile(change.path)
                    }
                }
                button.alignment = .left
                let text = NSMutableAttributedString(string: "\(change.status)  ", attributes: [.font: Theme.ui, .foregroundColor: change.status == "A" || change.status == "U" ? Theme.add : change.status == "D" ? Theme.remove : change.status == "R" ? Theme.number : Theme.muted])
                let name = change.oldPath == nil ? (change.path as NSString).lastPathComponent : change.label
                text.append(NSAttributedString(string: name, attributes: [.font: Theme.row, .foregroundColor: Theme.strong]))
                let directory = (change.path as NSString).deletingLastPathComponent
                if !directory.isEmpty && change.oldPath == nil { text.append(NSAttributedString(string: "  \(directory)/", attributes: [.font: Theme.ui, .foregroundColor: Theme.muted])) }
                if change.status == "D" { text.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 3, length: text.length - 3)) }
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
                button.attributedTitle = text
                button.cell?.usesSingleLineMode = true
                button.toolTip = change.label
                button.frame = NSRect(x: 16, y: y, width: 196, height: 34)
                if group == stream && change.path == (selectedPath ?? visibleSections.first?.path) {
                    let selected = Surface(frame: NSRect(x: 8, y: y, width: 304, height: 34))
                    selected.fill = Theme.selection; selected.wantsLayer = true; selected.layer?.cornerRadius = 12
                    sidebarContent.addSubview(selected)
                }
                let (plus, minus) = sidebarCounts[group.rawValue + ":" + change.path] ?? (0, 0)
                let counter = label("")
                let numbers = NSMutableAttributedString()
                if plus > 0 { numbers.append(NSAttributedString(string: "+\(plus)", attributes: [.font: Theme.ui, .foregroundColor: Theme.add])) }
                if minus > 0 { numbers.append(NSAttributedString(string: (plus > 0 ? "  " : "") + "−\(minus)", attributes: [.font: Theme.ui, .foregroundColor: Theme.remove])) }
                let countParagraph = NSMutableParagraphStyle()
                countParagraph.alignment = .right
                numbers.addAttribute(.paragraphStyle, value: countParagraph, range: NSRange(location: 0, length: numbers.length))
                counter.attributedStringValue = numbers
                counter.frame = NSRect(x: 228, y: y + 8, width: 76, height: 18)
                sidebarContent.addSubview(counter)
                sidebarContent.addSubview(button); y += 34
            }
        }
        sidebarContent.frame.size = NSSize(width: 320, height: y)
    }

    func layout(animated: Bool = false) {
        guard let window else { return }
        let size = surface.bounds.size, side: CGFloat = root != nil && sidebarVisible ? 320 : 0
        chrome.frame = NSRect(x: 0, y: 0, width: size.width, height: 60)
        titleLabel.frame = NSRect(x: 96, y: 21, width: max(100, size.width - 300), height: 20)
        back.frame = NSRect(x: size.width - 144, y: 16, width: 28, height: 28)
        previous.frame = NSRect(x: size.width - 112, y: 16, width: 28, height: 28)
        next.frame = NSRect(x: size.width - 80, y: 16, width: 28, height: 28)
        fullButton.frame = NSRect(x: size.width - 48, y: 16, width: 28, height: 28)
        back.isHidden = fullPath == nil; previous.isHidden = root == nil; next.isHidden = root == nil; fullButton.isHidden = root == nil
        let sidebarFrame = NSRect(x: 0, y: 60, width: side, height: max(0, size.height - 92))
        let readerFrame = NSRect(x: side, y: 60, width: max(0, size.width - side), height: max(0, size.height - 92))
        sidebarScroll.frame = NSRect(x: 0, y: 0, width: 319, height: sidebarFrame.height)
        if animated && !Theme.reducedMotion {
            sidebar.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.38; context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
                sidebar.animator().frame = sidebarFrame; reader.animator().frame = readerFrame
            } completionHandler: { [weak self] in guard let self else { return }; self.sidebar.isHidden = !self.sidebarVisible }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18; context.timingFunction = CAMediaTimingFunction(name: .linear)
                sidebar.animator().alphaValue = side == 0 ? 0 : 1
            }
        } else {
            sidebar.frame = sidebarFrame; reader.frame = readerFrame
            sidebar.isHidden = side == 0; sidebar.alphaValue = 1
        }
        windowBar.frame = NSRect(x: 0, y: size.height - 32, width: size.width, height: 32)
        let width = NSScrollView.contentSize(forFrameSize: readerFrame.size, horizontalScrollerClass: nil, verticalScrollerClass: NSScroller.self, borderType: reader.borderType, controlSize: .regular, scrollerStyle: reader.scrollerStyle).width
        var y: CGFloat = 0
        for section in visibleSections {
            let height = section.size(width: width)
            section.frame = NSRect(x: 0, y: y, width: width, height: height); y += height
        }
        readerContent.frame.size = NSSize(width: width, height: max(reader.contentSize.height, y + 16))
        for view in readerContent.subviews where view is NSTextField {
            view.frame = NSRect(x: 30, y: max(80, reader.contentSize.height / 2 - 10), width: max(0, width - 60), height: 24)
        }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(kind), button.superview !== chrome { chrome.addSubview(button) }
        }
        window.standardWindowButton(.closeButton)?.setFrameOrigin(NSPoint(x: 20, y: 24))
        window.standardWindowButton(.miniaturizeButton)?.setFrameOrigin(NSPoint(x: 40, y: 24))
        window.standardWindowButton(.zoomButton)?.setFrameOrigin(NSPoint(x: 60, y: 24))
    }

    func updateTitle() {
        let name = displayName + (edited ? "  ●" : "")
        let title = NSMutableAttributedString(string: name, attributes: [.font: Theme.uiMedium, .foregroundColor: Theme.fg])
        if let snapshot { title.append(NSAttributedString(string: "  \(snapshot.branch)", attributes: [.font: Theme.ui, .foregroundColor: Theme.muted])) }
        titleLabel.attributedStringValue = title
        window?.title = name; window?.isDocumentEdited = edited
    }
    func updateWindowBar(_ workspaces: [Workspace]) {
        windowBar.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 8
        for workspace in workspaces {
            let button = ActionButton(workspace.displayName + (workspace.edited ? "  ●" : "")) { workspace.show() }
            button.cell?.usesSingleLineMode = true
            let width = min(280, button.intrinsicContentSize.width + 32)
            button.frame = NSRect(x: x, y: 4, width: width, height: 24)
            if workspace === self {
                let selected = Surface(frame: button.frame)
                selected.fill = Theme.selection; selected.wantsLayer = true; selected.layer?.cornerRadius = 8
                windowBar.addSubview(selected)
            }
            windowBar.addSubview(button); x += width
        }
    }
    func showMessage(_ text: String) {
        readerContent.subviews.filter { !($0 is FileSection) }.forEach { $0.removeFromSuperview() }
        let field = label(text, color: Theme.muted, font: Theme.message)
        field.alignment = .center; readerContent.addSubview(field); layout()
    }
    func switchStream(_ value: SpaleCore.Stream) {
        scrollPositions[stateKey] = reader.contentView.bounds.origin
        stream = value; fullPath = nil
        afterLayout = { [weak self] in guard let self else { return }; self.reader.contentView.scroll(to: self.scrollPositions[self.stateKey] ?? .zero); self.reader.reflectScrolledClipView(self.reader.contentView) }
        recompute()
    }
    func openFull(_ path: String?) {
        guard let path else { return }
        scrollPositions[stateKey] = reader.contentView.bounds.origin
        fullPath = path; selectedPath = path; recompute()
    }
    func returnToStream() {
        guard fullPath != nil else { return }
        fullPath = nil
        afterLayout = { [weak self] in guard let self else { return }; self.reader.contentView.scroll(to: self.scrollPositions[self.stateKey] ?? .zero); self.reader.reflectScrolledClipView(self.reader.contentView) }
        recompute()
    }
    func scrollToFile(_ path: String) {
        guard let section = visibleSections.first(where: { $0.path == path }) else { return }
        reader.contentView.scroll(to: NSPoint(x: 0, y: section.frame.minY)); reader.reflectScrolledClipView(reader.contentView)
    }
    func navigate(_ direction: Int) {
        let points = visibleSections.filter { !$0.collapsed }.flatMap { section in section.changeOffsets.compactMap { offset -> (CGFloat, String)? in
            guard let manager = section.code.layoutManager, let container = section.code.textContainer else { return nil }
            let rect = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: NSRange(location: offset, length: 1), actualCharacterRange: nil), in: container)
            return (section.frame.minY + section.code.frame.minY + rect.minY, section.path)
        } }
        let y = reader.contentView.bounds.minY
        let target = direction > 0 ? points.first { $0.0 > y + 2 } ?? points.first : points.last { $0.0 < y - 2 } ?? points.last
        if let target { selectedPath = target.1; reader.contentView.scroll(to: NSPoint(x: 0, y: target.0)); reader.reflectScrolledClipView(reader.contentView) }
    }
    func captureAnchor() -> (String, Int, String, CGFloat)? {
        let y = reader.contentView.bounds.minY
        guard let section = visibleSections.first(where: { $0.frame.maxY > y }), let manager = section.code.layoutManager, let container = section.code.textContainer, manager.numberOfGlyphs > 0 else { return nil }
        let point = NSPoint(x: 0, y: max(0, y - section.frame.minY - section.code.frame.minY))
        let glyph = manager.glyphIndex(for: point, in: container)
        let character = manager.characterIndexForGlyph(at: min(glyph, manager.numberOfGlyphs - 1))
        guard let line = section.code.lines.first(where: { NSLocationInRange(character, $0.range) }) else { return nil }
        let box = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: line.range, actualCharacterRange: nil), in: container)
        let text = (section.code.string as NSString).substring(with: line.range)
        return (section.path, line.newLine ?? 0, text, y - section.frame.minY - section.code.frame.minY - box.minY)
    }
    func restoreAnchor(_ anchor: (String, Int, String, CGFloat)?) {
        guard let anchor, let section = visibleSections.first(where: { $0.path == anchor.0 }), let manager = section.code.layoutManager, let container = section.code.textContainer else { return }
        let matches = section.code.lines.filter { (section.code.string as NSString).substring(with: $0.range) == anchor.2 }
        guard let line = matches.min(by: { abs(($0.newLine ?? 0) - anchor.1) < abs(($1.newLine ?? 0) - anchor.1) }) ?? section.code.lines.min(by: { abs(($0.newLine ?? 0) - anchor.1) < abs(($1.newLine ?? 0) - anchor.1) }) else { return }
        let box = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: line.range, actualCharacterRange: nil), in: container)
        reader.contentView.scroll(to: NSPoint(x: 0, y: max(0, section.frame.minY + section.code.frame.minY + box.minY + anchor.3)))
        reader.reflectScrolledClipView(reader.contentView)
    }
    func saveAll(completion: @escaping (Bool) -> Void) {
        let dirty = allBuffers.filter { $0.isDocumentEdited || $0.fileURL == nil }
        func save(_ i: Int) {
            if i == dirty.count { completion(true); return }
            dirty[i].saveNow { if $0 { save(i + 1) } else { completion(false) } }
        }
        save(0)
    }
    @objc func saveDocument(_ sender: Any?) {
        guard stream != .staged || fullPath != nil || root == nil else { return }
        guard let buffer = standalone ?? visibleSections.first(where: { window?.firstResponder === $0.code })?.buffer, buffer.isDocumentEdited || buffer.fileURL == nil else { return }
        buffer.saveNow { _ in self.refresh() }
    }
    @objc func saveDocumentAs(_ sender: Any?) { guard stream != .staged || fullPath != nil || root == nil else { return }; (standalone ?? selectedPath.map { buffer(for: $0) })?.saveAsNow { _ in self.refresh() } }
    @objc func toggleSidebar(_ sender: Any?) { guard root != nil else { return }; sidebarVisible.toggle(); layout(animated: true) }
}
