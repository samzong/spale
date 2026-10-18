import AppKit
import SpaleCore

enum MarkdownRenderer {
    static func render(_ block: MarkdownBlock) -> NSAttributedString {
        var groups: [(identity: Int?, columns: [PresentationIntent.TableColumn]?, content: AttributedString)] = []
        for run in block.content.runs {
            var identity: Int?, columns: [PresentationIntent.TableColumn]?
            for component in run.presentationIntent?.components ?? [] {
                if case .table(let value) = component.kind { identity = component.identity; columns = value }
            }
            if groups.isEmpty || groups.last?.identity != identity { groups.append((identity, columns, AttributedString())) }
            groups[groups.count - 1].content.append(block.content[run.range])
        }
        let result = NSMutableAttributedString()
        var listed = Set<Int>()
        for group in groups { result.append(group.columns.map { renderTable(group.content, columns: $0, listed: &listed) } ?? render(group.content, listed: &listed)) }
        return result
    }

    private static func renderTable(_ content: AttributedString, columns: [PresentationIntent.TableColumn], listed: inout Set<Int>) -> NSAttributedString {
        var cells: [Int: [Int: AttributedString]] = [:]
        for run in content.runs {
            var row = 0, column = 0
            for component in run.presentationIntent?.components ?? [] {
                if case .tableRow(let index) = component.kind { row = index }
                if case .tableCell(let index) = component.kind { column = index }
            }
            cells[row, default: [:]][column, default: AttributedString()].append(content[run.range])
        }
        let table = NSTextTable()
        table.numberOfColumns = columns.count
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.setContentWidth(100, type: .percentageValueType)
        let result = NSMutableAttributedString()
        for row in 0...(cells.keys.max() ?? 0) {
            for column in columns.indices {
                let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setContentWidth(100 / CGFloat(columns.count), type: .percentageValueType)
                cell.setWidth(8, type: .absoluteValueType, for: .padding)
                cell.verticalAlignment = .topAlignment
                let value = render(cells[row]?[column] ?? AttributedString(" "), listed: &listed)
                let styled = NSMutableAttributedString(attributedString: value)
                styled.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: styled.length)) { value, range, _ in
                    let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    paragraph.textBlocks = [cell]
                    paragraph.paragraphSpacing = 0
                    switch columns[column].alignment {
                    case .center: paragraph.alignment = .center
                    case .right: paragraph.alignment = .right
                    default: paragraph.alignment = .left
                    }
                    styled.addAttribute(.paragraphStyle, value: paragraph, range: range)
                }
                result.append(styled)
            }
        }
        return result
    }

    private static func render(_ content: AttributedString, listed: inout Set<Int>) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var previousLeaf: Int?
        for run in content.runs {
            let components = run.presentationIntent?.components ?? []
            let leaf = components.first?.identity
            if result.length > 0 && leaf != previousLeaf {
                result.append(NSAttributedString(string: "\n"))
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4; paragraph.paragraphSpacing = 10
            var font = NSFont.systemFont(ofSize: 14)
            var color = Theme.fg
            var traits: NSFontTraitMask = []
            var code = false
            var prefix = ""
            for component in components {
                switch component.kind {
                case .header(let level):
                    font = .systemFont(ofSize: level == 1 ? 24 : level == 2 ? 20 : 16, weight: .semibold)
                    paragraph.paragraphSpacingBefore = 8; paragraph.paragraphSpacing = 12
                case .codeBlock:
                    code = true; font = Theme.code; paragraph.lineSpacing = 4; paragraph.paragraphSpacing = 12
                case .blockQuote:
                    color = Theme.muted; paragraph.headIndent += 16; paragraph.firstLineHeadIndent += 16
                case .tableHeaderRow: traits.insert(.boldFontMask)
                default: break
                }
            }
            let depth = components.filter { if case .listItem = $0.kind { return true }; return false }.count
            if let item = components.firstIndex(where: { if case .listItem = $0.kind { return true }; return false }),
               case .listItem(let ordinal) = components[item].kind {
                paragraph.headIndent += CGFloat(depth) * 20
                paragraph.firstLineHeadIndent = paragraph.headIndent
                if !listed.contains(components[item].identity) {
                    let ordered = components.dropFirst(item + 1).first.map { if case .orderedList = $0.kind { return true }; return false } ?? false
                    prefix = ordered ? "\(ordinal).  " : "•  "
                    paragraph.firstLineHeadIndent -= 20
                    listed.insert(components[item].identity)
                }
            }
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.code) { code = true; font = Theme.code }
            if inline.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if inline.contains(.emphasized) { traits.insert(.italicFontMask) }
            font = NSFontManager.shared.convert(font, toHaveTrait: traits)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if code { attributes[.backgroundColor] = Theme.line }
            if let link = run.link, ["https", "http"].contains(link.scheme?.lowercased() ?? "") {
                attributes[.link] = link; attributes[.foregroundColor] = Theme.soft; attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if leaf != previousLeaf && !prefix.isEmpty { result.append(NSAttributedString(string: prefix, attributes: attributes)) }
            result.append(NSAttributedString(string: String(content[run.range].characters), attributes: attributes))
            previousLeaf = leaf
        }
        if !result.string.hasSuffix("\n") { result.append(NSAttributedString(string: "\n", attributes: result.length > 0 ? result.attributes(at: result.length - 1, effectiveRange: nil) : [:])) }
        return result
    }
}
