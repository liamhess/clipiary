import AppKit
import Foundation

/// Converts rich-text clipboard content (HTML or RTF) to a plain Markdown string.
/// HTML items are parsed directly for full heading and list support.
/// RTF items are decoded via NSAttributedString for inline formatting and heading heuristics.
enum MarkdownSerializer {

    static func fromHTML(_ html: String) -> String {
        HTMLConverter(html).convert()
    }

    static func fromRTF(_ data: Data) -> String {
        guard let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) else { return "" }
        return RTFConverter(src: attrStr).convert()
    }
}

// MARK: - HTML → Markdown

private final class HTMLConverter {

    private static let hrefRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(?i)href\s*=\s*(?:"([^"]*)"|'([^']*)'|(\S+))"#)

    private let src: String
    private var idx: String.Index

    private var out = ""
    private var inPre = false
    private var skipDepth = 0          // >0 inside <script>, <style>, <head>
    private var hrefs: [String] = []   // href stack for nested/malformed <a>
    private var lists: [(ordered: Bool, counter: Int)] = []
    private var afterListMarker = false // suppress \n\n from <p> right after a list marker
    private var tableFirstRowDone = false
    private var tableCurrentCellCount = 0

    init(_ src: String) {
        self.src = src
        idx = src.startIndex
    }

    func convert() -> String {
        while idx < src.endIndex {
            src[idx] == "<" ? parseTag() : parseText()
        }
        return finalise(out)
    }

    // MARK: Parsing

    private func advance(_ n: Int = 1) {
        idx = src.index(idx, offsetBy: n, limitedBy: src.endIndex) ?? src.endIndex
    }

    private func parseTag() {
        advance() // consume '<'

        // Comment / doctype
        if src[idx...].hasPrefix("!") {
            if src[idx...].hasPrefix("!--") {
                advance(3)
                while idx < src.endIndex {
                    if src[idx...].hasPrefix("-->") { advance(3); break }
                    advance()
                }
            } else {
                skipToTagEnd()
            }
            return
        }

        let closing = idx < src.endIndex && src[idx] == "/"
        if closing { advance() }

        var name = ""
        while idx < src.endIndex, !isTagBoundary(src[idx]) {
            name.append(src[idx]); advance()
        }
        name = name.lowercased()

        var rawAttrs = ""
        while idx < src.endIndex && src[idx] != ">" {
            rawAttrs.append(src[idx])
            advance()
        }
        let selfClose = rawAttrs.hasSuffix("/")
        if selfClose { rawAttrs = String(rawAttrs.dropLast()) }
        if idx < src.endIndex { advance() } // consume '>'

        if closing {
            handleClose(name)
        } else {
            handleOpen(name, attrs: rawAttrs)
            let voidTags = ["area","base","br","col","embed","hr","img","input",
                            "link","meta","param","source","track","wbr"]
            if selfClose || voidTags.contains(name) { handleClose(name) }
        }
    }

    private func parseText() {
        var text = ""
        while idx < src.endIndex && src[idx] != "<" { text.append(src[idx]); advance() }
        guard skipDepth == 0 else { return }
        if inPre {
            out += text
        } else {
            let decoded = decodeEntities(text)
            // Collapse all whitespace sequences to a single space (HTML rendering semantics)
            let normalized = decoded.replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ",
                                                          options: .regularExpression)
            if normalized.isEmpty { return }
            if normalized == " " {
                // Preserve a space between inline elements, but not at block boundaries
                if let last = out.last, last != "\n" && last != " " { out += " " }
                return
            }
            afterListMarker = false
            out += normalized
        }
    }

    private func skipToTagEnd() {
        while idx < src.endIndex && src[idx] != ">" { advance() }
        if idx < src.endIndex { advance() }
    }

    private func isTagBoundary(_ c: Character) -> Bool {
        c == ">" || c == " " || c == "\t" || c == "\n" || c == "\r" || c == "/"
    }

    // MARK: Tag handlers

    private func handleOpen(_ name: String, attrs: String) {
        if name == "script" || name == "style" || name == "head" { skipDepth += 1; return }
        guard skipDepth == 0 else { return }
        switch name {
        case "h1": out += "\n\n# "
        case "h2": out += "\n\n## "
        case "h3": out += "\n\n### "
        case "h4": out += "\n\n#### "
        case "h5": out += "\n\n##### "
        case "h6": out += "\n\n###### "
        case "p", "div", "section", "article", "header", "footer", "main", "nav", "aside":
            if afterListMarker { afterListMarker = false } else { out += "\n\n" }
        case "br":  out += "\n"
        case "hr":  out += "\n\n---\n\n"
        case "pre": inPre = true; out += "\n\n```\n"
        case "code":   if !inPre { out += "`" }
        case "strong", "b": out += "**"
        case "em", "i":     out += "*"
        case "s", "del":    out += "~~"
        case "a":
            hrefs.append(hrefAttr(attrs) ?? "")
            out += "["
        case "ul": lists.append((ordered: false, counter: 0)); out += "\n"
        case "ol": lists.append((ordered: true,  counter: 0)); out += "\n"
        case "li":
            let indent = String(repeating: "  ", count: max(0, lists.count - 1))
            if !lists.isEmpty {
                if lists[lists.count - 1].ordered {
                    lists[lists.count - 1].counter += 1
                    out += "\n\(indent)\(lists[lists.count - 1].counter). "
                } else {
                    out += "\n\(indent)- "
                }
            } else {
                out += "\n- "
            }
            afterListMarker = true
        case "blockquote": out += "\n\n> "
        case "table":      out += "\n\n"; tableFirstRowDone = false; tableCurrentCellCount = 0
        case "tr":         out += "\n"
        case "th", "td":   out += "| "; if !tableFirstRowDone { tableCurrentCellCount += 1 }
        default: break
        }
    }

    private func handleClose(_ name: String) {
        if name == "script" || name == "style" || name == "head" {
            skipDepth = max(0, skipDepth - 1); return
        }
        guard skipDepth == 0 else { return }
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6": out += "\n\n"
        case "p", "div", "section", "article", "header", "footer", "main", "nav", "aside":
            out += "\n\n"
        case "pre":  inPre = false; out += "\n```\n\n"
        case "code": if !inPre { out += "`" }
        case "strong", "b": out += "**"
        case "em", "i":     out += "*"
        case "s", "del":    out += "~~"
        case "a":
            let href = hrefs.isEmpty ? "" : hrefs.removeLast()
            out += href.isEmpty ? "]" : "](\(href))"
        case "ul", "ol":
            if !lists.isEmpty { lists.removeLast() }
            out += "\n"
        case "li":
            afterListMarker = false
        case "th", "td": out += " "
        case "tr":
            out += "|"
            if !tableFirstRowDone && tableCurrentCellCount > 0 {
                let sep = Array(repeating: " --- ", count: tableCurrentCellCount).joined(separator: "|")
                out += "\n|\(sep)|"
                tableFirstRowDone = true
            }
        default: break
        }
    }

    // MARK: Utilities

    private func hrefAttr(_ attrs: String) -> String? {
        guard let re = HTMLConverter.hrefRegex,
              let m = re.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs))
        else { return nil }
        for g in 1...3 {
            let r = m.range(at: g)
            if r.location != NSNotFound, let sr = Range(r, in: attrs) { return String(attrs[sr]) }
        }
        return nil
    }

    private func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&nbsp;",  with: " ")
         .replacingOccurrences(of: "&amp;",   with: "&")
         .replacingOccurrences(of: "&lt;",    with: "<")
         .replacingOccurrences(of: "&gt;",    with: ">")
         .replacingOccurrences(of: "&quot;",  with: "\"")
         .replacingOccurrences(of: "&apos;",  with: "'")
         .replacingOccurrences(of: "&#39;",   with: "'")
    }

    private func finalise(_ s: String) -> String {
        s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - RTF → Markdown (via NSAttributedString)

private struct RTFConverter {

    let src: NSAttributedString

    func convert() -> String {
        let str = src.string
        guard !str.isEmpty else { return "" }

        var paragraphs: [String] = []
        var paraStart = str.startIndex
        var j = str.startIndex

        while j < str.endIndex {
            if str[j] == "\n" {
                flushParagraph(from: paraStart, to: j, into: &paragraphs)
                paraStart = str.index(after: j)
            }
            j = str.index(after: j)
        }
        flushParagraph(from: paraStart, to: str.endIndex, into: &paragraphs)

        return paragraphs.joined(separator: "\n\n")
    }

    private func flushParagraph(from start: String.Index, to end: String.Index,
                                into paragraphs: inout [String]) {
        guard start < end else { return }
        let str = src.string
        let nsRange = NSRange(start..<end, in: str)
        let inline = buildInline(nsRange)
        let trimmed = inline.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        paragraphs.append(headingPrefix(nsRange) + trimmed)
    }

    private func buildInline(_ nsRange: NSRange) -> String {
        let str = src.string
        var result = ""
        src.enumerateAttributes(in: nsRange, options: []) { attrs, runRange, _ in
            guard let sr = Range(runRange, in: str) else { return }
            var text = String(str[sr])
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\u{FFFC}", with: "") // attachment placeholder
            guard !text.isEmpty else { return }

            let font   = attrs[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let isBold   = traits.contains(.boldFontMask)
            let isItalic = traits.contains(.italicFontMask)
            let isMono   = traits.contains(.fixedPitchFontMask)

            let link: URL?
            switch attrs[.link] {
            case let u as URL:    link = u
            case let s as String: link = URL(string: s)
            default:              link = nil
            }

            if let url = link {
                text = "[\(text)](\(url.absoluteString))"
            } else if isMono {
                text = "`\(text)`"
            } else if isBold && isItalic {
                text = "***\(text)***"
            } else if isBold {
                text = "**\(text)**"
            } else if isItalic {
                text = "*\(text)*"
            }
            result += text
        }
        return result
    }

    // Headings are heuristic for RTF: map dominant font size to heading level.
    // Most RTF body text is 10–12 pt; heading sizes vary by document.
    private func headingPrefix(_ nsRange: NSRange) -> String {
        var maxPt: CGFloat = 0
        src.enumerateAttribute(.font, in: nsRange, options: []) { val, _, _ in
            if let f = val as? NSFont { maxPt = max(maxPt, f.pointSize) }
        }
        switch maxPt {
        case 28...:    return "# "
        case 24..<28:  return "## "
        case 20..<24:  return "### "
        case 17..<20:  return "#### "
        case 14..<17:  return "##### "
        default:       return ""
        }
    }
}
