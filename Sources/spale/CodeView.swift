import AppKit
import SpaleCore

struct RenderLine {
    let range: NSRange
    let oldLine: Int?
    let newLine: Int?
    let kind: RowKind
    let fold: Range<Int>?
    var open = false
    var deletionBoundary = false
    var modified = false
    var deletionAtEnd = false
}

final class CodeView: NSTextView {
    var lines: [RenderLine] = []
    var single = false
    var full = false
    var foldClick: ((Range<Int>) -> Void)?
    var turningFold: Int?
    var escape: (() -> Void)?
    var cueStarted = Date.distantPast
    var cueLines = Set<Int>()
    var cueTimer: Timer?
    func showCue(started: Date, lines: Set<Int>) {
        guard started != cueStarted, Date().timeIntervalSince(started) < 3 else { return }
        cueStarted = started; cueLines = lines
        cueTimer?.invalidate()
        cueTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.needsDisplay = true
            if Date().timeIntervalSince(self.cueStarted) >= 3 { timer.invalidate(); self.cueTimer = nil }
        }
    }
    var numberWidth: CGFloat = 30
    var codeInset: CGFloat { single ? 20 : full ? 32 + numberWidth : 40 + numberWidth * 2 }

    override func drawBackground(in rect: NSRect) {
        Theme.bg.setFill(); rect.fill()
        guard let manager = layoutManager, let container = textContainer else { return }
        let visible = rect.intersection(visibleRect).offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let visibleCharacters = manager.characterRange(forGlyphRange: manager.glyphRange(forBoundingRect: visible, in: container), actualGlyphRange: nil)
        for line in lines where NSIntersectionRange(line.range, visibleCharacters).length > 0 {
            let glyph = manager.glyphRange(forCharacterRange: line.range, actualCharacterRange: nil)
            var box = manager.boundingRect(forGlyphRange: glyph, in: container)
            box.origin.y += textContainerOrigin.y
            box.origin.x = 0; box.size.width = bounds.width
            guard box.intersects(rect) else { continue }
            if !full && line.kind != .context { (line.kind == .addition ? Theme.addBG : Theme.removeBG).setFill(); box.fill() }
            let elapsed = Date().timeIntervalSince(cueStarted)
            if let number = line.newLine, cueLines.contains(number), elapsed < 3 {
                Theme.addWord.withAlphaComponent(Theme.addWord.alphaComponent * min(1, (3 - elapsed) / 2.1)).setFill(); box.fill()
            }
            guard line.kind != .context else { continue }
            (line.modified ? Theme.modify : line.kind == .addition ? Theme.add : Theme.remove).setFill()
            NSRect(x: 4, y: box.minY, width: 2, height: max(18, box.height)).fill()
        }
    }

    func drawGutter(_ dirtyRect: NSRect) {
        guard let manager = layoutManager, let container = textContainer, !single else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.code, .foregroundColor: Theme.muted]
        let visible = dirtyRect.intersection(visibleRect).offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let visibleCharacters = manager.characterRange(forGlyphRange: manager.glyphRange(forBoundingRect: visible, in: container), actualGlyphRange: nil)
        for line in lines where NSIntersectionRange(line.range, visibleCharacters).length > 0 {
            let glyph = manager.glyphRange(forCharacterRange: line.range, actualCharacterRange: nil)
            let box = manager.boundingRect(forGlyphRange: glyph, in: container).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard box.intersects(dirtyRect), box.height > 0 else { continue }
            if line.deletionBoundary {
                Theme.remove.setStroke()
                let marker = NSBezierPath(); marker.move(to: NSPoint(x: 17, y: line.deletionAtEnd ? box.maxY : box.minY)); marker.line(to: NSPoint(x: 27, y: line.deletionAtEnd ? box.maxY : box.minY)); marker.lineWidth = 1.5; marker.stroke()
            }
            if let fold = line.fold {
                if fold.lowerBound != turningFold { Theme.muted.setStroke(); foldArrow(open: line.open, in: foldArrowFrame(box)).stroke() }
            } else {
                if let old = line.oldLine {
                    let value = "\(old)" as NSString
                    value.draw(at: NSPoint(x: 24 + numberWidth - value.size(withAttributes: attributes).width, y: box.minY), withAttributes: attributes)
                }
                if let new = line.newLine {
                    let value = "\(new)" as NSString
                    value.draw(at: NSPoint(x: (full ? 24 + numberWidth : 32 + numberWidth * 2) - value.size(withAttributes: attributes).width, y: box.minY), withAttributes: attributes)
                }
            }
        }
    }

    func foldArrowFrame(_ box: NSRect) -> NSRect { NSRect(x: codeInset - 24, y: box.midY - 8, width: 16, height: 16) }
    func foldArrow(open: Bool, in frame: NSRect) -> NSBezierPath {
        let path = NSBezierPath(); path.lineWidth = 1.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let edge: CGFloat = open ? 10 : 6, tip: CGFloat = open ? 5 : 11
        path.move(to: NSPoint(x: frame.minX + 3, y: frame.minY + edge)); path.line(to: NSPoint(x: frame.minX + 8, y: frame.minY + tip)); path.line(to: NSPoint(x: frame.minX + 13, y: frame.minY + edge))
        return path
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if let fold = lines.first(where: { $0.fold != nil && NSLocationInRange(index, $0.range) })?.fold { foldClick?(fold); return }
        super.mouseDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

final class GutterView: NSView {
    weak var code: CodeView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { code?.drawGutter(dirtyRect) }
}

final class FileSection: Surface, NSTextViewDelegate {
    let key: String
    let path: String
    let header = Surface()
    let code: CodeView
    let gutter = GutterView()
    let headerButton: ActionButton
    let counts = ActionButton("", action: {})
    let conflictBar = Surface()
    var buffer: FileBuffer
    var segments: [ProjectionSegment] = []
    var full = false
    var readOnly = false
    var collapsed = false
    var expanded = Set<Int>()
    var rows: [DiffRow] = []
    var baseline = ""
    var contentWidth: CGFloat = 600
    var onEdit: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onFocus: (() -> Void)?
    var lastRendered = ""
    var applying = false
    var caretAfterEdit: Int?
    var changeOffsets: [Int] = []
    var topPadding: CGFloat { header.isHidden ? 0 : 48 }

    init(key: String, path: String, buffer: FileBuffer) {
        self.key = key; self.path = path; self.buffer = buffer
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true; container.lineFragmentPadding = 0
        manager.addTextContainer(container); storage.addLayoutManager(manager)
        code = CodeView(frame: .zero, textContainer: container)
        headerButton = ActionButton(path, action: {})
        super.init(frame: .zero)
        addSubview(header); header.addSubview(headerButton); header.addSubview(counts); addSubview(conflictBar); addSubview(code); addSubview(gutter); gutter.code = code
        header.fill = Theme.bg; conflictBar.fill = Theme.page
        headerButton.alignment = .left; headerButton.font = Theme.heading
        headerButton.contentTintColor = Theme.fg
        headerButton.actionBlock = { [weak self] in guard let self else { return }; self.collapsed.toggle(); self.onCollapse?() }
        counts.actionBlock = headerButton.actionBlock; counts.alignment = .right
        code.delegate = self; code.isRichText = false; code.importsGraphics = false
        code.isAutomaticQuoteSubstitutionEnabled = false; code.isAutomaticDashSubstitutionEnabled = false
        code.isAutomaticTextReplacementEnabled = false; code.isAutomaticSpellingCorrectionEnabled = false
        code.isContinuousSpellCheckingEnabled = false; code.isGrammarCheckingEnabled = false
        code.font = Theme.code; code.textColor = Theme.fg; code.backgroundColor = Theme.bg
        code.insertionPointColor = Theme.strong; code.drawsBackground = true
        code.isVerticallyResizable = false; code.isHorizontallyResizable = false
        code.textContainerInset = NSSize(width: 104, height: 0)
        code.usesFindBar = true; code.isIncrementalSearchingEnabled = true; code.allowsUndo = false
        code.selectedTextAttributes = [.backgroundColor: Theme.selection]
        code.foldClick = { [weak self] range in self?.toggleFold(range) }
        conflictBar.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(rows: [DiffRow], status: Character, title: String, full: Bool, readOnly: Bool, single: Bool = false) {
        self.rows = rows; self.full = full; self.readOnly = readOnly
        baseline = rows.filter { $0.kind != .addition }.map(\.text).joined()
        header.isHidden = single; code.single = single; code.full = full
        let maximum = rows.reduce(0) { max($0, $1.oldLine ?? 0, $1.newLine ?? 0) }
        code.numberWidth = (String(repeating: "0", count: max(2, String(maximum).count)) as NSString).size(withAttributes: [.font: Theme.code]).width
        code.textContainerInset.width = code.codeInset
        let additions = rows.filter { $0.kind == .addition }.count, deletions = rows.filter { $0.kind == .deletion }.count
        let text = NSMutableAttributedString(string: title, attributes: [.font: Theme.heading, .foregroundColor: Theme.strong])
        let directory = (title as NSString).deletingLastPathComponent
        if !directory.isEmpty { text.addAttribute(.foregroundColor, value: Theme.muted, range: NSRange(location: 0, length: (directory as NSString).length + 1)) }
        if status == "D" { text.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 0, length: text.length)) }
        let statusName: String = ["A": "Added", "U": "Untracked", "M": "Modified", "D": "Deleted", "R": "Renamed"][String(status)] ?? "Modified"
        text.append(NSAttributedString(string: "   " + statusName, attributes: [.font: Theme.ui, .foregroundColor: Theme.muted]))
        let countText = NSMutableAttributedString(string: additions > 0 ? "+\(additions)" : "", attributes: [.font: Theme.ui, .foregroundColor: Theme.add])
        if deletions > 0 { countText.append(NSAttributedString(string: (additions > 0 ? "  " : "") + "−\(deletions)", attributes: [.font: Theme.ui, .foregroundColor: Theme.remove])) }
        headerButton.attributedTitle = text
        counts.attributedTitle = countText
        code.isEditable = !readOnly && buffer.content.editable
        render()
    }

    func render() {
        applying = true
        defer { applying = false }
        let selectedSource = caretAfterEdit ?? Projection.sourceRange(for: code.selectedRange(), segments: segments, sourceLength: (buffer.text as NSString).length)?.location
        let output = NSMutableAttributedString()
        segments = []; code.lines = []; changeOffsets = []
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
        paragraph.defaultTabInterval = Theme.code.maximumAdvancement.width * 4
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.code, .foregroundColor: Theme.fg, .paragraphStyle: paragraph]
        if let reason = buffer.content.reason {
            output.append(NSAttributedString(string: reason + "\n", attributes: [.font: Theme.ui, .foregroundColor: Theme.muted]))
        } else {
            var i = 0
            var deletionPending = false
            var replacementBlock = false
            var openUntil = 0
            while i < rows.count {
                let row = rows[i]
                if !full && row.kind == .context && i >= openUntil {
                    var end = i + 1
                    while end < rows.count && rows[end].kind == .context { end += 1 }
                    if i > 0 && end < rows.count && end - i >= 4 {
                        let value = "\(end - i) unchanged lines\n"
                        let range = NSRange(location: output.length, length: (value as NSString).length)
                        output.append(NSAttributedString(string: value, attributes: [.font: Theme.ui, .foregroundColor: Theme.muted, .paragraphStyle: {
                            let folded = paragraph.mutableCopy() as! NSMutableParagraphStyle
                            folded.minimumLineHeight = 28; folded.maximumLineHeight = 28
                            return folded
                        }()]))
                        segments.append(ProjectionSegment(display: range, source: nil))
                        code.lines.append(RenderLine(range: range, oldLine: nil, newLine: nil, kind: .context, fold: i..<end, open: expanded.contains(i)))
                        if !expanded.contains(i) { i = end; continue }
                        openUntil = end
                    }
                }
                if full && row.kind == .deletion { deletionPending = true; replacementBlock = true; i += 1; continue }
                let value = row.text.hasSuffix("\n") || i == rows.count - 1 ? row.text : row.text + "\n"
                let range = NSRange(location: output.length, length: (value as NSString).length)
                output.append(NSAttributedString(string: value, attributes: attributes))
                segments.append(ProjectionSegment(display: range, source: row.sourceRange))
                code.lines.append(RenderLine(range: range, oldLine: full ? nil : row.oldLine, newLine: row.newLine, kind: row.kind, fold: nil, deletionBoundary: deletionPending, modified: replacementBlock && row.kind == .addition))
                deletionPending = false
                if row.kind == .context { replacementBlock = false }
                if row.kind != .context && (i == 0 || rows[i - 1].kind == .context) { changeOffsets.append(range.location) }
                i += 1
            }
            if full && deletionPending && !code.lines.isEmpty {
                code.lines[code.lines.count - 1].deletionBoundary = true
                code.lines[code.lines.count - 1].deletionAtEnd = true
            }
        }
        if output.length == 0 && !readOnly { segments = [ProjectionSegment(display: NSRange(location: 0, length: 0), source: NSRange(location: 0, length: 0))] }
        if buffer.content.reason == nil {
            highlight(output); highlightChangedWords(output)
            for line in code.lines where line.fold != nil {
                output.addAttributes([.foregroundColor: Theme.muted, .baselineOffset: 5], range: line.range)
            }
        }
        code.textStorage?.setAttributedString(output)
        lastRendered = output.string
        if let position = selectedSource {
            let display = segments.first { segment in guard let source = segment.source else { return false }; return source.location <= position && position <= NSMaxRange(source) }.map { segment in segment.display.location + min(position - segment.source!.location, segment.display.length) } ?? min(position, output.length)
            code.setSelectedRange(NSRange(location: display, length: 0))
        }
        caretAfterEdit = nil
        configureConflict()
        code.needsDisplay = true; gutter.needsDisplay = true
    }

    func toggleFold(_ range: Range<Int>) {
        let open = !expanded.contains(range.lowerBound)
        if open { expanded.insert(range.lowerBound) } else { expanded.remove(range.lowerBound) }
        render(); onCollapse?()
        guard !Theme.reducedMotion, let manager = code.layoutManager, let container = code.textContainer,
              let index = code.lines.firstIndex(where: { $0.fold?.lowerBound == range.lowerBound }) else { return }
        func box(_ line: RenderLine) -> NSRect {
            manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: line.range, actualCharacterRange: nil), in: container).offsetBy(dx: code.frame.minX + code.textContainerOrigin.x, dy: code.frame.minY + code.textContainerOrigin.y)
        }
        let foldBox = box(code.lines[index])
        let arrow = ShapeView(frame: code.foldArrowFrame(foldBox).offsetBy(dx: code.frame.minX, dy: 0))
        arrow.shape.path = code.foldArrow(open: false, in: arrow.bounds).cgPath
        addSubview(arrow); code.turningFold = range.lowerBound; gutter.needsDisplay = true
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = open ? 0 : CGFloat.pi; turn.toValue = open ? CGFloat.pi : 0
        turn.duration = 0.38; turn.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in arrow.removeFromSuperview(); self?.code.turningFold = nil; self?.gutter.needsDisplay = true }
        arrow.shape.setAffineTransform(CGAffineTransform(rotationAngle: open ? .pi : 0)); arrow.shape.add(turn, forKey: "turn")
        CATransaction.commit()
        let last = min(code.lines.count - 1, index + range.count)
        guard open, last > index else { return }
        let cover = Surface(frame: NSRect(x: 0, y: foldBox.maxY, width: bounds.width, height: box(code.lines[last]).maxY - foldBox.maxY))
        cover.wantsLayer = true; addSubview(cover)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38; context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
            cover.animator().alphaValue = 0
        } completionHandler: { cover.removeFromSuperview() }
    }

    func synchronize() {
        rows = LineDiff.rows(before: baseline, after: buffer.text)
        render()
    }

    private func highlight(_ output: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: output.length)
        guard output.length < 500_000 else { return }
        let patterns: [(String, NSColor)] = [
            (#"\b(import|func|let|var|if|else|return|struct|class|enum|public|private|static|guard|for|while|switch|case|const|function|def|type|package|nil|true|false)\b"#, Theme.keyword),
            (#"\b[0-9]+(?:\.[0-9]+)?\b"#, Theme.number),
            (#"\"(?:[^\"\\]|\\.)*\"|'[^'\n]*'"#, Theme.add)
        ]
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: output.string, range: range) { output.addAttribute(.foregroundColor, value: color, range: match.range) }
        }
    }
    private func highlightChangedWords(_ output: NSMutableAttributedString) {
        guard !full else { return }
        let displayed = code.lines
        var i = 0
        while i < displayed.count {
            guard displayed[i].kind == .deletion else { i += 1; continue }
            let start = i
            while i < displayed.count && displayed[i].kind == .deletion { i += 1 }
            let additions = i
            while i < displayed.count && displayed[i].kind == .addition { i += 1 }
            for pair in 0..<min(additions - start, i - additions) {
                let oldLine = displayed[start + pair], newLine = displayed[additions + pair]
                let old = (output.string as NSString).substring(with: oldLine.range)
                let new = (output.string as NSString).substring(with: newLine.range)
                guard let changes = WordDiff.ranges(before: old, after: new) else { continue }
                for (line, ranges, color) in [(oldLine, changes.removed, Theme.removeWord), (newLine, changes.inserted, Theme.addWord)] {
                    for range in ranges {
                        output.addAttribute(.backgroundColor, value: color, range: NSRange(location: line.range.location + range.location, length: range.length))
                    }
                }
            }
        }
    }
    private func configureConflict() {
        conflictBar.subviews.forEach { $0.removeFromSuperview() }
        conflictBar.isHidden = !buffer.conflict
        guard buffer.conflict else { return }
        let title = label("Changed on disk", color: Theme.modify)
        let keep = ActionButton("Keep my version") { [weak self] in self?.buffer.saveNow { _ in } }
        let disk = ActionButton("Use disk version") { [weak self] in self?.buffer.useDisk() }
        title.frame = NSRect(x: 16, y: 10, width: 120, height: 18)
        keep.frame = NSRect(x: 152, y: 6, width: 120, height: 26)
        disk.frame = NSRect(x: 288, y: 6, width: 120, height: 26)
        [title, keep, disk].forEach { conflictBar.addSubview($0) }
    }
    @discardableResult func size(width: CGFloat) -> CGFloat {
        contentWidth = width
        header.frame = NSRect(x: 0, y: 0, width: width, height: topPadding)
        headerButton.frame = NSRect(x: 16, y: 8, width: max(0, width - 148), height: 32)
        counts.frame = NSRect(x: max(16, width - 120), y: 8, width: 104, height: 32)
        let bannerHeight: CGFloat = buffer.conflict && !collapsed ? 38 : 0
        conflictBar.frame = NSRect(x: 0, y: topPadding, width: width, height: bannerHeight)
        code.isHidden = collapsed
        code.frame = NSRect(x: 0, y: topPadding + bannerHeight, width: width, height: 18)
        code.textContainer?.containerSize = NSSize(width: max(40, width - code.textContainerInset.width - 16), height: CGFloat.greatestFiniteMagnitude)
        code.layoutManager?.ensureLayout(for: code.textContainer!)
        let height = max(18, code.layoutManager?.usedRect(for: code.textContainer!).height ?? 18)
        code.frame.size.height = height + 4
        gutter.frame = code.frame; gutter.isHidden = collapsed || code.single; gutter.needsDisplay = true
        return topPadding + bannerHeight + (collapsed ? 0 : height)
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !applying, !readOnly, let replacementString,
              let edit = Projection.replacing(affectedCharRange, segments: segments, text: buffer.text, before: baseline, with: replacementString) else { NSSound.beep(); return false }
        caretAfterEdit = edit.caret
        onFocus?()
        buffer.replace(edit.range, with: replacementString, manager: buffer.undoManager)
        return false
    }
    func undoManager(for view: NSTextView) -> UndoManager? { buffer.undoManager }
    func textViewDidChangeSelection(_ notification: Notification) { if !applying { onFocus?() } }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            _ = self.textView(textView, shouldChangeTextIn: textView.selectedRange(), replacementString: TextContent.indentation(in: buffer.text)); return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard let source = Projection.sourceRange(for: textView.selectedRange(), segments: segments, sourceLength: (buffer.text as NSString).length) else { return true }
            let value = buffer.text as NSString
            let lineRange = value.lineRange(for: NSRange(location: source.location, length: 0))
            let prefix = value.substring(with: NSRange(location: lineRange.location, length: source.location - lineRange.location)).prefix { $0 == " " || $0 == "\t" }
            _ = self.textView(textView, shouldChangeTextIn: textView.selectedRange(), replacementString: "\n" + prefix); return true
        }
        return false
    }
}
