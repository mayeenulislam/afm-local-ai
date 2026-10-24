import Foundation

/// Chat-friendly markdown post-processing, separated from AppState so the formatter is testable standalone.
enum ChatMarkdownFormatter {
    static func polish(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.contains("```") || trimmed.contains("#") || trimmed.contains("| ---") || trimmed.contains("> [!") {
            return trimmed
        }
        let codeSignals = ["func ", "struct ", "class ", "import ", "let ", "var ", "{", "};"]
        if trimmed.components(separatedBy: "\n").count > 2 && codeSignals.contains(where: { trimmed.contains($0) }) {
            return "```text\n\(trimmed)\n```"
        }
        if trimmed.first == "\"" && trimmed.last == "\"" {
            return "> \(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))"
        }
        return trimmed
    }

    static func nonBlankResponse(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "> [!ERROR]\n> **The model returned no response**\n\nThe on-device model produced no usable content. Ask again, or summarize the context if the conversation has grown long."
        }
        return trimmed
    }

    /// Returns a warning callout when the response ends as an incomplete table (a
    /// pipe-led header with no body rows). The on-device model can silently stop
    /// mid-table (Apple caps output at `maximumResponseTokens` without an error),
    /// so surface the truncation instead of showing a half table.
    static func truncatedTableCue(_ markdown: String) -> String {
        guard case .table(_, let rows)? = MarkdownBlockParser.parse(markdown).last, rows.isEmpty else { return "" }
        return "\n\n> [!WARNING]\n> **Table cut short**\n\nThe on-device model stopped while writing the table. Ask again to generate the full comparison."
    }

    static func chatFriendly(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: "\n")
        guard let first = lines.first, isHeadingLine(first) else { return trimmed }
        var body = Array(lines.dropFirst())
        while let head = body.first, head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body.removeFirst()
        }
        guard isSimpleChatBody(body) else { return trimmed }
        return body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isHeadingLine(_ line: String) -> Bool {
        guard let first = line.first, first == "#" else { return false }
        guard let next = line.dropFirst().first else { return true }
        return next == "#" || next == " "
    }

    private static func isSimpleChatBody(_ lines: [String]) -> Bool {
        var sawContent = false
        var sawBlank = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { if sawContent { sawBlank = true } }
            else if sawBlank { return false }
            else if t.hasPrefix("|") || t.hasPrefix(">") || t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("```") || isHeadingLine(t) { return false }
            else { sawContent = true }
        }
        return true
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unordered([String])
    case ordered([String])
    case quote(String)
    case callout(kind: String, text: String)
    case code(String)
    case footnote(label: String, content: String)
    case divider
    case table(header: [String], rows: [[String]])
}

enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                if !code.isEmpty {
                    result.append(.code(code.joined(separator: "\n")))
                }
                continue
            }

            if trimmed.range(of: "^#{1,6}($| )", options: .regularExpression) != nil {
                let level = min(max(trimmed.prefix(while: { $0 == "#" }).count, 1), 6)
                let content = trimmed.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
                result.append(.heading(level: level, text: content))
                index += 1
                continue
            }

            if trimmed.range(of: "^([-*_])\\1{2,}$", options: .regularExpression) != nil {
                result.append(.divider)
                index += 1
                continue
            }

            if trimmed.range(of: "^\\[\\^[^]]+\\]:", options: .regularExpression) != nil {
                let labelEnd = trimmed.firstIndex(of: "]")!
                let label = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<labelEnd])
                let after = trimmed[labelEnd...].dropFirst(2).trimmingCharacters(in: .whitespaces)
                var content = after.isEmpty ? [] : [after]
                index += 1
                while index < lines.count {
                    let raw = lines[index]
                    let stripped = raw.trimmingCharacters(in: .whitespaces)
                    if raw.hasPrefix("  ") || stripped.isEmpty {
                        if !stripped.isEmpty { content.append(stripped) }
                        index += 1
                    } else {
                        break
                    }
                }
                result.append(.footnote(label: label, content: content.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count {
                    let line = lines[index].trimmingCharacters(in: .whitespaces)
                    guard line.hasPrefix(">") else { break }
                    quote.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                if let alert = Self.alertMatch(in: quote) {
                    var content = quote.dropFirst(alert.markerIndex + 1).filter { !$0.isEmpty }
                    while index < lines.count {
                        let line = lines[index].trimmingCharacters(in: .whitespaces)
                        if line.isEmpty { index += 1; continue }
                        if isBlockStart(line) { break }
                        content.append(line)
                        index += 1
                    }
                    result.append(.callout(kind: alert.kind, text: content.joined(separator: "\n")))
                } else {
                    result.append(.quote(quote.joined(separator: "\n")))
                }
                continue
            }

            if let table = parseTable(lines: lines, index: &index) {
                result.append(.table(header: table.header, rows: table.rows))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while index < lines.count {
                    let line = lines[index].trimmingCharacters(in: .whitespaces)
                    guard line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") else { break }
                    items.append(String(line.dropFirst(2)))
                    index += 1
                }
                result.append(.unordered(items))
                continue
            }

            if trimmed.range(of: "^[0-9]+[\\.)] ", options: .regularExpression) != nil {
                var items: [String] = []
                while index < lines.count {
                    let line = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let range = line.range(of: "^[0-9]+[\\.)] ", options: .regularExpression) else { break }
                    items.append(String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                result.append(.ordered(items))
                continue
            }

            var paragraph: [String] = []
            while index < lines.count {
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                if line.isEmpty || isBlockStart(line) { break }
                paragraph.append(line)
                index += 1
            }
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: "\n")))
            }
        }

        return result
    }

    private static func isBlockStart(_ line: String) -> Bool {
        if line.hasPrefix("```") || line.hasPrefix("#") || line.hasPrefix(">")
            || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return true
        }
        if line.range(of: "^\\[\\^[^]]+\\]:", options: .regularExpression) != nil { return true }
        if line.range(of: "^([-*_])\\1{2,}$", options: .regularExpression) != nil { return true }
        if line.range(of: "^[0-9]+[\\.)] ", options: .regularExpression) != nil { return true }
        return false
    }

private static func parseTable(lines: [String], index: inout Int) -> (header: [String], rows: [[String]])? {
        guard index < lines.count else { return nil }
        let headerLine = lines[index].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|") else { return nil }

        let separatorLine = index + 1 < lines.count
            ? lines[index + 1].trimmingCharacters(in: .whitespaces)
            : ""
        guard Self.isSeparatorRow(separatorLine) else {
            // Table fragment from a truncated response (the on-device model can stop
            // mid-table): a pipe-led row-shaped line renders as a header-only table,
            // with any following pipe-led lines as body rows. Prose with an inner
            // "|" (no leading pipe) stays a paragraph.
            guard headerLine.hasPrefix("|"),
                  headerLine.dropFirst().trimmingCharacters(in: .whitespaces).contains("|") else { return nil }
            let header = Self.splitTableRow(headerLine)
            index += 1
            var rows: [[String]] = []
            while index < lines.count {
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, line.hasPrefix("|") else { break }
                rows.append(Self.splitTableRow(line))
                index += 1
            }
            return (header, rows)
        }

        let header = Self.splitTableRow(headerLine)
        index += 2

        var rows: [[String]] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.contains("|") else { break }
            rows.append(Self.splitTableRow(line))
            index += 1
        }
        return (header, rows)
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } && trimmed.contains("-")
        }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let inner = trimmed.hasPrefix("|") ? String(trimmed.dropFirst()) : trimmed
        let dropTrailing = inner.hasSuffix("|") ? String(inner.dropLast()) : inner
        return dropTrailing.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static let alertRegex = (try? NSRegularExpression(pattern: "^\\s*\\[!([A-Za-z]+)\\]\\s*$"))

    private static func alertMatch(in lines: [String]) -> (kind: String, markerIndex: Int)? {
        guard let alertRegex else { return nil }
        for (i, line) in lines.enumerated() where !line.isEmpty {
            let ns = line as NSString
            if let match = alertRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) {
                return (ns.substring(with: match.range(at: 1)).uppercased(), i)
            }
        }
        return nil
    }
}