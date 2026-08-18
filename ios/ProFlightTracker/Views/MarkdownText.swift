import SwiftUI

/// Lightweight renderer for LLM-written markdown: `##` headings, `**bold**`
/// and other inline spans, `---` dividers, and bullet/numbered lists become
/// styled rich text instead of literal syntax characters on screen.
/// Block structure is parsed by hand (AttributedString's markdown init only
/// handles inline spans); inline formatting goes through the system parser.
struct MarkdownText: View {
    let markdown: String
    var font: Font = .subheadline
    var color: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block model

    private enum Block {
        case heading(level: Int, text: String)
        case divider
        case bullet(String)
        case numbered(label: String, text: String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            result.append(.paragraph(paragraphBuffer.joined(separator: " ")))
            paragraphBuffer = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if isDivider(line) {
                flushParagraph()
                result.append(.divider)
            } else if line.hasPrefix("#") {
                flushParagraph()
                let level = line.prefix(while: { $0 == "#" }).count
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if text.isEmpty { continue }
                result.append(.heading(level: level, text: text))
            } else if let bullet = bulletText(line) {
                flushParagraph()
                result.append(.bullet(bullet))
            } else if let (label, text) = numberedItem(line) {
                flushParagraph()
                result.append(.numbered(label: label, text: text))
            } else {
                paragraphBuffer.append(line)
            }
        }
        flushParagraph()
        return result
    }

    /// `---`, `***`, `___` (3+ of the same rule character, nothing else).
    private func isDivider(_ line: String) -> Bool {
        guard line.count >= 3, let first = line.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return line.allSatisfy { $0 == first }
    }

    private func bulletText(_ line: String) -> String? {
        for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// "1. text" / "2) text" → ("1.", "text").
    private func numberedItem(_ line: String) -> (label: String, text: String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return ("\(digits).", text)
    }

    // MARK: - Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level <= 2 ? .subheadline.weight(.bold) : .footnote.weight(.bold))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        case .divider:
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.vertical, 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Theme.teal)
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)
                Text(inline(text))
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .numbered(let label, let text):
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .font(font.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text(inline(text))
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let text):
            Text(inline(text))
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Inline spans (**bold**, *italic*, `code`) via the system parser; the
    /// raw string wins over a crash or dropped text if parsing fails.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
