import Accounting
import AccountingParsers
import AccountingSyntax
import Foundation
import SyntaxStyling
import Terminal

public enum ECSourceTerminalRenderer {}

extension ECSourceTerminalRenderer {
    public typealias Options = ECSourcePresentationOptions

    public static func render(
        files: [ECSourceFile],
        options: Options = .init(),
        theme: SyntaxTheme = EntryCompilerSyntax.sourceDarkTheme
    ) -> String {
        let document = ECSourcePresenter.present(
            files: files,
            options: options,
            theme: theme
        )

        return render(
            document: document,
            options: options
        )
    }

    public static func render(
        document: ECSourceDocument,
        options: Options = .init()
    ) -> String {
        ECSourceRendererShared.makeOutput(
            document: document,
            options: options,
            renderTitle: styledTitle,
            renderSubtitle: styledSubtitle,
            renderFilePath: styledFilePath,
            renderFileMeta: styledFileMeta,
            renderRule: styledRule,
            renderBlockCaption: styledBlockCaption,
            renderLine: renderedLine
        )
    }

    private static func renderedLine(
        _ line: ECSourcePresentedLine,
        showLineNumbers: Bool,
        lineNumberWidth: Int
    ) -> String {
        let text = renderedFragments(line)

        guard showLineNumbers else {
            return text
        }

        let number = String(line.number)
        let padding = String(
            repeating: " ",
            count: max(0, lineNumberWidth - number.count)
        )

        let gutter = "\(padding)\(number) │".ansi(.brightBlack)
        return "\(gutter) \(text)"
    }

    private static func renderedFragments(
        _ line: ECSourcePresentedLine
    ) -> String {
        guard let fragments = line.styledFragments else { return line.text }
        return fragments.map { styledFragment($0.text, style: $0.style) }.joined()
    }

    /// ANSI is introduced only when a terminal renderer consumes SyntaxStyle.
    private static func styledFragment(_ text: String, style: SyntaxStyle) -> String {
        var codes: [String] = []
        if let foreground = style.foreground {
            codes.append("38;2;\(foreground.red);\(foreground.green);\(foreground.blue)")
        }
        if let background = style.background {
            codes.append("48;2;\(background.red);\(background.green);\(background.blue)")
        }
        if let bold = style.bold { codes.append(bold ? "1" : "22") }
        if let italic = style.italic { codes.append(italic ? "3" : "23") }
        if let underline = style.underline { codes.append(underline ? "4" : "24") }
        guard !codes.isEmpty else { return text }
        return "\u{001B}[\(codes.joined(separator: ";"))m\(text)\u{001B}[0m"
    }

    private static func styledTitle(
        _ text: String
    ) -> String {
        text.ansi(.white, .bold)
    }

    private static func styledSubtitle(
        _ text: String
    ) -> String {
        text.ansi(.brightBlack)
    }

    private static func styledFilePath(
        _ text: String
    ) -> String {
        text.ansi(.brightBlue, .bold)
    }

    private static func styledFileMeta(
        _ text: String
    ) -> String {
        text.ansi(.brightBlack)
    }

    private static func styledBlockCaption(
        _ text: String
    ) -> String {
        text.ansi(.brightWhite, .bold)
    }

    private static func styledRule(
        _ length: Int
    ) -> String {
        String(
            repeating: "─",
            count: max(1, length)
        )
        .ansi(.brightBlack)
    }
}
