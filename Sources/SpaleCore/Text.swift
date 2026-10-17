import Foundation

public struct TextContent: Equatable, Sendable {
    public let data: Data
    public let text: String
    public let editable: Bool
    public let reason: String?
    public let crlf: Bool
    public let finalNewline: Bool
    public let bom: Bool
    public let lineEndings: [String]

    public init(_ data: Data) {
        self.data = data
        bom = data.starts(with: [0xef, 0xbb, 0xbf])
        let body = bom ? data.dropFirst(3) : data[...]
        let decoded = String(data: body, encoding: .utf8)
        editable = decoded != nil && !body.contains(0)
        reason = body.contains(0) ? "Binary file. Read-only." : decoded == nil ? "Not UTF-8. Read-only." : nil
        let original = decoded ?? String(decoding: body, as: UTF8.self)
        lineEndings = original.components(separatedBy: "\n").dropLast().map { $0.hasSuffix("\r") ? "\r\n" : "\n" }
        let crlfCount = lineEndings.filter { $0 == "\r\n" }.count
        crlf = crlfCount > lineEndings.count - crlfCount || crlfCount == lineEndings.count - crlfCount && lineEndings.first == "\r\n"
        finalNewline = original.utf8.last == 10
        text = original.replacingOccurrences(of: "\r\n", with: "\n")
    }

    public func encode(_ value: String) -> Data {
        var normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
        if finalNewline && !normalized.hasSuffix("\n") { normalized += "\n" }
        while !finalNewline && normalized.hasSuffix("\n") { normalized.removeLast() }
        var output = ""
        var replacedEndings: [String] = []
        var replacementIndex = 0
        for row in LineDiff.rows(before: text, after: normalized) {
            if row.kind == .deletion {
                if let number = row.oldLine, number <= lineEndings.count { replacedEndings.append(lineEndings[number - 1]) }
                continue
            }
            let ending: String
            if row.kind == .context {
                replacedEndings = []; replacementIndex = 0
                ending = row.oldLine.flatMap { $0 <= lineEndings.count ? lineEndings[$0 - 1] : nil } ?? (crlf ? "\r\n" : "\n")
            } else {
                ending = replacementIndex < replacedEndings.count ? replacedEndings[replacementIndex] : (crlf ? "\r\n" : "\n")
                replacementIndex += 1
            }
            output += row.text.hasSuffix("\n") ? String(row.text.dropLast()) + ending : row.text
        }
        var result = bom ? Data([0xef, 0xbb, 0xbf]) : Data()
        result.append(Data(output.utf8))
        return result
    }

    public static func indentation(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.contains(where: { $0.hasPrefix("\t") }) { return "\t" }
        let lengths = lines.compactMap { line -> Int? in
            let count = line.prefix(while: { $0 == " " }).count
            return count > 0 && count < line.count ? count : nil
        }
        guard let smallest = lengths.min(), smallest <= 8 else { return "\t" }
        return String(repeating: " ", count: smallest)
    }
}

public enum RowKind: Sendable { case context, addition, deletion }
public struct DiffRow: Sendable {
    public let kind: RowKind
    public let text: String
    public let oldLine: Int?
    public let newLine: Int?
    public let sourceRange: NSRange?
}

public enum LineDiff {
    public static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let value = text as NSString
        var result: [String] = [], offset = 0
        while offset < value.length {
            let range = value.lineRange(for: NSRange(location: offset, length: 0))
            result.append(value.substring(with: range)); offset = NSMaxRange(range)
        }
        return result
    }

    public static func rows(before: String, after: String) -> [DiffRow] {
        let a = lines(before), b = lines(after)
        var prefix = 0
        while prefix < min(a.count, b.count) && a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix && a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
        let old = Array(a[prefix..<(a.count - suffix)])
        let new = Array(b[prefix..<(b.count - suffix)])
        var deleted = Set<Int>(), inserted = Set<Int>()
        if old.count > 0 && new.count > 4_000_000 / old.count {
            deleted.formUnion(prefix..<(a.count - suffix)); inserted.formUnion(prefix..<(b.count - suffix))
        } else {
            for change in new.difference(from: old) {
                switch change {
                case .remove(let offset, _, _): deleted.insert(prefix + offset)
                case .insert(let offset, _, _): inserted.insert(prefix + offset)
                }
            }
        }
        var result: [DiffRow] = [], i = 0, j = 0, offset = 0
        while i < a.count || j < b.count {
            if i < a.count && deleted.contains(i) {
                result.append(DiffRow(kind: .deletion, text: a[i], oldLine: i + 1, newLine: nil, sourceRange: nil)); i += 1
            } else if j < b.count && inserted.contains(j) {
                let length = (b[j] as NSString).length
                result.append(DiffRow(kind: .addition, text: b[j], oldLine: nil, newLine: j + 1, sourceRange: NSRange(location: offset, length: length))); offset += length; j += 1
            } else if i < a.count && j < b.count {
                let length = (b[j] as NSString).length
                result.append(DiffRow(kind: .context, text: b[j], oldLine: i + 1, newLine: j + 1, sourceRange: NSRange(location: offset, length: length))); offset += length; i += 1; j += 1
            } else { break }
        }
        return result
    }
}

