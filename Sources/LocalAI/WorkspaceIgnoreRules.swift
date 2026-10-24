import Foundation

struct WorkspaceIgnoreRules {
    private let defaultIgnoredNames: Set<String> = [
        ".git", ".DS_Store", "node_modules", ".build", "DerivedData",
        ".swiftpm", ".venv", "__pycache__", ".cache", "build", "dist"
    ]
    private let patterns: [IgnorePattern]

    init(root: URL) {
        patterns = Self.loadGitignorePatterns(root: root)
    }

    func shouldSkip(url: URL, root: URL, isDirectory: Bool) -> Bool {
        let name = url.lastPathComponent
        if defaultIgnoredNames.contains(name) {
            return true
        }

        let relativePath = normalizedRelativePath(for: url, root: root)
        guard !relativePath.isEmpty else {
            return false
        }

        var ignored = false
        for pattern in patterns where pattern.matches(relativePath: relativePath, isDirectory: isDirectory) {
            ignored = !pattern.isNegated
        }
        return ignored
    }

    func normalizedRelativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }

        let start = path.index(path.startIndex, offsetBy: rootPath.count)
        return path[start...]
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "\\", with: "/")
    }

    private static func loadGitignorePatterns(root: URL) -> [IgnorePattern] {
        let url = root.appendingPathComponent(".gitignore")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { IgnorePattern(rawLine: String($0)) }
    }
}

private struct IgnorePattern {
    var pattern: String
    var isNegated: Bool
    var directoryOnly: Bool
    var anchored: Bool
    private let regex: NSRegularExpression?

    init?(rawLine: String) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else {
            return nil
        }

        let isNegated = line.hasPrefix("!")
        if isNegated {
            line.removeFirst()
        }

        let directoryOnly = line.hasSuffix("/")
        if directoryOnly {
            line.removeLast()
        }

        let anchored = line.hasPrefix("/")
        if anchored {
            line.removeFirst()
        }

        guard !line.isEmpty else {
            return nil
        }

        self.pattern = line
        self.isNegated = isNegated
        self.directoryOnly = directoryOnly
        self.anchored = anchored
        self.regex = Self.compileWildcard(line)
    }

    private static func compileWildcard(_ pattern: String) -> NSRegularExpression? {
        var regex = "^"
        for character in pattern {
            switch character {
            case "*":
                regex += "[^/]*"
            case "?":
                regex += "[^/]"
            case ".":
                regex += "\\."
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return try? NSRegularExpression(pattern: regex)
    }

    func matches(relativePath: String, isDirectory: Bool) -> Bool {
        guard !directoryOnly || isDirectory else {
            return false
        }
        guard let regex else { return false }

        let path = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if anchored || pattern.contains("/") {
            return regex.firstMatch(in: path, options: [], range: NSRange(path.startIndex..., in: path)) != nil
        }

        return path
            .split(separator: "/")
            .contains { component in
                let value = String(component)
                return regex.firstMatch(in: value, options: [], range: NSRange(value.startIndex..., in: value)) != nil
            }
    }
}

