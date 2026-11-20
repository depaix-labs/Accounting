import AccountingSyntax
import AccountingCompiler
import Foundation
import Syntax
import SyntaxStyling
import Testing

private enum AccountingSyntaxFixtureError: Error {
    case missing_capture(String)
}

enum AccountingSyntaxTestSuite {
    static let suite = TestSuite("accounting-syntax", title: "Exact EC lexical syntax") {
        Test("EC vocabulary preserves language-specific kinds") {
            let language = try EntryCompilerSyntax.language()
            let vocabulary = try language.vocabulary()
            try Expect.equal(vocabulary.id, "ec", "language identity")
            try Expect.equal(vocabulary.definitions.count, 9, "all EC kinds declared")
            try Expect.equal(
                vocabulary.definition(named: "account")?.roles,
                [.identifier, .reference],
                "account role classification"
            )
        }

        Test("Unicode token offsets exclude trivia and quoted slashes") {
            let source = "  café \"//inside\" // outside\r\n42"
            let document = try EntryCompilerSyntax.document(source: source, flavor: .fallback)
            guard let identifier = document.captures.first(where: { $0.kind.name == "identifier" }),
                  let quoted = document.captures.first(where: { $0.kind.name == "string" }),
                  let comment = document.captures.first(where: { $0.kind.name == "comment" }) else {
                throw AccountingSyntaxFixtureError.missing_capture("identifier, string, comment")
            }
            try Expect.equal(identifier.segments[0].start.offset, 2, "leading trivia excluded")
            try Expect.equal(identifier.segments[0].end.offset, 7, "UTF-8, not scalar, end")
            try Expect.equal(String(document.text(in: identifier.segments[0]) ?? ""), "café", "exact unicode text")
            try Expect.equal(String(document.text(in: quoted.segments[0]) ?? ""), "\"//inside\"", "slash inside quotes remains a string")
            try Expect.equal(String(document.text(in: comment.segments[0]) ?? ""), "// outside", "only skipped comment classified")
            try Expect.equal(document.captures.filter { $0.kind.name == "comment" }.count, 1, "one actual comment")
            try Expect.equal(document.roles(for: identifier), [.identifier], "vocabulary default role")
        }

        Test("highlight projection preserves source, trivia, and CRLF") {
            let source = "  café \"//inside\" // outside\r\n42"
            let lines = try EntryCompilerSyntax.highlightedLines(
                source: source, flavor: .fallback, startingAtLine: 7
            )
            try Expect.equal(lines.map(\.number), [7, 8], "line numbering")
            try Expect.equal(lines[0].text, "  café \"//inside\" // outside\r", "original first line")
            try Expect.equal(lines[1].text, "42", "original second line")
            try Expect.equal(lines[0].fragments.first?.kind.rawValue, "plain", "trivia stays plain")
            try Expect.equal(lines[0].fragments.first(where: { $0.kind.rawValue == "identifier" })?.text, "café", "exact identifier")
            try Expect.equal(lines[0].fragments.first(where: { $0.kind.rawValue == "string" })?.text, "\"//inside\"", "quoted slashes stay string")
            try Expect.equal(lines[0].fragments.first(where: { $0.kind.rawValue == "comment" })?.text, "// outside", "comment is real trivia")
        }

        Test("highlight projection preserves multiline details classifications") {
            let source = "details {line 1\n// inside block\nline 3}\n// trailing"
            let lines = try EntryCompilerSyntax.highlightedLines(
                source: source, flavor: .entries, startingAtLine: 1
            )
            try Expect.equal(lines.count, 4, "all lines retained")
            try Expect.equal(lines[1].text, "// inside block", "raw block contents preserved")
            try Expect.equal(lines[1].fragments.first?.kind.rawValue, "string", "block slashes are not comments")
            try Expect.equal(lines[3].fragments.first?.kind.rawValue, "comment", "trailing actual comment")
        }

        Test("semantic tokens use UTF-16 columns and CRLF line positions") {
            let source = "\"\u{1F600}\" café // outside\r\n42"
            let tokens = try EntryCompilerSyntax.semanticTokens(
                source: source, flavor: .fallback
            )
            let coordinates = tokens.map {
                "\($0.line):\($0.startColumn):\($0.length):\($0.kind.rawValue)"
            }
            try Expect.equal(coordinates, [
                "0:0:4:string",
                "0:5:4:identifier",
                "0:10:10:comment",
                "1:0:2:number"
            ], "UTF-16 source positions and comment spans")
        }

        Test("multiline semantic captures split without false comments") {
            let source = "details {one\n// inside\nend}\n// outside"
            let tokens = try EntryCompilerSyntax.semanticTokens(
                source: source, flavor: .entries
            )
            try Expect.equal(
                tokens.filter { $0.kind == .string }.map(\.line),
                [0, 1, 2],
                "one multiline string becomes three line-bounded tokens"
            )
            try Expect.equal(
                tokens.filter { $0.kind == .comment }.map(\.line),
                [3],
                "only trailing trivia is a comment"
            )
        }

        Test("LSP full-document request works without position") {
            let data = try ECLSPProtocolFixture.fullSemanticTokens()
            try Expect.equal(data, [
                0, 0, 4, 3, 0,
                0, 5, 4, 1, 0,
                0, 5, 10, 6, 0,
                1, 0, 2, 2, 0
            ], "full framed JSON-RPC UTF-16 semantic tokens")
        }

        Test("EC source renderer remains the projection oracle") {
            let source = "  café \"//inside\" // outside\r\n42"
            let file = ECSourceFile(
                relativePath: "fixtures/demo.ec",
                absolutePath: "/tmp/fixtures/demo.ec",
                blocks: [ECSourceBlock(
                    kind: .unknown, source: source,
                    renderStartLine: 7, semanticStartLine: 7, endLine: 8
                )]
            )
            let options = ECSourcePresentationOptions(showLineNumbers: false)
            let presented = ECSourcePresenter.present(
                files: [file], options: options, theme: EntryCompilerSyntax.sourceLightTheme
            )
            let lines = presented.files[0].blocks[0].lines
            try Expect.equal(lines.map(\.number), [7, 8], "stable source line numbering")
            try Expect.equal(lines.map(\.text), [
                "  café \"//inside\" // outside\r", "42"
            ], "exact Unicode source and CRLF content")
            let kinds = lines[0].fragments.map { $0.kind.rawValue }
            try Expect.equal(kinds, [
                "plain", "identifier", "plain", "string", "plain", "comment", "plain"
            ], "source classes remain equivalent")
            let plain = ECSourceTextRenderer.render(document: presented, options: options)
            try Expect.equal(plain.contains("café \"//inside\" // outside\r\n42"), true,
                             "text rendering preserves original source")
            let ansi = ECSourceTerminalRenderer.render(document: presented, options: options)
            let stripped = ansi.replacingOccurrences(
                of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression
            )
            try Expect.equal(stripped, plain, "ANSI is final presentation only")
            let html = ECSourceHTMLRenderer.render(document: presented, options: options)
            try Expect.equal(html.contains("tok-string"), true, "HTML class mapping")
            try Expect.equal(html.contains("tok-comment"), true, "HTML comment mapping")
        }

        Test("shared projector equals legacy for nonoverlapping EC source") {
            let source = "details {one\n// inside\nend}\n// outside"
            let legacy = try EntryCompilerSyntax.highlightedLines(
                source: source, flavor: .entries, startingAtLine: 1
            )
            let shared = try EntryCompilerSyntax.projectedLines(
                source: source, flavor: .entries, startingAtLine: 1
            )
            try Expect.equal(shared.map(\.text), legacy.map(\.text), "source preservation")
            try Expect.equal(shared.map { $0.fragments.map { $0.kind.rawValue } },
                             legacy.map { $0.fragments.map { $0.kind.rawValue } },
                             "token boundary parity")
        }

        Test("generic LSP encoding retains EC protocol result") {
            let data = try EntryCompilerSyntax.encodedSemanticTokens(
                source: "\"\u{1F600}\" café // outside\r\n42", flavor: .fallback
            )
            try Expect.equal(data, [
                0, 0, 4, 3, 0,
                0, 5, 4, 1, 0,
                0, 5, 10, 6, 0,
                1, 0, 2, 2, 0
            ], "shared LSP encoder produces the expected protocol data")
        }

        Test("shared style map lowers identically into HTML and terminal") {
            let theme = SyntaxTheme.light.adding([
                .init(selector: .init(language: "ec", kind: "number"),
                      style: .init(foreground: .init(red: 1, green: 2, blue: 3), bold: true),
                      priority: 100)
            ])
            let file = ECSourceFile(
                relativePath: "fixture.ec", absolutePath: "/tmp/fixture.ec",
                blocks: [ECSourceBlock(kind: .unknown, source: "42",
                    renderStartLine: 1, semanticStartLine: 1, endLine: 1)]
            )
            let options = ECSourcePresentationOptions(showLineNumbers: false)
            let document = ECSourcePresenter.present(
                files: [file], options: options, theme: theme
            )
            guard let fragment = document.files[0].blocks[0].lines[0].styledFragments?.first else {
                throw AccountingSyntaxFixtureError.missing_capture("styled number")
            }
            try Expect.equal(fragment.kind, .number, "EC source kind remains available")
            try Expect.equal(fragment.style.foreground,
                SyntaxColor(red: 1, green: 2, blue: 3), "style originates in the shared theme")
            let html = ECSourceHTMLRenderer.render(document: document, options: options)
            try Expect.equal(html.contains("tok-number"), true, "semantic CSS class retained")
            try Expect.equal(html.contains("color:rgb(1,2,3)"), true,
                "HTML interprets the exact resolved RGB style")
            let ansi = ECSourceTerminalRenderer.render(document: document, options: options)
            try Expect.equal(ansi.contains("38;2;1;2;3"), true,
                "terminal interprets the same resolved RGB style")
        }

        Test("source format defaults select appearance without modifying layout options") {
            let file = ECSourceFile(
                relativePath: "fixture.ec", absolutePath: "/tmp/fixture.ec",
                blocks: [ECSourceBlock(
                    kind: .unknown, source: "\"hello\"",
                    renderStartLine: 1, semanticStartLine: 1, endLine: 1
                )]
            )
            let options = ECSourcePresentationOptions(showLineNumbers: false)
            let ansi = ECSourceTerminalRenderer.render(files: [file], options: options)
            let html = ECSourceHTMLRenderer.render(files: [file], options: options)
            try Expect.equal(ansi.contains("38;2;145;220;150"), true,
                             "terminal defaults to dark lexical strings")
            try Expect.equal(html.contains("color:rgb(30,120,55)"), true,
                             "HTML defaults to light lexical strings")
            let overridden = ECSourceTerminalRenderer.render(
                files: [file], options: options,
                theme: EntryCompilerSyntax.sourceLightTheme
            )
            try Expect.equal(overridden.contains("38;2;30;120;55"), true,
                             "explicit concrete theme overrides destination default")
        }

        Test("disabled highlighting has no syntax styling") {
            let file = ECSourceFile(
                relativePath: "fixture.ec", absolutePath: "/tmp/fixture.ec",
                blocks: [ECSourceBlock(kind: .unknown, source: "42",
                    renderStartLine: 1, semanticStartLine: 1, endLine: 1)]
            )
            let options = ECSourcePresentationOptions(
                showLineNumbers: false, syntaxHighlighting: false
            )
            let document = ECSourcePresenter.present(
                files: [file], options: options, theme: EntryCompilerSyntax.sourceLightTheme
            )
            try Expect.equal(document.files[0].blocks[0].lines[0].styledFragments == nil,
                true, "unstyled lines have no resolved syntax colors")
            let html = ECSourceHTMLRenderer.render(document: document, options: options)
            try Expect.equal(html.contains("tok-number"), false,
                "HTML does not classify plain source")
        }

        Test("multiline details blocks do not create false comments") {
            let source = "details {line 1\n// inside block\nline 3}\n// trailing"
            let document = try EntryCompilerSyntax.document(source: source, flavor: .entries)
            guard let content = document.captures.first(where: { $0.kind.name == "string" }),
                  let comment = document.captures.first(where: { $0.kind.name == "comment" }) else {
                throw AccountingSyntaxFixtureError.missing_capture("details content and trailing comment")
            }
            try Expect.equal(
                String(document.text(in: content.segments[0]) ?? ""),
                "line 1\n// inside block\nline 3",
                "verbatim details content"
            )
            try Expect.equal(
                String(document.text(in: comment.segments[0]) ?? ""),
                "// trailing",
                "comment after last token captured at EOF"
            )
            try Expect.equal(document.captures.filter { $0.kind.name == "comment" }.count, 1, "no comment inside details")
        }
    }
}
