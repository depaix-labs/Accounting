import Accounting
import AccountingParsers
import AccountingSyntax
import Foundation
import SyntaxStyling

public enum ECSourcePresenter {
    public static func present(
        files: [ECSourceFile],
        options: ECSourcePresentationOptions = .init(),
        theme: SyntaxTheme
    ) -> ECSourceDocument {
        ECSourceDocument(
            title: options.title,
            subtitle: options.subtitle,
            files: files.map {
                presentedFile(
                    from: $0,
                    options: options,
                    theme: theme
                )
            }
        )
    }

    private static func presentedFile(
        from file: ECSourceFile,
        options: ECSourcePresentationOptions,
        theme: SyntaxTheme
    ) -> ECSourcePresentedFile {
        ECSourcePresentedFile(
            relativePath: file.relativePath,
            blockCount: file.blocks.count,
            blocks: file.blocks.map {
                presentedBlock(
                    from: $0,
                    options: options,
                    theme: theme
                )
            }
        )
    }

    private static func presentedBlock(
        from block: ECSourceBlock,
        options: ECSourcePresentationOptions,
        theme: SyntaxTheme
    ) -> ECSourcePresentedBlock {
        let presentation = presentedLines(
            from: block,
            options: options,
            theme: theme
        )

        let lineRange = "\(block.renderStartLine)–\(block.endLine)"
        var caption = "\(block.kind.rawValue) · lines \(lineRange)"

        if let summary = block.summary?.compactDescription {
            caption += " · \(summary)"
        }
        if let failure = presentation.syntaxFailure {
            caption += " · syntax highlighting unavailable: \(failure)"
        }

        return ECSourcePresentedBlock(
            kind: block.kind,
            caption: caption,
            lines: presentation.lines,
            renderStartLine: block.renderStartLine,
            semanticStartLine: block.semanticStartLine,
            endLine: block.endLine,
            summary: block.summary
        )
    }

    private static func presentedLines(
        from block: ECSourceBlock,
        options: ECSourcePresentationOptions,
        theme: SyntaxTheme
    ) -> (lines: [ECSourcePresentedLine], syntaxFailure: String?) {
        if options.syntaxHighlighting {
            do {
                let styled = try EntryCompilerSyntax.styledLines(
                    source: block.source,
                    flavor: lexingFlavor(for: block.kind),
                    startingAtLine: block.renderStartLine,
                    theme: theme
                )
                return (styled.map { line in
                    ECSourcePresentedLine(
                        number: line.number,
                        fragments: line.fragments.map(\.fragment),
                        styledFragments: line.fragments
                    )
                }, nil)
            } catch {
                return (plainLines(from: block), String(describing: error))
            }
        }
        return (plainLines(from: block), nil)
    }

    private static func plainLines(from block: ECSourceBlock) -> [ECSourcePresentedLine] {
        block.source.components(separatedBy: "\n").enumerated().map { offset, text in
            ECSourcePresentedLine(
                number: block.renderStartLine + offset,
                fragments: [ECSyntaxFragment(text: text, kind: .plain)]
            )
        }
    }

    private static func lexingFlavor(
        for kind: ECSourceBlockKind
    ) -> EntryCompilerLexingFlavor {
        switch kind {
        case .entry:
            return .entries

        case .entity:
            return .entities

        case .account:
            return .accounts

        case .transaction:
            return .transactions

        case .document:
            return .documents

        case .settings:
            return .settings

        case .assertion, .unknown:
            return .fallback
        }
    }
}
