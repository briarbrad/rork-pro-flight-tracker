import Foundation

/// Pulls the single forward-looking "Outlook" line out of the analyst
/// narrative — the first concrete item under its "What Would Change the
/// Picture" (or similar) section.
///
/// The narrative is model-written prose the backend prompt explicitly asks
/// to include ("what would change the picture, and what is worth watching
/// next"), so this knowledge already exists — it was just buried at the
/// bottom of a collapsed card. This surfaces it verbatim: the client never
/// invents advice, it only promotes what the analyst already wrote.
///
/// Returns nil when the narrative names no forward risk — no line beats a
/// generic placeholder.
nonisolated enum NarrativeOutlook {

    /// Heading fragments that mark the narrative's forward-looking section.
    private static let sectionMarkers = [
        "change the picture",
        "worth watching",
        "what to watch",
        "watch next",
        "outlook",
    ]

    /// First items that mean "nothing identified" — treated as no outlook.
    private static let emptyMarkers = [
        "none", "nothing", "no specific", "no identified", "no single",
        "no factor", "not applicable", "n/a",
    ]

    static func outlookLine(from narrative: String?) -> String? {
        guard let narrative, !narrative.isEmpty else { return nil }
        let lines = narrative.components(separatedBy: .newlines)

        guard let headingIndex = lines.firstIndex(where: isForwardHeading) else {
            return nil
        }

        for raw in lines.dropFirst(headingIndex + 1) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Next section started before any content — no outlook given.
            if isHeading(line) { return nil }
            let cleaned = stripMarkdown(line)
            if cleaned.isEmpty { continue }
            let lowered = cleaned.lowercased()
            if emptyMarkers.contains(where: { lowered.hasPrefix($0) }) { return nil }
            return compress(cleaned)
        }
        return nil
    }

    // MARK: - Line classification

    /// A heading whose text names the forward-looking section.
    private static func isForwardHeading(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard isHeading(line) else { return false }
        let text = stripMarkdown(line).lowercased()
        return sectionMarkers.contains { text.contains($0) }
    }

    /// Markdown heading (`## …`), fully-bold line (`**…**`), or a short
    /// label line ending in ":" — the shapes model-written section titles
    /// actually take. Bullets are content, never headings.
    private static func isHeading(_ line: String) -> Bool {
        if line.hasPrefix("#") { return true }
        if isBullet(line) { return false }
        let unterminated = line.hasSuffix(":") ? String(line.dropLast()) : line
        if unterminated.hasPrefix("**"), unterminated.hasSuffix("**"),
           unterminated.count > 4 {
            // Fully bold with no other prose after the closing marker.
            let inner = unterminated.dropFirst(2).dropLast(2)
            return !inner.contains("**")
        }
        // "What Would Change the Picture:" without any markdown at all.
        return line.hasSuffix(":") && line.count <= 60 && !line.contains(". ")
    }

    private static func isBullet(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return true
        }
        // "1. " / "2) " ordered list markers.
        if let first = line.first, first.isNumber {
            let prefix = line.prefix(4)
            return prefix.contains(". ") || prefix.contains(") ")
        }
        return false
    }

    // MARK: - Cleanup

    /// Strips list markers, bold/italic/code markers, and heading hashes.
    private static func stripMarkdown(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("#") { text.removeFirst() }
        for marker in ["- ", "* ", "• "] where text.hasPrefix(marker) {
            text.removeFirst(marker.count)
        }
        if let first = text.first, first.isNumber {
            for separator in [". ", ") "] {
                if let range = text.range(of: separator),
                   text.distance(from: text.startIndex, to: range.lowerBound) <= 2 {
                    text = String(text[range.upperBound...])
                    break
                }
            }
        }
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Collapses whitespace and caps the line at a caption-friendly length,
    /// preferring a sentence boundary over a mid-thought ellipsis.
    private static func compress(_ text: String, maxLength: Int = 180) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        let head = String(collapsed.prefix(maxLength))
        if let sentenceEnd = head.lastIndex(where: { $0 == "." || $0 == ";" }),
           head.distance(from: head.startIndex, to: sentenceEnd) > 60 {
            return String(head[...sentenceEnd])
        }
        if let lastSpace = head.lastIndex(of: " ") {
            return String(head[..<lastSpace]) + "…"
        }
        return head + "…"
    }
}
