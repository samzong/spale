import AppKit
import SpaleCore

private final class TreeNode {
    let path: String
    var entry: FolderEntry?
    var message: String?
    var children: [TreeNode] = []
    init(path: String, entry: FolderEntry? = nil, message: String? = nil) { self.path = path; self.entry = entry; self.message = message }
}

private final class TreeRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        Theme.selection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

final class FileTree: Surface, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let root: URL
    let outline = NSOutlineView()
    let scroll = NSScrollView()
    let heading = ActionButton("FILES", action: {})
    var onOpen: ((String) -> Void)?
    var onCollapse: (() -> Void)?
    var collapsed = false
    private let trunk = TreeNode(path: "")
    private var nodes: [String: TreeNode] = [:]
    private var expanded: Set<String> = []
    var expandedPaths: [String] { Array(expanded) }
    func restore(expanded paths: [String], collapsed: Bool) {
        expanded = Set(paths)
        self.collapsed = collapsed; updateHeading(); refresh()
    }
    private var selected: String?
    private var applying = false
    private var revision = 0
    private var refreshing = false
    private var refreshAgain = false
    private let worker = DispatchQueue(label: "spale.tree", qos: .userInitiated)

    init(root: URL) {
        self.root = root
        super.init(frame: .zero)
        nodes[""] = trunk
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.headerView = nil; outline.rowHeight = 30; outline.intercellSpacing = .zero
        outline.backgroundColor = .clear; outline.indentationPerLevel = 14
        outline.style = .plain; outline.focusRingType = .none
        outline.autoresizesOutlineColumn = false
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.dataSource = self; outline.delegate = self
        outline.target = self; outline.action = #selector(clicked)
        outline.setAccessibilityLabel("Files")
        scroll.documentView = outline; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        heading.alignment = .left
        heading.actionBlock = { [weak self] in
            guard let self else { return }
            self.collapsed.toggle(); self.updateHeading(); self.onCollapse?(); self.window?.invalidateRestorableState()
        }
        addSubview(heading); addSubview(scroll)
        updateHeading(); refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func updateHeading() {
        heading.title = ""
        heading.image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        heading.imagePosition = .imageLeading
        heading.attributedTitle = NSAttributedString(string: "  FILES", attributes: [.font: Theme.ui, .foregroundColor: Theme.muted])
        heading.setAccessibilityLabel(collapsed ? "Expand files" : "Collapse files")
        scroll.isHidden = collapsed
    }
    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 8, y: 4, width: 304, height: 32)
        scroll.frame = NSRect(x: 8, y: 40, width: max(0, bounds.width - 16), height: max(0, bounds.height - 40))
        outline.tableColumns.first?.width = max(0, scroll.contentSize.width)
    }
    func select(_ path: String?) {
        selected = path
        applying = true
        defer { applying = false }
        if let path, let node = nodes[path], outline.row(forItem: node) >= 0 { outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: node)), byExtendingSelection: false) }
        else { outline.deselectAll(nil) }
    }
    func refresh() {
        revision += 1
        if refreshing { refreshAgain = true; return }
        refreshing = true
        let token = revision, paths = expanded.union([""]).filter { path in
            path.isEmpty || (expanded.contains(path) && path.split(separator: "/").indices.dropFirst().allSatisfy { depth in
                expanded.contains(path.split(separator: "/").prefix(depth).joined(separator: "/"))
            })
        }, root = root
        worker.async { [weak self] in
            let results = paths.map { path in (path, Result { try FolderListing.load(root: root, path: path) }) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                defer {
                    if self.refreshAgain { self.refreshAgain = false; self.refresh() }
                }
                guard self.revision == token else { return }
                self.applying = true
                for (path, result) in results.sorted(by: { $0.0.count < $1.0.count }) {
                    guard let parent = self.nodes[path] else { continue }
                    switch result {
                    case .success(let listing):
                        parent.children = listing.entries.map { entry in
                            let node = self.nodes[entry.path] ?? TreeNode(path: entry.path)
                            node.entry = entry; self.nodes[entry.path] = node
                            return node
                        }
                        if listing.truncated { parent.children.append(TreeNode(path: path, message: "Only the first 2,000 items are shown.")) }
                        else if listing.entries.isEmpty && path.isEmpty { parent.children = [TreeNode(path: path, message: "This folder is empty.")] }
                    case .failure:
                        parent.children = [TreeNode(path: path, message: "This folder is unavailable.")]
                    }
                }
                var retained: Set<String> = [""]
                var pending = self.trunk.children
                while let node = pending.popLast() { retained.insert(node.path); pending.append(contentsOf: node.children) }
                self.expanded = self.expanded.filter { retained.contains($0) && self.nodes[$0]?.entry?.isEmpty == false }
                self.nodes = self.nodes.filter { retained.contains($0.key) }
                self.outline.reloadData()
                for path in self.expanded.sorted(by: { $0.count < $1.count }) {
                    if let node = self.nodes[path] { if !self.outline.isItemExpanded(node) { self.animate { self.outline.animator().expandItem(node) } } }
                }
                self.applying = false
                self.select(self.selected)
            }
        }
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { ((item as? TreeNode) ?? trunk).children.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? TreeNode) ?? trunk).children[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let entry = (item as? TreeNode)?.entry else { return false }
        return entry.isDirectory && !entry.isSymbolicLink && !entry.isEmpty
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode else { return nil }
        let color = node.message != nil || node.entry?.isHidden == true ? Theme.muted : Theme.strong
        let text = label(node.message ?? (node.path as NSString).lastPathComponent, color: color, font: node.message == nil ? Theme.row : Theme.ui)
        text.lineBreakMode = .byTruncatingTail
        text.toolTip = node.message ?? node.path
        guard let entry = node.entry else { return text }
        let icon = NSImageView(image: NSImage(systemSymbolName: entry.isDirectory ? "folder" : entry.isSymbolicLink ? "arrow.turn.up.right" : "doc", accessibilityDescription: nil)!)
        icon.contentTintColor = Theme.muted
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let row = NSStackView(views: [icon, text]); row.spacing = 8; row.orientation = .horizontal
        return row
    }
    private func animate(_ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.reducedMotion ? 0 : 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
            changes()
        }
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { TreeRow() }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as? TreeNode)?.entry?.isDirectory == false }
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !applying, let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        guard expanded.insert(node.path).inserted else { return }
        window?.invalidateRestorableState()
        refresh()
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !applying, let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        expanded = expanded.filter { $0 != node.path && !$0.hasPrefix(node.path + "/") }
        for path in nodes.keys where path.hasPrefix(node.path + "/") { nodes.removeValue(forKey: path) }
        node.children = []
        window?.invalidateRestorableState()
    }
    @objc private func clicked() {
        guard !applying, let node = outline.item(atRow: outline.clickedRow) as? TreeNode, let entry = node.entry else { return }
        if entry.isDirectory {
            if !entry.isEmpty {
                if outline.isItemExpanded(node) { animate { outline.animator().collapseItem(node) } }
                else { expanded.insert(node.path); refresh() }
            }
        } else { selected = node.path; onOpen?(node.path) }
    }
}
