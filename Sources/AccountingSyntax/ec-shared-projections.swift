import AccountingParsers
import Syntax
import SyntaxLSP

public extension EntryCompilerSyntax {
    /// LSP semantic-token legend order is canonical for EC consumers.
    static let semanticTypes = [
        "keyword", "variable", "number", "string", "type",
        "namespace", "comment", "operator", "property"
    ]

    /// Generic projection retaining the current EC source renderer line contract.
    static func projectedLines(
        source: String,
        flavor: EntryCompilerLexingFlavor,
        startingAtLine startLine: Int
    ) throws -> [ECSyntaxLine] {
        let document = try document(source: source, flavor: flavor)
        let projection = try SyntaxProjection(document: document)
        let bytes = Array(source.utf8)
        return try projection.lines.map { line in
            var fragments: [ECSyntaxFragment] = []

            func append(_ range: SyntaxSourceRange, kind: ECSyntaxKind) {
                guard !range.isEmpty else { return }
                let text = String(decoding: bytes[range.start.offset..<range.end.offset], as: UTF8.self)
                if let last = fragments.last, last.kind == kind {
                    fragments[fragments.count - 1] = ECSyntaxFragment(text: last.text + text, kind: kind)
                } else {
                    fragments.append(ECSyntaxFragment(text: text, kind: kind))
                }
            }

            for run in line.runs {
                let kind: ECSyntaxKind
                if let capture = run.captures.last(where: { $0.layer == .lexical }) {
                    guard let classified = ECSyntaxKind(rawValue: capture.kind.name) else {
                        throw HighlightError.unsupported_kind(capture.kind.name)
                    }
                    kind = classified
                } else {
                    kind = .plain
                }
                append(run.range, kind: kind)
            }

            // EC's historical line contract includes CR before LF in line text.
            if line.terminator.length == 2,
               bytes[line.terminator.start.offset] == 13 {
                let start = line.terminator.start.offset
                append(try SyntaxSourceRange(start: start, end: start + 1), kind: .plain)
            }
            return ECSyntaxLine(number: startLine + line.index, fragments: fragments)
        }
    }

    /// Uses SyntaxLSP's UTF-16 projection and five-integer delta encoder.
    static func encodedSemanticTokens(
        source: String,
        flavor: EntryCompilerLexingFlavor
    ) throws -> [Int] {
        let document = try document(source: source, flavor: flavor)
        let kinds: [Kind] = [
            .keyword, .identifier, .number, .string, .account,
            .entity, .comment, .punctuation, .date
        ]
        let rules = zip(kinds, semanticTypes).map { kind, semanticType in
            SyntaxLSP.Rule(
                selector: .init(language: "ec", kind: kind.rawValue, layer: .lexical),
                type: semanticType
            )
        }
        let tokens = try SyntaxLSP.project(
            document: document,
            legend: SyntaxLSP.Legend(types: semanticTypes),
            rules: rules
        )
        return SyntaxLSP.encode(tokens)
    }
}
