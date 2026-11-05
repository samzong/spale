import AppKit
import SpaleCore

extension Workspace {
    var changesCollapsed: Bool { changedFilesCollapsed ?? (snapshot?.changes.isEmpty ?? true) }

    func configureChangedHeading() {
        changedHeading.alignment = .left
        changedCount.alignment = .right
        changedCount.setAccessibilityHidden(true)
        changedHeading.addSubview(changedCount)
        sidebar.addSubview(changedHeading)
        changedHeading.actionBlock = { [weak self] in
            guard let self else { return }
            self.changedFilesCollapsed = !self.changesCollapsed
            self.updateChangedHeading()
            self.window?.invalidateRestorableState()
            self.layout(animated: true)
        }
        updateChangedHeading()
    }

    func updateChangedHeading() {
        let count = Set(snapshot?.changes.map(\.path) ?? []).count
        changedHeading.title = ""
        changedHeading.image = Theme.disclosure(collapsed: changesCollapsed)
        changedHeading.imagePosition = .imageLeading
        changedHeading.attributedTitle = NSAttributedString(string: "  CHANGED FILES", attributes: [.font: Theme.ui, .foregroundColor: Theme.muted])
        changedHeading.setAccessibilityLabel(changesCollapsed ? "Expand changed files" : "Collapse changed files")
        changedHeading.setAccessibilityValue("\(count) files")
        changedCount.stringValue = "\(count)"
        sidebarScroll.isHidden = !isRepository || changesCollapsed
    }

    func buildSidebar() {
        sidebarContent.subviews.forEach { $0.removeFromSuperview() }
        fileTree?.select(fullPath)
        updateChangedHeading()
        guard let snapshot else { return }
        var y: CGFloat = 0
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
                button.title = ""
                let text = NSMutableAttributedString(string: "\(change.status)  ", attributes: [.font: Theme.ui, .foregroundColor: change.status == "A" || change.status == "U" ? Theme.add : change.status == "D" ? Theme.remove : change.status == "R" ? Theme.number : Theme.muted])
                let name = change.oldPath == nil ? (change.path as NSString).lastPathComponent : change.label
                text.append(NSAttributedString(string: name, attributes: [.font: Theme.row, .foregroundColor: Theme.strong]))
                let directory = (change.path as NSString).deletingLastPathComponent
                if !directory.isEmpty && change.oldPath == nil { text.append(NSAttributedString(string: "  \(directory)/", attributes: [.font: Theme.ui, .foregroundColor: Theme.muted])) }
                if change.status == "D" { text.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 3, length: text.length - 3)) }
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
                let fileLabel = label("")
                fileLabel.attributedStringValue = text
                fileLabel.frame = NSRect(x: 16, y: y + 8, width: 196, height: 18)
                fileLabel.setAccessibilityHidden(true)
                button.toolTip = change.label
                button.frame = NSRect(x: 8, y: y, width: 304, height: 34)
                button.setAccessibilityLabel("\(change.status) \(change.label)")
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
                counter.setAccessibilityHidden(true)
                button.setAccessibilityHelp(numbers.string)
                sidebarContent.addSubview(fileLabel)
                sidebarContent.addSubview(counter)
                sidebarContent.addSubview(button); y += 34
            }
        }
        sidebarContent.frame.size = NSSize(width: 320, height: y)
    }
}
