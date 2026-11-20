import AccountingParsers
import Syntax
import SyntaxStyling

/// EC-specific presets; generic style resolution belongs to SyntaxStyling.
public extension EntryCompilerSyntax {
    static let sourceLightTheme = SyntaxTheme.light.adding([
        .init(selector: .init(language: "ec", kind: "account"),
              style: .init(foreground: .init(red: 93, green: 74, blue: 47), bold: true)),
        .init(selector: .init(language: "ec", kind: "entity"),
              style: .init(foreground: .init(red: 180, green: 83, blue: 9), bold: true)),
        .init(selector: .init(language: "ec", kind: "date"),
              style: .init(foreground: .init(red: 75, green: 100, blue: 125))),
        .init(selector: .init(language: "ec", kind: "punctuation"),
              style: .init(foreground: .init(red: 114, green: 121, blue: 133)))
    ])

    static let sourceDarkTheme = SyntaxTheme.dark.adding([
        .init(selector: .init(language: "ec", kind: "account"),
              style: .init(foreground: .init(red: 232, green: 180, blue: 110), bold: true)),
        .init(selector: .init(language: "ec", kind: "entity"),
              style: .init(foreground: .init(red: 248, green: 200, blue: 115), bold: true)),
        .init(selector: .init(language: "ec", kind: "date"),
              style: .init(foreground: .init(red: 150, green: 190, blue: 220))),
        .init(selector: .init(language: "ec", kind: "punctuation"),
              style: .init(foreground: .init(red: 150, green: 160, blue: 175)))
    ])

    static func styledLines(
        source: String,
        flavor: EntryCompilerLexingFlavor,
        startingAtLine startLine: Int,
        theme: SyntaxTheme
    ) throws -> [ECStyledSyntaxLine] {
        let document = try document(source: source, flavor: flavor)
        let lines = try SyntaxStyling.project(document: document, theme: theme)
        let bytes = Array(source.utf8)

        return try lines.map { line in
            var fragments: [ECStyledSyntaxFragment] = []

            func append(_ range: SyntaxSourceRange, kind: ECSyntaxKind, style: SyntaxStyle) {
                guard !range.isEmpty else { return }
                let text = String(decoding: bytes[range.start.offset..<range.end.offset], as: UTF8.self)
                if let last = fragments.last, last.kind == kind, last.style == style {
                    fragments[fragments.count - 1] = ECStyledSyntaxFragment(
                        fragment: ECSyntaxFragment(text: last.text + text, kind: kind), style: style
                    )
                } else {
                    fragments.append(ECStyledSyntaxFragment(
                        fragment: ECSyntaxFragment(text: text, kind: kind), style: style
                    ))
                }
            }

            for run in line.runs {
                let kind: ECSyntaxKind
                if let capture = run.source.captures.last(where: { $0.layer == .lexical }) {
                    guard let classified = ECSyntaxKind(rawValue: capture.kind.name) else {
                        throw HighlightError.unsupported_kind(capture.kind.name)
                    }
                    kind = classified
                } else {
                    kind = .plain
                }
                append(run.source.range, kind: kind, style: run.style)
            }

            // Preserve the existing EC convention for CRLF source lines.
            if line.source.terminator.length == 2,
               bytes[line.source.terminator.start.offset] == 13 {
                let offset = line.source.terminator.start.offset
                append(try SyntaxSourceRange(start: offset, end: offset + 1),
                       kind: .plain, style: .init())
            }
            return ECStyledSyntaxLine(number: startLine + line.source.index, fragments: fragments)
        }
    }
}

public struct ECStyledSyntaxFragment: Sendable {
    public let fragment: ECSyntaxFragment
    public let style: SyntaxStyle

    public init(fragment: ECSyntaxFragment, style: SyntaxStyle) {
        self.fragment = fragment
        self.style = style
    }

    public var text: String { fragment.text }
    public var kind: ECSyntaxKind { fragment.kind }
}

public struct ECStyledSyntaxLine: Sendable {
    public let number: Int
    public let fragments: [ECStyledSyntaxFragment]

    public init(number: Int, fragments: [ECStyledSyntaxFragment]) {
        self.number = number
        self.fragments = fragments
    }
}
