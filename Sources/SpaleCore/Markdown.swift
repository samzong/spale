import Foundation

public struct MarkdownBlock {
    public let content: AttributedString
    public let firstLine: Int

    fileprivate var signature: Signature {
        var text = content
        text.presentationIntent = nil; text.markdownSourcePosition = nil
        for run in text.runs where run.inlinePresentationIntent?.contains(.softBreak) == true {
            let intent = run.inlinePresentationIntent!.subtracting(.softBreak)
            text[run.range].inlinePresentationIntent = intent.isEmpty ? nil : intent
        }
        var structure: [Span] = []
        var identities: [Int: Int] = [:]
        for run in content.runs {
            let components = run.presentationIntent?.components ?? []
            let kinds = components.map(\.kind)
            let ids = components.map { component in
                if let identity = identities[component.identity] { return identity }
                let identity = identities.count; identities[component.identity] = identity; return identity
            }
            let value = String(content[run.range].characters)
            if let last = structure.last, last.kinds == kinds && last.identities == ids { structure[structure.count - 1].text += value }
            else { structure.append(Span(kinds: kinds, identities: ids, text: value)) }
        }
        return Signature(text: text, structure: structure)
    }

    fileprivate struct Signature: Equatable {
        let text: AttributedString
        let structure: [Span]
    }

    fileprivate struct Span: Equatable {
        let kinds: [PresentationIntent.Kind]
        let identities: [Int]
        var text: String
    }

}

public struct MarkdownChange {
    public let block: MarkdownBlock
    public let kind: RowKind
    public let oldLine: Int?
    public let newLine: Int?
}

public enum MarkdownDiff {
    public static func blocks(_ text: String) -> [MarkdownBlock] {
        guard !text.isEmpty else { return [] }
        let parsed = (try? AttributedString(markdown: text, options: .init(appliesSourcePositionAttributes: true))) ?? AttributedString(text)
        var groups: [(identity: Int?, content: AttributedString, firstLine: Int)] = []
        for run in parsed.runs {
            let identity = run.presentationIntent?.components.last?.identity
            if groups.isEmpty || groups.last?.identity != identity {
                groups.append((identity, AttributedString(), run.markdownSourcePosition?.startLine ?? 1))
            }
            groups[groups.count - 1].content.append(parsed[run.range])
        }
        if groups.isEmpty { return [MarkdownBlock(content: AttributedString(text), firstLine: 1)] }
        return groups.map { MarkdownBlock(content: $0.content, firstLine: $0.firstLine) }
    }

    public static func changes(before: String, after: String) -> [MarkdownChange] {
        let old = blocks(before), new = blocks(after)
        var removed = Set<Int>(), inserted = Set<Int>()
        if !old.isEmpty && new.count > 4_000_000 / old.count {
            removed.formUnion(old.indices); inserted.formUnion(new.indices)
        } else {
            for change in new.map(\.signature).difference(from: old.map(\.signature)) {
                switch change {
                case .remove(let index, _, _): removed.insert(index)
                case .insert(let index, _, _): inserted.insert(index)
                }
            }
        }
        var result: [MarkdownChange] = [], i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) {
                result.append(MarkdownChange(block: old[i], kind: .deletion, oldLine: old[i].firstLine, newLine: nil)); i += 1
            } else if j < new.count && inserted.contains(j) {
                result.append(MarkdownChange(block: new[j], kind: .addition, oldLine: nil, newLine: new[j].firstLine)); j += 1
            } else if i < old.count && j < new.count {
                result.append(MarkdownChange(block: new[j], kind: .context, oldLine: old[i].firstLine, newLine: new[j].firstLine)); i += 1; j += 1
            } else { break }
        }
        return result
    }
}
