import AccountingParsers
import Syntax

public extension EntryCompilerSyntax {
    enum HighlightError: Swift.Error, Equatable, Sendable {
        case unsupported_kind(String)
        case overlapping_spans(start: Int, end: Int)
    }

    static func highlightedLines(
        source: String,
        flavor: EntryCompilerLexingFlavor,
        startingAtLine startLine: Int
    ) throws -> [ECSyntaxLine] {
        let syntax = try document(source: source, flavor: flavor)
        return try highlightedLines(document: syntax, startingAtLine: startLine)
    }

    static func highlightedLines(
        document: SyntaxDocument,
        startingAtLine startLine: Int
    ) throws -> [ECSyntaxLine] {
        let bytes = Array(document.source.utf8)
        var lineRanges: [Range<Int>] = []
        var lineStart = 0

        for (offset, byte) in bytes.enumerated() where byte == 10 {
            lineRanges.append(lineStart..<offset)
            lineStart = offset + 1
        }
        lineRanges.append(lineStart..<bytes.count)

        let spans = try document.captures
            .filter { $0.layer == .lexical }
            .flatMap { capture -> [HighlightSpan] in
                guard let kind = ECSyntaxKind(rawValue: capture.kind.name) else {
                    throw HighlightError.unsupported_kind(capture.kind.name)
                }
                return capture.segments.map {
                    HighlightSpan(range: $0.start.offset..<$0.end.offset, kind: kind)
                }
            }
            .sorted {
                if $0.range.lowerBound != $1.range.lowerBound {
                    return $0.range.lowerBound < $1.range.lowerBound
                }
                return $0.range.upperBound < $1.range.upperBound
            }

        return try lineRanges.enumerated().map { lineOffset, lineRange in
            var fragments: [ECSyntaxFragment] = []
            var cursor = lineRange.lowerBound

            func append(_ range: Range<Int>, kind: ECSyntaxKind) {
                guard !range.isEmpty else { return }
                let text = String(decoding: bytes[range], as: UTF8.self)
                if let last = fragments.last, last.kind == kind {
                    fragments[fragments.count - 1] = ECSyntaxFragment(
                        text: last.text + text,
                        kind: kind
                    )
                } else {
                    fragments.append(ECSyntaxFragment(text: text, kind: kind))
                }
            }

            for span in spans {
                let lower = max(span.range.lowerBound, lineRange.lowerBound)
                let upper = min(span.range.upperBound, lineRange.upperBound)
                guard lower < upper else { continue }
                guard lower >= cursor else {
                    throw HighlightError.overlapping_spans(start: lower, end: upper)
                }
                append(cursor..<lower, kind: .plain)
                append(lower..<upper, kind: span.kind)
                cursor = upper
            }
            append(cursor..<lineRange.upperBound, kind: .plain)
            return ECSyntaxLine(number: startLine + lineOffset, fragments: fragments)
        }
    }
}

private struct HighlightSpan {
    let range: Range<Int>
    let kind: ECSyntaxKind
}
