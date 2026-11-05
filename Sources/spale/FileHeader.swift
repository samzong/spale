import AppKit

func fittedHeaderPaths(_ path: String, oldPath: String? = nil, width: CGFloat, font: NSFont) -> [String] {
    func measure(_ value: String) -> CGFloat { (value as NSString).size(withAttributes: [.font: font]).width }
    func fits(_ value: String) -> Bool { measure(value) <= width }
    func candidates(_ value: String) -> [String] {
        let parts = value.components(separatedBy: "/")
        var values = [value]
        if parts.count > 2 {
            for start in 1..<(parts.count - 1) { values.append("…/" + parts[start...].joined(separator: "/")) }
        }
        if parts.count > 1 { values.append(parts.last!) }
        return values
    }
    let current = candidates(path)
    if let oldPath {
        let previous = candidates(oldPath)
        var left = 0, right = 0
        while !fits(previous[left] + " → " + current[right]) {
            if left == previous.count - 1 && right == current.count - 1 { break }
            if left < previous.count - 1 && (right == current.count - 1 || measure(previous[left]) >= measure(current[right])) { left += 1 }
            else { right += 1 }
        }
        if fits(previous[left] + " → " + current[right]) { return [previous[left], current[right]] }
    } else if let candidate = current.first(where: fits) { return [candidate] }
    let filename = current.last!
    if fits(filename) { return [filename] }
    guard fits("…") else { return [""] }
    let characters = Array(filename)
    func shortened(_ count: Int) -> String {
        String(characters.prefix((count + 1) / 2)) + "…" + String(characters.suffix(count / 2))
    }
    var low = 0, high = max(0, characters.count - 1)
    while low < high {
        let count = (low + high + 1) / 2
        if fits(shortened(count)) { low = count } else { high = count - 1 }
    }
    return [shortened(low)]
}

extension FileSection {
    func configureHeader(title: String, oldPath: String?, status: Character, changesVisible: Bool) {
        headerTitle = title; headerOldPath = oldPath; headerStatus = status
        headerButton.cell?.wraps = false
        headerButton.cell?.usesSingleLineMode = true
        headerButton.cell?.lineBreakMode = .byClipping
        let additions = rows.filter { $0.kind == .addition }.count, deletions = rows.filter { $0.kind == .deletion }.count
        let text = NSMutableAttributedString(string: additions > 0 ? "+\(additions)" : "", attributes: [.font: Theme.ui, .foregroundColor: Theme.add])
        if deletions > 0 { text.append(NSAttributedString(string: (additions > 0 ? "  " : "") + "−\(deletions)", attributes: [.font: Theme.ui, .foregroundColor: Theme.remove])) }
        counts.attributedTitle = changesVisible ? text : NSAttributedString(string: "")
        layoutHeader(width: contentWidth)
    }

    func layoutHeader(width: CGFloat) {
        let countWidth = ceil(counts.attributedTitle.size().width)
        let gap: CGFloat = countWidth > 0 ? 16 : 0
        counts.frame = NSRect(x: max(16, width - 16 - countWidth), y: 8, width: countWidth, height: 32)
        headerButton.frame = NSRect(x: 16, y: 8, width: max(0, width - 32 - countWidth - gap), height: 32)
        let status = ["A": "Added", "U": "Untracked", "M": "Modified", "D": "Deleted", "R": "Renamed"][String(headerStatus)] ?? ""
        let suffix = NSAttributedString(string: status.isEmpty ? "" : "   " + status, attributes: [.font: Theme.ui, .foregroundColor: Theme.muted])
        let available = headerButton.cell?.titleRect(forBounds: headerButton.bounds).width ?? headerButton.bounds.width
        let paths = fittedHeaderPaths(headerTitle, oldPath: headerOldPath, width: max(0, available - ceil(suffix.size().width)), font: Theme.heading)
        let text = NSMutableAttributedString()
        for (index, path) in paths.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: " → ", attributes: [.font: Theme.heading, .foregroundColor: Theme.strong])) }
            let piece = NSMutableAttributedString(string: path, attributes: [.font: Theme.heading, .foregroundColor: Theme.strong])
            if let slash = path.lastIndex(of: "/") {
                piece.addAttribute(.foregroundColor, value: Theme.muted, range: NSRange(path.startIndex...slash, in: path))
            }
            text.append(piece)
        }
        if headerStatus == "D" { text.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 0, length: text.length)) }
        text.append(suffix)
        headerButton.attributedTitle = text
        let fullTitle = headerOldPath.map { $0 + " → " + headerTitle } ?? headerTitle
        headerButton.toolTip = headerOldPath != nil || paths.joined(separator: " → ") != fullTitle ? fullTitle : nil
        headerButton.setAccessibilityLabel(fullTitle + (status.isEmpty ? "" : ", " + status))
    }

    var showsConflict: Bool { buffer.unavailable ? full || buffer.isDocumentEdited : buffer.conflict }

    func configureConflict() {
        conflictBar.subviews.forEach { $0.removeFromSuperview() }
        conflictBar.isHidden = !showsConflict
        guard !conflictBar.isHidden else { return }
        let title = label(buffer.unavailable ? "File unavailable" : "Changed on disk", color: Theme.modify)
        let keep = ActionButton("Keep my version") { [weak self] in self?.buffer.saveNow { _ in } }
        let disk = ActionButton("Use disk version") { [weak self] in self?.buffer.useDisk() }
        conflictBar.addSubview(title)
        if !buffer.unavailable || buffer.isDocumentEdited { conflictBar.addSubview(keep) }
        if !buffer.unavailable { conflictBar.addSubview(disk) }
        _ = layoutConflict(width: contentWidth)
    }

    func layoutConflict(width: CGFloat) -> CGFloat {
        guard let title = conflictBar.subviews.first as? NSTextField else { return 0 }
        let buttons = conflictBar.subviews.compactMap { $0 as? ActionButton }
        let titleWidth = max(120, ceil(title.intrinsicContentSize.width) + 8)
        let buttonWidths = buttons.map { max(120, ceil($0.intrinsicContentSize.width) + 16) }
        let actionWidth = buttonWidths.reduce(0, +) + CGFloat(max(0, buttons.count - 1)) * 16
        let narrow = !buttons.isEmpty && 32 + titleWidth + 16 + actionWidth > width
        title.frame = NSRect(x: 16, y: narrow ? 8 : 10, width: titleWidth, height: 18)
        var x: CGFloat = narrow ? 16 : 32 + titleWidth
        for (button, buttonWidth) in zip(buttons, buttonWidths) {
            button.frame = NSRect(x: x, y: narrow ? 34 : 6, width: buttonWidth, height: 26)
            x += buttonWidth + 16
        }
        return narrow ? 66 : 38
    }
}
