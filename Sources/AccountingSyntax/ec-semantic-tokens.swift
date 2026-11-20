import AccountingParsers
import Position
import Syntax

public extension EntryCompilerSyntax {
    struct SemanticToken: Equatable, Sendable {
        public let line: Int
        public let startColumn: Int
        public let length: Int
        public let kind: Kind
    }

    enum SemanticError: Swift.Error, Equatable, Sendable {
        case unsupported_kind(String)
        case cross_line_segment
    }

    static func semanticTokens(
        source: String,
        flavor: EntryCompilerLexingFlavor
    ) throws -> [SemanticToken] {
        try semanticTokens(document: document(source: source, flavor: flavor))
    }

    static func semanticTokens(document: SyntaxDocument) throws -> [SemanticToken] {
        let bytes = Array(document.source.utf8)
        let map = Position.TextMap(source: document.source)
        var lines: [Range<Int>] = []
        var lineStart = 0
        var cursor = 0

        while cursor < bytes.count {
            if bytes[cursor] == 10 || bytes[cursor] == 13 {
                lines.append(lineStart..<cursor)
                if bytes[cursor] == 13,
                   cursor + 1 < bytes.count,
                   bytes[cursor + 1] == 10 {
                    cursor += 1
                }
                lineStart = cursor + 1
            }
            cursor += 1
        }
        lines.append(lineStart..<bytes.count)

        let spans = try document.captures
            .filter { $0.layer == .lexical }
            .flatMap { capture -> [SemanticSpan] in
                guard let kind = Kind(rawValue: capture.kind.name) else {
                    throw SemanticError.unsupported_kind(capture.kind.name)
                }
                return capture.segments.map {
                    SemanticSpan(range: $0.start.offset..<$0.end.offset, kind: kind)
                }
            }
            .sorted {
                if $0.range.lowerBound != $1.range.lowerBound {
                    return $0.range.lowerBound < $1.range.lowerBound
                }
                return $0.range.upperBound < $1.range.upperBound
            }

        var result: [SemanticToken] = []
        var lineCursor = 0
        for span in spans {
            while lineCursor < lines.count,
                  lines[lineCursor].upperBound <= span.range.lowerBound {
                lineCursor += 1
            }

            var index = lineCursor
            while index < lines.count,
                  lines[index].lowerBound < span.range.upperBound {
                let lower = max(lines[index].lowerBound, span.range.lowerBound)
                let upper = min(lines[index].upperBound, span.range.upperBound)
                if lower < upper {
                    let start = try map.convert(
                        Position.Offset<Position.Unit.UTF8>(lower),
                        to: Position.Unit.UTF16.self
                    )
                    let end = try map.convert(
                        Position.Offset<Position.Unit.UTF8>(upper),
                        to: Position.Unit.UTF16.self
                    )
                    let startCoordinate = try map.coordinate(at: start)
                    let endCoordinate = try map.coordinate(at: end)
                    guard startCoordinate.line == endCoordinate.line else {
                        throw SemanticError.cross_line_segment
                    }
                    result.append(SemanticToken(
                        line: startCoordinate.line - 1,
                        startColumn: startCoordinate.column - 1,
                        length: endCoordinate.column - startCoordinate.column,
                        kind: span.kind
                    ))
                }
                index += 1
            }
        }

        return result
    }
}

private struct SemanticSpan {
    let range: Range<Int>
    let kind: EntryCompilerSyntax.Kind
}
