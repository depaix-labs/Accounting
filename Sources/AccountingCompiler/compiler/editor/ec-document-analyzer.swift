import Accounting
import AccountingParsers
import AccountingSyntax
import Foundation
import Position

public enum ECDocumentAnalyzer {
    public static func analyze(
        source: String,
        flavor: EntryCompilerLexingFlavor
    ) -> ECDocumentAnalysis {
        var lexer = EntryCompilerLexer(
            source: source,
            flavor: flavor
        )

        var tokens: [EntryCompilerToken] = []
        var spans: [PositionSpan] = []

        while true {
            let token = lexer.nextToken()
            let span = lexer.lastTokenSpan

            tokens.append(token)

            if let span {
                spans.append(span)
            } else {
                spans.append(
                    PositionSpan(
                        uncheckedStart: Position(
                            uncheckedFile: nil,
                            line: 1,
                            column: 1
                        ),
                        uncheckedEnd: Position(
                            uncheckedFile: nil,
                            line: 1,
                            column: 1
                        )
                    )
                )
            }

            if token == .eof {
                break
            }
        }

        let occurrences = zip(tokens, spans).compactMap { token, span in
            occurrence(
                for: token,
                span: span
            )
        }

        let lexDiagnostics = lexer.diagnostics.map { diagnostic in
            ECDocumentDiagnostic(
                severity: mapSeverity(diagnostic.severity),
                code: diagnostic.kind.rawValue,
                message: diagnostic.message,
                span: diagnostic.span
            )
        }

        let editorDiagnostics = makeEditorDiagnostics(
            flavor: flavor,
            tokens: tokens,
            spans: spans
        )

        return ECDocumentAnalysis(
            source: source,
            flavor: flavor,
            tokens: tokens,
            spans: spans,
            diagnostics: ecDedupeDiagnostics(
                lexDiagnostics + editorDiagnostics
            ),
            occurrences: occurrences
        )
    }

    public static func semanticTokens(
        from analysis: ECDocumentAnalysis
    ) throws -> [ECSemanticToken] {
        try EntryCompilerSyntax.semanticTokens(
            source: analysis.source,
            flavor: analysis.flavor
        ).map { token in
            ECSemanticToken(
                line: token.line,
                startColumn: token.startColumn,
                length: token.length,
                kind: semanticKind(for: token.kind)
            )
        }
    }
}

private extension ECDocumentAnalyzer {
    @inline(__always)
    static func mapSeverity(
        _ severity: EntryCompilerLexDiagnosticSeverity
    ) -> ECDocumentDiagnosticSeverity {
        switch severity {
        case .error:
            return .error

        case .warning:
            return .warning
        }
    }

    static func makeEditorDiagnostics(
        flavor: EntryCompilerLexingFlavor,
        tokens: [EntryCompilerToken],
        spans: [PositionSpan]
    ) -> [ECDocumentDiagnostic] {
        switch flavor {
        case .entries,
             .transactions:
            return duplicateIDDiagnostics(
                tokens: tokens,
                spans: spans
            )

        default:
            return []
        }
    }

    static func duplicateIDDiagnostics(
        tokens: [EntryCompilerToken],
        spans: [PositionSpan]
    ) -> [ECDocumentDiagnostic] {
        let occurrences = ecDocumentIDOccurrences(
            tokens: tokens,
            spans: spans
        )

        var buckets: [String: [ECDocumentIDOccurrence]] = [:]
        for occurrence in occurrences {
            let key = "\(occurrence.namespace.rawValue)|\(occurrence.id)"
            buckets[key, default: []].append(occurrence)
        }

        var out: [ECDocumentDiagnostic] = []

        for group in buckets.values where group.count > 1 {
            for occurrence in group {
                let code: String
                let message: String

                switch occurrence.namespace {
                case .entry:
                    code = "duplicateEntryIDInDocument"
                    message = "Duplicate entry id \(occurrence.id) in current document."

                case .transaction:
                    code = "duplicateTransactionIDInDocument"
                    message = "Duplicate transaction id \(occurrence.id) in current document."
                }

                out.append(
                    ECDocumentDiagnostic(
                        severity: .warning,
                        code: code,
                        message: message,
                        span: occurrence.span
                    )
                )
            }
        }

        return out
    }

    @inline(__always)
    static func occurrence(
        for token: EntryCompilerToken,
        span: PositionSpan
    ) -> ECSymbolOccurrence? {
        switch token {
        case .keyword(let s):
            return .init(
                kind: .keyword,
                text: s,
                span: span
            )

        case .ident(let s):
            return .init(
                kind: .identifier,
                text: s,
                span: span
            )

        case .entity(let s):
            return .init(
                kind: .entityReference,
                text: s,
                span: span
            )

        case .account(let s):
            return .init(
                kind: .accountReference,
                text: s,
                span: span
            )

        case .number(let d):
            return .init(
                kind: .number,
                text: NSDecimalNumber(decimal: d).stringValue,
                span: span
            )

        case .string(let s):
            return .init(
                kind: .string,
                text: s,
                span: span
            )

        case .dateLiteral(let s):
            return .init(
                kind: .date,
                text: s,
                span: span
            )

        case .lBrace:
            return .init(kind: .punctuation, text: "{", span: span)

        case .rBrace:
            return .init(kind: .punctuation, text: "}", span: span)

        case .lPar:
            return .init(kind: .punctuation, text: "(", span: span)

        case .rPar:
            return .init(kind: .punctuation, text: ")", span: span)

        case .arrow:
            return .init(kind: .punctuation, text: "->", span: span)

        case .dot:
            return .init(kind: .punctuation, text: ".", span: span)

        case .equals:
            return .init(kind: .punctuation, text: "=", span: span)

        case .comma:
            return .init(kind: .punctuation, text: ",", span: span)

        case .hash:
            return .init(kind: .punctuation, text: "#", span: span)

        case .eof:
            return nil
        }
    }

    @inline(__always)
    static func semanticKind(
        for kind: EntryCompilerSyntax.Kind
    ) -> ECSemanticTokenKind {
        switch kind {
        case .keyword: .keyword
        case .identifier: .variable
        case .number: .number
        case .string: .string
        case .date: .property
        case .account: .type
        case .entity: .namespace
        case .comment: .comment
        case .punctuation: .operator
        }
    }
}
