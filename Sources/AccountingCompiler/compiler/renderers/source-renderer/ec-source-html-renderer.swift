import Accounting
import AccountingParsers
import AccountingSyntax
import Foundation
import SyntaxStyling
import HTML
import CSS

public enum ECSourceHTMLRenderer {}

extension ECSourceHTMLRenderer {
    static func fileBlockCountLabel(
        _ count: Int
    ) -> String {
        count == 1 ? "1 block" : "\(count) blocks"
    }
}

extension ECSourceHTMLRenderer {
    public typealias Options = ECSourcePresentationOptions

    public static func render(
        files: [ECSourceFile],
        options: Options = .init(),
        theme: SyntaxTheme = EntryCompilerSyntax.sourceLightTheme
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
        let css = ECSourceHTMLRendererCSS
            .base(compact: options.compact)
            .render(
                options: CSSRenderOptions(
                    ensureTrailingNewline: false
                )
            )

        let doc = HTML.document {
            HTML.html(["lang": "nl"]) {
                HTML.head {
                    HTML.meta(.charset())
                    HTML.meta(.viewport())
                    HTML.title(document.title)
                    HTML.style(css)
                }

                HTML.body {
                    HTML.h1 {
                        HTML.text(document.title)
                    }

                    if let subtitle = document.subtitle {
                        HTML.div(["class": "subtitle"]) {
                            HTML.text(subtitle)
                        }
                    }

                    for file in document.files {
                        renderFile(
                            file,
                            options: options
                        )
                    }
                }
            }
        }

        return doc.render(default: .minified, doctype: true)
    }

    @HTMLBuilder
    static func renderFile(
        _ file: ECSourcePresentedFile,
        options: Options
    ) -> [any HTMLNode] {
        HTML.section(["class": "src-file"]) {
            HTML.div(["class": "src-file-header"]) {
                HTML.div(["class": "src-file-path"]) {
                    HTML.text(file.relativePath)
                }

                if options.includeFileBlockCounts {
                    HTML.div(["class": "src-file-meta"]) {
                        // HTML.text("\(file.blockCount) block(s)")
                        HTML.text(fileBlockCountLabel(file.blockCount))
                    }
                }
            }

            for block in file.blocks {
                renderBlock(
                    block,
                    options: options
                )
            }
        }
    }

    @HTMLBuilder
    static func renderBlock(
        _ block: ECSourcePresentedBlock,
        options: Options
    ) -> [any HTMLNode] {
        HTML.div(["class": "src-block"]) {
            HTML.div(["class": "src-block-header"]) {
                HTML.text(block.caption)
            }

            HTML.div(["class": "src-lines"]) {
                for line in block.lines {
                    renderLine(
                        line,
                        showLineNumbers: options.showLineNumbers
                    )
                }
            }
        }
    }

    static func renderLine(
        _ line: ECSourcePresentedLine,
        showLineNumbers: Bool
    ) -> any HTMLNode {
        HTML.div(["class": "src-line"]) {
            HTML.span([
                "class": showLineNumbers
                    ? "src-line-no"
                    : "src-line-no src-line-no-hidden"
            ]) {
                HTML.text("\(line.number)")
            }

            HTML.span(["class": "src-line-text"]) {
                renderFragments(line)
            }
        }
    }

    static func renderFragments(
        _ line: ECSourcePresentedLine
    ) -> [any HTMLNode] {
        let fragments = line.styledFragments ?? line.fragments.map {
            ECStyledSyntaxFragment(fragment: $0, style: .init())
        }

        return fragments.map { fragment -> any HTMLNode in
            let cssClass = tokenClass(for: fragment.kind)
            let style = styleAttribute(fragment.style)

            guard cssClass != nil || style != nil else {
                return HTML.text(fragment.text)
            }

            var attributes = HTMLAttribute()
            if let cssClass {
                attributes.merge(.class(cssClass))
            }
            if let style {
                attributes.merge(["style": style])
            }

            return HTML.span(attributes) {
                HTML.text(fragment.text)
            }
        }
    }

