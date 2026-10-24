import Foundation

struct PlanOperationEntry: Decodable {
    var from: String
    var to: String
    var reason: String?
}

struct PlanOperationsBlock: Decodable {
    var operations: [PlanOperationEntry]
}

enum PlanOperationParser {
    static func extract(from markdown: String) -> (cleanMarkdown: String, operations: [PlanOperationEntry])? {
        let pattern = "```json\\s*\n([\\s\\S]*?)\n?```"
        let regex = (try? NSRegularExpression(pattern: pattern))

        if let regex {
            let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
            for match in matches {
                guard let blockRange = Range(match.range(at: 1), in: markdown) else { continue }
                let content = String(markdown[blockRange])
                if let decoded = decodeBlock(content) {
                    return (clean(removing: match.range, from: markdown), decoded)
                }
                if let object = balancedJSONObject(in: content),
                   let decoded = decodeBlock(object) {
                    return (clean(removing: match.range, from: markdown), decoded)
                }
            }
        }

        guard let open = markdown.range(of: "{\"operations\":"),
              let close = closingBrace(after: open.upperBound, in: markdown)
        else { return nil }
        let object = String(markdown[open.lowerBound...close])
        guard let decoded = decodeBlock(object) else { return nil }
        return (clean(removing: open.lowerBound, to: close, from: markdown), decoded)
    }

    private static func decodeBlock(_ content: String) -> [PlanOperationEntry]? {
        guard let block = try? JSONDecoder().decode(PlanOperationsBlock.self, from: Data(content.utf8)),
              !block.operations.isEmpty
        else { return nil }
        return block.operations
    }

    private static func clean(removing range: NSRange, from markdown: String) -> String {
        guard let fullRange = Range(range, in: markdown) else { return markdown }
        var clean = markdown
        clean.removeSubrange(fullRange)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clean(removing lower: String.Index, to upper: String.Index, from markdown: String) -> String {
        var clean = markdown
        clean.removeSubrange(lower...upper)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func balancedJSONObject(in text: String) -> String? {
        guard text.contains("{\"operations\":"),
              let open = text.range(of: "{\"operations\":"),
              let close = closingBrace(after: open.upperBound, in: text)
        else { return nil }
        return String(text[open.lowerBound...close])
    }

    private static func closingBrace(after start: String.Index, in text: String) -> String.Index? {
        var depth = 1
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                switch char {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return index }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func sourceIsInsideWorkspace(_ source: URL, root: URL) -> Bool {
        source.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
    }

    static func targetExists(_ source: URL, to: String, root: URL) -> Bool {
        guard let toURL = resolveDestination(to, in: root) else { return false }
        let targetFile = toURL.appendingPathComponent(source.lastPathComponent)
        return FileManager.default.fileExists(atPath: targetFile.path)
    }

    static func validate(operation: PlanOperationEntry, checkedPaths: Set<String>, directory: URL) -> String? {
        guard checkedPaths.contains(operation.from) else { return "not a checked file" }
        let sourceURL = directory.appendingPathComponent(operation.from)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return "source does not exist" }
        guard sourceIsInsideWorkspace(sourceURL, root: directory) else { return "source is outside the workspace" }
        guard resolveDestination(operation.to, in: directory) != nil else { return "destination outside the workspace" }
        if targetExists(sourceURL, to: operation.to, root: directory) { return "destination already exists" }
        return nil
    }

    static func resolveDestination(_ to: String, in directory: URL) -> URL? {
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty, !to.hasPrefix("/"), !to.contains("..") else { return nil }
        let root = directory.standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath()
        let fm = FileManager.default

        // Resolve the deepest existing ancestor, keeping the not-yet-created remainder.
        var candidate = directory.appendingPathComponent(to)
        var remainder: [String] = []
        while candidate.path != root.path, !fm.fileExists(atPath: candidate.path) {
            remainder.append(candidate.lastPathComponent)
            candidate.deleteLastPathComponent()
        }
        let resolvedBase = candidate.resolvingSymlinksInPath()

        // The component now living directly under the resolved base was walked up
        // as non-existent; if it is actually a dangling symlink, writes would go
        // through it to an unknown target — reject instead.
        if let boundary = remainder.last,
           (try? fm.destinationOfSymbolicLink(atPath: resolvedBase.appendingPathComponent(boundary).path)) != nil {
            return nil
        }

        let destination = remainder.reversed().reduce(resolvedBase) { url, component in
            url.appendingPathComponent(component)
        }
        guard destination.path == resolvedRoot.path || destination.path.hasPrefix(resolvedRoot.path + "/") else {
            return nil
        }
        return destination
    }
}