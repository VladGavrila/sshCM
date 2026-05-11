import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    private var blocks: [Block] { MarkdownView.parse(text) }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(inline(content))
                .font(headingFont(level))
                .bold()
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let content):
            Text(inline(content))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.ordered ? "\(item.index)." : "•")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(inline(item.content))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(item.indent) * 16)
                }
            }
        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    private func inline(_ s: String) -> AttributedString {
        if let a = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return a
        }
        return AttributedString(s)
    }
}

extension MarkdownView {
    enum Block {
        case heading(level: Int, content: String)
        case paragraph(String)
        case list(items: [ListItem])
        case codeBlock(String)
        case rule
    }

    struct ListItem {
        let indent: Int
        let ordered: Bool
        let index: Int
        let content: String
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var paragraph: [String] = []
        var listItems: [ListItem] = []
        var codeLines: [String] = []
        var inFence = false
        var orderedCounters: [Int: Int] = [:]

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }
        func flushList() {
            guard !listItems.isEmpty else { return }
            blocks.append(.list(items: listItems))
            listItems.removeAll()
            orderedCounters.removeAll()
        }

        for raw in lines {
            if inFence {
                if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inFence = false
                } else {
                    codeLines.append(raw)
                }
                continue
            }

            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph(); flushList()
                inFence = true
                continue
            }

            if trimmed.isEmpty {
                flushParagraph(); flushList()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph(); flushList()
                blocks.append(.rule)
                continue
            }

            if let (level, content) = headingMatch(trimmed) {
                flushParagraph(); flushList()
                blocks.append(.heading(level: level, content: content))
                continue
            }

            let indent = leadingSpaces(raw) / 2
            if let bullet = bulletMatch(trimmed) {
                flushParagraph()
                listItems.append(ListItem(indent: indent, ordered: false, index: 0, content: bullet))
                continue
            }
            if let (num, content) = orderedMatch(trimmed) {
                flushParagraph()
                let idx = num ?? ((orderedCounters[indent] ?? 0) + 1)
                orderedCounters[indent] = idx
                listItems.append(ListItem(indent: indent, ordered: true, index: idx, content: content))
                continue
            }

            // Continuation of a list item if indented under one.
            if !listItems.isEmpty, leadingSpaces(raw) > 0 {
                var last = listItems.removeLast()
                last = ListItem(indent: last.indent, ordered: last.ordered, index: last.index,
                                content: last.content + " " + trimmed)
                listItems.append(last)
                continue
            }

            flushList()
            paragraph.append(trimmed)
        }

        if inFence, !codeLines.isEmpty {
            blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        flushList()
        return blocks
    }

    private static func leadingSpaces(_ s: String) -> Int {
        var n = 0
        for c in s {
            if c == " " { n += 1 }
            else if c == "\t" { n += 4 }
            else { break }
        }
        return n
    }

    private static func headingMatch(_ s: String) -> (Int, String)? {
        var level = 0
        for c in s {
            if c == "#" { level += 1 } else { break }
            if level > 6 { return nil }
        }
        guard level > 0, level < s.count else { return nil }
        let idx = s.index(s.startIndex, offsetBy: level)
        let rest = s[idx...]
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletMatch(_ s: String) -> String? {
        guard let first = s.first, first == "-" || first == "*" || first == "+" else { return nil }
        let after = s.dropFirst()
        guard after.first == " " else { return nil }
        return String(after.dropFirst())
    }

    private static func orderedMatch(_ s: String) -> (Int?, String)? {
        var digits = ""
        var i = s.startIndex
        while i < s.endIndex, s[i].isNumber {
            digits.append(s[i])
            i = s.index(after: i)
        }
        guard !digits.isEmpty, i < s.endIndex, s[i] == "." else { return nil }
        let next = s.index(after: i)
        guard next < s.endIndex, s[next] == " " else { return nil }
        return (Int(digits), String(s[s.index(after: next)...]))
    }
}