    /// HTML is a final interpretation of platform-neutral SyntaxStyle.
    private static func styleAttribute(_ style: SyntaxStyle) -> String? {
        var declarations: [String] = []
        if let color = style.foreground {
            declarations.append("color:rgb(\(color.red),\(color.green),\(color.blue))")
        }
        if let color = style.background {
            declarations.append("background-color:rgb(\(color.red),\(color.green),\(color.blue))")
        }
        if let bold = style.bold { declarations.append("font-weight:\(bold ? "bold" : "normal")") }
        if let italic = style.italic { declarations.append("font-style:\(italic ? "italic" : "normal")") }
        if let underline = style.underline {
            declarations.append("text-decoration:\(underline ? "underline" : "none")")
        }
        return declarations.isEmpty ? nil : declarations.joined(separator: ";")
    }

    static func tokenClass(
        for kind: ECSyntaxKind
    ) -> String? {
        switch kind {
        case .plain:
            return nil

        case .keyword:
            return "tok-keyword"

        case .identifier:
            return "tok-ident"

        case .account:
            return "tok-account"

        case .entity:
            return "tok-entity"

        case .number:
            return "tok-number"

        case .string:
            return "tok-string"

        case .date:
            return "tok-date"

        case .punctuation:
            return "tok-punct"

        case .comment:
            return "tok-comment"
        }
    }
}



// extension ECSourceHTMLRenderer {
//     public typealias Options = ECSourcePresentationOptions

//     public static func render(
//         files: [ECSourceFile],
//         options: Options = .init()
//     ) -> String {
//         let document = ECSourcePresenter.present(
//             files: files,
//             options: options
//         )

//         return render(
//             document: document,
//             options: options
//         )
//     }

//     public static func render(
//         document: ECSourceDocument,
//         options: Options = .init()
//     ) -> String {
//         let css = ECSourceHTMLRendererCSS
//             .base(compact: options.compact)
//             .render(
//                 options: CSSRenderOptions(
//                     ensureTrailingNewline: false
//                 )
//             )

//         let doc = HTML.document {
//             HTML.html(["lang": "nl"]) {
//                 HTML.head {
//                     HTML.meta(.charset())
//                     HTML.meta(.viewport())
//                     HTML.title(document.title)
//                     HTML.style(css)
//                 }

//                 HTML.body {
//                     HTML.h1 {
//                         HTML.text(document.title)
//                     }

//                     if let subtitle = document.subtitle {
//                         HTML.div(["class": "subtitle"]) {
//                             HTML.text(subtitle)
//                         }
//                     }

//                     for file in document.files {
//                         renderFile(
//                             file,
//                             options: options
//                         )
//                     }
//                 }
//             }
//         }

//         return doc.render(default: .minified, doctype: true)
//     }

//     @HTMLBuilder
//     static func renderFile(
//         _ file: ECSourcePresentedFile,
//         options: Options
//     ) -> [any HTMLNode] {
//         HTML.section(["class": "src-file"]) {
//             HTML.div(["class": "src-file-header"]) {
//                 HTML.div(["class": "src-file-path"]) {
//                     HTML.text(file.relativePath)
//                 }

//                 if options.includeFileBlockCounts {
//                     HTML.div(["class": "src-file-meta"]) {
//                         HTML.text(fileBlockCountLabel(file.blockCount))
//                     }
//                 }
//             }

//             for block in file.blocks {
//                 renderBlock(
//                     block,
//                     options: options
//                 )
//             }
//         }
//     }

//     @HTMLBuilder
//     static func renderBlock(
//         _ block: ECSourcePresentedBlock,
//         options: Options
//     ) -> [any HTMLNode] {
//         HTML.div(["class": "src-block"]) {
//             HTML.div(["class": "src-block-header"]) {
//                 HTML.text(block.caption)
//             }

//             HTML.div(["class": "src-lines"]) {
//                 for line in block.lines {
//                     renderLine(
//                         line,
//                         showLineNumbers: options.showLineNumbers
//                     )
//                 }
//             }
//         }
//     }

//     static func renderLine(
//         _ line: ECSourcePresentedLine,
//         showLineNumbers: Bool
//     ) -> any HTMLNode {
//         HTML.div(["class": "src-line"]) {
//             HTML.span([
//                 "class": showLineNumbers
//                     ? "src-line-no"
//                     : "src-line-no src-line-no-hidden"
//             ]) {
//                 HTML.text("\(line.number)")
//             }

//             HTML.span(["class": "src-line-text"]) {
//                 HTML.text(line.text)
//             }
//         }
//     }
// }
