import AppKit
import CoreText
import SpaleCore

final class CommandHint: NSView {
    override var isFlipped: Bool { true }
    private var text: NSAttributedString {
        let text = NSMutableAttributedString(string: "Run spale . in a terminal.", attributes: [.font: Theme.ui, .foregroundColor: Theme.muted])
        text.addAttributes([.font: Theme.code, .foregroundColor: Theme.soft], range: NSRange(location: 4, length: 7))
        text.addAttribute(.kern, value: 6, range: NSRange(location: 3, length: 1))
        text.addAttribute(.kern, value: 6, range: NSRange(location: 10, length: 1))
        return text
    }
    override var intrinsicContentSize: NSSize { NSSize(width: ceil(text.size().width), height: 22) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text.string)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let text = text
        let line = CTLineCreateWithAttributedString(text)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var command = CGPoint.zero
        var suffix = CGPoint.zero
        CTRunGetPositions(runs.first { CTRunGetStringRange($0).location == 4 }!, CFRange(location: 0, length: 1), &command)
        CTRunGetPositions(runs.first { CTRunGetStringRange($0).location == 11 }!, CFRange(location: 0, length: 1), &suffix)
        let chip = backingAlignedRect(NSRect(x: command.x - 6, y: 0, width: suffix.x - command.x + 6, height: bounds.height), options: .alignAllEdgesNearest)
        Theme.line.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
        text.draw(at: NSPoint(x: 0, y: (bounds.height - text.size().height) / 2))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }
}

final class EmptyView: Surface {
    var opening = false
    var monitor: Any?
    let identity = Surface()
    let mark = ShavingView()
    let word = label("spale", color: Theme.muted, font: Theme.wordmark)
    let hint = CommandHint(frame: .zero)
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(identity); addSubview(hint)
        [mark, word].forEach { identity.addSubview($0) }
        identity.wantsLayer = true; word.wantsLayer = true
        word.alignment = .center
    }
    required init?(coder: NSCoder) { fatalError() }
    var identityFrame: NSRect { NSRect(x: floor(bounds.midX - 64), y: floor(bounds.midY - 57), width: 128, height: 114) }
    override func layout() {
        super.layout()
        identity.frame = identityFrame
        mark.frame = NSRect(x: 28, y: 0, width: 72, height: 72)
        word.frame = NSRect(x: 9, y: 78, width: 110, height: 36)
        let size = hint.intrinsicContentSize
        hint.frame = backingAlignedRect(NSRect(x: bounds.midX - size.width / 2, y: bounds.height - 33 - size.height, width: size.width, height: size.height), options: .alignAllEdgesNearest)
    }
    func playOpening() {
        guard !UserDefaults.standard.bool(forKey: "openingPlayed") else { return }
        UserDefaults.standard.set(true, forKey: "openingPlayed")
        layoutSubtreeIfNeeded()
        opening = true
        [identity, word, hint].forEach { $0.alphaValue = 0 }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.opening, event.window === self.window else { return event }
            self.finishOpening(); return nil
        }
        if Theme.reducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                [self.identity, self.word, self.hint].forEach { $0.animator().alphaValue = 1 }
            } completionHandler: { [weak self] in self?.finishOpening() }
            return
        }
        identity.alphaValue = 1
        mark.layoutSubtreeIfNeeded(); mark.drawStroke()
        let scale: CGFloat = 28 / 22
        let anchor = identity.layer!.anchorPoint
        let pivot = CGPoint(x: identity.bounds.width * (0.5 - anchor.x), y: identity.bounds.height * (0.5 - anchor.y))
        var transform = CATransform3DMakeTranslation(pivot.x * (1 - scale), pivot.y * (1 - scale), 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        let settle = CABasicAnimation(keyPath: "transform")
        settle.fromValue = NSValue(caTransform3D: transform); settle.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        settle.beginTime = CACurrentMediaTime() + 1.1; settle.duration = 0.5; settle.fillMode = .backwards
        settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
        identity.layer?.add(settle, forKey: "opening")
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = word.layer!.position.y + 4 / scale; rise.toValue = word.layer!.position.y
        rise.beginTime = CACurrentMediaTime() + 0.6; rise.duration = 0.5; rise.fillMode = .backwards
        rise.timingFunction = settle.timingFunction
        word.layer?.add(rise, forKey: "opening")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.opening else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18; context.timingFunction = CAMediaTimingFunction(name: .linear)
                self.word.animator().alphaValue = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.opening else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18; context.timingFunction = CAMediaTimingFunction(name: .linear)
                self.hint.animator().alphaValue = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.opening else { return }
            self.finishOpening()
        }
    }
    func finishOpening() {
        opening = false
        [identity, word, hint].forEach { $0.layer?.removeAllAnimations() }
        mark.stroke.removeAllAnimations(); mark.progress = 1
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        [identity, word, hint].forEach { $0.alphaValue = 1 }
    }
}