public enum WordDiff {
    public static func ranges(before: String, after: String) -> (removed: [NSRange], inserted: [NSRange])? {
        guard let regex = try? NSRegularExpression(pattern: #"\w+|[^\w\s]|\s+"#) else { return nil }
        let old = before as NSString, new = after as NSString
        let oldMatches = regex.matches(in: before, range: NSRange(location: 0, length: old.length))
        let newMatches = regex.matches(in: after, range: NSRange(location: 0, length: new.length))
        guard oldMatches.count < 2048, newMatches.count < 2048 else { return nil }
        let a = oldMatches.map { old.substring(with: $0.range) }
        let b = newMatches.map { new.substring(with: $0.range) }
        let words: (String) -> Bool = { $0.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) } }
        let oldWords = a.filter(words), newWords = b.filter(words)
        let oldLength = oldWords.reduce(0) { $0 + $1.utf16.count }
        let newLength = newWords.reduce(0) { $0 + $1.utf16.count }
        let removedLength = newWords.difference(from: oldWords).reduce(0) { total, edit in
            if case .remove(_, let word, _) = edit { return total + word.utf16.count }
            return total
        }
        let sharedLength = oldLength - removedLength
        guard sharedLength > 0, Double(sharedLength) / Double(max(oldLength, newLength)) >= 0.5 else { return nil }
        var removed: [NSRange] = [], inserted: [NSRange] = []
        for edit in b.difference(from: a) {
            switch edit {
            case .remove(let offset, _, _): removed.append(oldMatches[offset].range)
            case .insert(let offset, _, _): inserted.append(newMatches[offset].range)
            }
        }
        return (removed, inserted)
    }
}

public struct ProjectionSegment {
    public let display: NSRange
    public let source: NSRange?
    public init(display: NSRange, source: NSRange?) { self.display = display; self.source = source }
}

public enum Projection {
    public static func replacing(_ selection: NSRange, segments: [ProjectionSegment], text: String, before: String, with replacement: String) -> (range: NSRange, text: String, rows: [DiffRow], caret: Int)? {
        guard let range = sourceRange(for: selection, segments: segments, sourceLength: (text as NSString).length), NSMaxRange(range) <= (text as NSString).length else { return nil }
        let updated = (text as NSString).replacingCharacters(in: range, with: replacement)
        return (range, updated, LineDiff.rows(before: before, after: updated), range.location + (replacement as NSString).length)
    }

    public static func sourceRange(for selection: NSRange, segments: [ProjectionSegment], sourceLength: Int) -> NSRange? {
        if selection.length == 0 {
            for segment in segments where segment.display.location <= selection.location && selection.location < NSMaxRange(segment.display) {
                guard let source = segment.source else { return nil }
                return NSRange(location: source.location + min(selection.location - segment.display.location, source.length), length: 0)
            }
            if selection.location == segments.last.map({ NSMaxRange($0.display) }) { return NSRange(location: sourceLength, length: 0) }
            return segments.isEmpty && selection.location == 0 ? NSRange(location: 0, length: 0) : nil
        }
        var first: Int?, end = 0
        for segment in segments where NSIntersectionRange(segment.display, selection).length > 0 {
            guard let source = segment.source else { continue }
            let intersection = NSIntersectionRange(segment.display, selection)
            let start = source.location + min(source.length, intersection.location - segment.display.location)
            if let _ = first, start != end { return nil }
            first = first ?? start
            end = min(NSMaxRange(source), start + intersection.length)
        }
        guard let start = first else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
