import Foundation

struct ObsidianMetadataParser: Sendable {
    func parse(_ text: String) -> ObsidianMetadata {
        let frontmatterResult = parseFrontmatter(from: text)
        let body = frontmatterResult.bodyText
        let frontmatter = frontmatterResult.frontmatter
        let frontmatterTags = values(from: frontmatter["tags"])
        let aliases = values(from: frontmatter["aliases"]) + values(from: frontmatter["alias"])
        let inlineTags = parseInlineTags(from: body)
        let wikilinks = parseWikilinks(from: body)

        return ObsidianMetadata(
            frontmatter: frontmatter,
            tags: normalizedUnique(frontmatterTags + inlineTags),
            wikilinks: normalizedUnique(wikilinks),
            aliases: normalizedUnique(aliases),
            bodyText: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func parseFrontmatter(from text: String) -> (frontmatter: [String: String], bodyText: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], text)
        }

        var fields: [String: String] = [:]
        var endIndex: Int?
        var index = 1
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = index
                break
            }

            if let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !value.isEmpty {
                    fields[key] = value
                } else if !key.isEmpty {
                    let listResult = parseIndentedList(lines: lines, startingAt: index + 1)
                    if !listResult.values.isEmpty {
                        fields[key] = listResult.values.joined(separator: ", ")
                        index = listResult.endIndex - 1
                    }
                }
            }
            index += 1
        }

        guard let endIndex else {
            return ([:], text)
        }

        let bodyStart = min(endIndex + 1, lines.count)
        if fields.isEmpty {
            let junk = lines[1..<endIndex].joined(separator: "\n")
            let body = lines.dropFirst(bodyStart).joined(separator: "\n")
            let combined = [junk, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return ([:], combined)
        }
        let body = lines.dropFirst(bodyStart).joined(separator: "\n")
        return (fields, body)
    }

    private func parseIndentedList(lines: [String], startingAt startIndex: Int) -> (values: [String], endIndex: Int) {
        var values: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" || trimmed.contains(":") && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                break
            }
            if trimmed.hasPrefix("- ") {
                let value = String(trimmed.dropFirst(2))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]#").union(.whitespacesAndNewlines))
                if !value.isEmpty {
                    values.append(value)
                }
            }
            index += 1
        }

        return (values, index)
    }

    private func values(from rawValue: String?) -> [String] {
        guard let rawValue, !rawValue.isEmpty else { return [] }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBrackets: String
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            withoutBrackets = String(trimmed.dropFirst().dropLast())
        } else {
            withoutBrackets = trimmed
        }

        return withoutBrackets
            .split { character in
                character == "," || character == " "
            }
            .map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]#").union(.whitespacesAndNewlines))
            }
            .filter { !$0.isEmpty }
    }

    private func parseInlineTags(from text: String) -> [String] {
        let pattern = #"(^|[\s\[\{\(])#([A-Za-z0-9_/-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let tagRange = Range(match.range(at: 2), in: text) else {
                return nil
            }
            let tag = String(text[tagRange])
            return tag.contains(where: \.isLetter) ? tag : nil
        }
    }

    private func parseWikilinks(from text: String) -> [String] {
        let pattern = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let linkRange = Range(match.range(at: 1), in: text) else {
                return nil
            }

            var target = String(text[linkRange])
            if let pipe = target.firstIndex(of: "|") {
                target = String(target[..<pipe])
            }
            if let heading = target.firstIndex(of: "#") {
                target = String(target[..<heading])
            }
            if let block = target.firstIndex(of: "^") {
                target = String(target[..<block])
            }
            return target.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func normalizedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            if seen.insert(key).inserted {
                results.append(normalized)
            }
        }
        return results.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct ObsidianIndexAccumulator: Sendable {
    private(set) var noteCount = 0
    private var frontmatterFields: Set<String> = []
    private var tagCounts: [String: Int] = [:]
    private var wikilinks: Set<String> = []
    private var wikilinkTotal = 0

    mutating func record(_ metadata: ObsidianMetadata) {
        noteCount += 1
        frontmatterFields.formUnion(metadata.frontmatter.keys)
        for tag in metadata.tags {
            tagCounts[tag, default: 0] += 1
        }
        for wikilink in metadata.wikilinks {
            wikilinks.insert(wikilink)
            wikilinkTotal += 1
        }
    }

    var summary: ObsidianIndexSummary? {
        guard noteCount > 0 else { return nil }
        let uniqueTags = tagCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let topTags = tagCounts
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedStandardCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(5)
            .map { "#\($0.key)" }

        return ObsidianIndexSummary(
            noteCount: noteCount,
            frontmatterFieldCount: frontmatterFields.count,
            uniqueTags: uniqueTags,
            wikilinkCount: wikilinkTotal,
            uniqueWikilinks: wikilinks.count,
            topTags: Array(topTags)
        )
    }
}