final class DocumentController: NSDocumentController {
    override func noteNewRecentDocumentURL(_ url: URL) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var workspaces: [Workspace] = []
    var emptyWindow: NSWindow?
    var emptyView: EmptyView?
    var openingURLs = false
    var terminateAfterSave = false
    override init() { super.init(); Self.shared = self }
    func applicationWillFinishLaunching(_ notification: Notification) {
        Theme.registerFonts(); NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular); makeMenu()
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.workspaces.isEmpty else { return }
            if self.workspaces.isEmpty { self.showEmpty() }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "spale", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let path = components.queryItems?.first(where: { $0.name == "path" })?.value { open(URL(fileURLWithPath: path)) }
            else { open(url) }
        }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.forEach { open(URL(fileURLWithPath: $0)) }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { showEmpty() }; return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard workspaces.contains(where: { $0.edited }) else { persist(); return .terminateNow }
        guard let workspace = workspaces.first(where: { $0.edited }), let window = workspace.window else { return .terminateCancel }
        let alert = NSAlert(); alert.messageText = "Save changes before quitting?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Don’t Save")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertThirdButtonReturn { self?.persist(); NSApp.reply(toApplicationShouldTerminate: true) }
            else if response == .alertFirstButtonReturn {
                self?.saveWorkspaces(0) { success in if success { self?.persist() }; NSApp.reply(toApplicationShouldTerminate: success) }
            } else { NSApp.reply(toApplicationShouldTerminate: false) }
        }
        return .terminateLater
    }
    func saveWorkspaces(_ i: Int, completion: @escaping (Bool) -> Void) {
        if i == workspaces.count { completion(true); return }
        workspaces[i].saveAll { [weak self] success in if success { self?.saveWorkspaces(i + 1, completion: completion) } else { completion(false) } }
    }
    func open(_ input: URL) {
        let target: OpenTarget
        do { target = try OpenTarget.resolve(input) }
        catch { showError((error as? CocoaError)?.code == .fileNoSuchFile ? "The path does not exist." : "This folder cannot be opened."); return }
        if let existing = workspaces.first(where: { target.root != nil ? $0.root == target.root : $0.standalone?.fileURL == target.file }) {
            if let root = target.root, let file = target.file { existing.openFull(String(file.path.dropFirst(root.path.count + 1))) }
            existing.show(); return
        }
        let workspace = Workspace(root: target.root, file: target.file, isRepository: target.isRepository)
        workspaces.append(workspace); emptyWindow?.close(); emptyWindow = nil; emptyView = nil
        workspace.show()
        persist()
    }
    func remove(_ workspace: Workspace) { workspaces.removeAll { $0 === workspace }; updateWindowBars(); persist() }
    func updateWindowBars() { workspaces.forEach { $0.updateTitle(); $0.updateWindowBar(workspaces) } }
    func persist() { workspaces.forEach { $0.window?.invalidateRestorableState() } }
    func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = message
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
    func showEmpty() {
        if let emptyWindow { emptyWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "spale"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed; window.isReleasedWhenClosed = false; window.backgroundColor = Theme.bg; window.center()
        let view = EmptyView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        window.contentView = view; emptyWindow = window; emptyView = view
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); view.playOpening()
    }
    @objc func newDocument(_ sender: Any?) {
        let workspace = Workspace(root: nil)
        workspaces.append(workspace); emptyWindow?.close(); emptyWindow = nil; workspace.show()
    }
    @objc func saveDocument(_ sender: Any?) { active?.saveDocument(sender) }
    @objc func saveDocumentAs(_ sender: Any?) { active?.saveDocumentAs(sender) }
    @objc func toggleSidebar(_ sender: Any?) { active?.toggleSidebar(sender) }
    @objc func undo(_ sender: Any?) { active?.visibleSections.first(where: { $0.code === NSApp.keyWindow?.firstResponder })?.buffer.undoManager?.undo() }
    @objc func redo(_ sender: Any?) { active?.visibleSections.first(where: { $0.code === NSApp.keyWindow?.firstResponder })?.buffer.undoManager?.redo() }
    var active: Workspace? { workspaces.first { $0.window === NSApp.keyWindow } }
    func makeMenu() {
        let menu = NSMenu()
        func group(_ title: String) -> NSMenu { let item = NSMenuItem(); let submenu = NSMenu(title: title); item.submenu = submenu; menu.addItem(item); return submenu }
        func item(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String = "", shift: Bool = false, control: Bool = false, target: AnyObject? = nil, tag: Int = 0) {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            var mask: NSEvent.ModifierFlags = [.command]
            if shift { mask.insert(.shift) }
            if control { mask.insert(.control) }
            entry.target = target; entry.keyEquivalentModifierMask = mask; entry.tag = tag
            menu.addItem(entry)
        }
        let app = group("spale")
        item(app, "About spale", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator()); item(app, "Hide spale", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(app, "Quit spale", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = group("File")
        item(file, "New", #selector(newDocument(_:)), "n", target: self)
        file.addItem(.separator()); item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        item(file, "Save", #selector(saveDocument(_:)), "s", target: self)
        item(file, "Save As…", #selector(saveDocumentAs(_:)), "s", shift: true, target: self)
        let edit = group("Edit")
        item(edit, "Undo", #selector(undo(_:)), "z", target: self)
        item(edit, "Redo", #selector(redo(_:)), "z", shift: true, target: self)
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        item(edit, "Find…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: NSTextFinder.Action.showFindInterface.rawValue)
        item(edit, "Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: NSTextFinder.Action.nextMatch.rawValue)
        item(edit, "Find Previous", #selector(NSTextView.performFindPanelAction(_:)), "g", shift: true, tag: NSTextFinder.Action.previousMatch.rawValue)
        let view = group("View"); item(view, "Show or Hide Sidebar", #selector(toggleSidebar(_:)), "b", target: self)
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", control: true)
        let window = group("Window"); item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        NSApp.mainMenu = menu
    }
}
