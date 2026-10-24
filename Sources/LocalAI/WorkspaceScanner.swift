import Foundation

/// The canonical per-extension classification tables. `classifyFile` and the
/// "file types" UI both read from here so the lists can't drift apart.
enum FileKindSuffixes {
    static let markdown = ["md", "markdown"]
    static let text = ["txt", "rtf"]
    static let code = ["swift", "py", "js", "jsx", "ts", "tsx", "html", "css", "json", "yaml", "yml", "toml", "rs", "go", "java", "kt", "c", "cpp", "h", "hpp", "m", "mm"]
    static let document = ["doc", "docx", "pages"]
    static let presentation = ["ppt", "pptx", "key"]
    static let pdf = ["pdf"]
    static let data = ["csv", "tsv", "sqlite", "sqlite3", "db", "parquet", "ndjson"]
    static let image = ["png", "jpg", "jpeg", "gif", "heic", "webp"]

    static var readable: [String] { markdown + text + code + pdf + document + presentation + data }
    static var unreadable: [String] { image }

    /// Supported file types grouped by kind, used by the classifier and the
    /// "Supported" table in Workspace info and Model Diagnostics.
    static var supportedTable: [(title: String, extensions: [String])] {
        [
            ("Markdown", markdown),
            ("Text", text),
            ("Code", code),
            ("PDF", pdf),
            ("Documents", document),
            ("Presentations", presentation),
            ("Data", data),
        ]
    }
}

struct WorkspaceScanner {
    func scan(url: URL) -> Workspace {
        let discovery = discoverFiles(in: url)
        let summary = summarize(discovery.files, ignoredItems: discovery.ignoredItems)
        return Workspace(
            url: url,
            kind: classify(root: url, files: discovery.files),
            files: discovery.files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending },
            summary: summary,
            scannedAt: Date()
        )
    }

    private func discoverFiles(in root: URL) -> (files: [WorkspaceFile], ignoredItems: Int) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ([], 0)
        }

        let ignoreRules = WorkspaceIgnoreRules(root: root)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        var results: [WorkspaceFile] = []
        var ignoredItems = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values?.isDirectory == true
            if ignoreRules.shouldSkip(url: fileURL, root: root, isDirectory: isDirectory) {
                ignoredItems += 1
                enumerator.skipDescendants()
                continue
            }

            if isDirectory {
                continue
            }

            let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            if !resolved.hasPrefix(resolvedRoot + "/") {
                ignoredItems += 1
                continue
            }

            let relativePath = ignoreRules.normalizedRelativePath(for: fileURL, root: root)
            let byteCount = Int64(values?.fileSize ?? 0)
            results.append(
                WorkspaceFile(
                    url: fileURL,
                    relativePath: relativePath,
                    kind: classifyFile(fileURL),
                    byteCount: byteCount
                )
            )
        }

        return (results, ignoredItems)
    }

    private func summarize(_ files: [WorkspaceFile], ignoredItems: Int) -> WorkspaceSummary {
        var summary = WorkspaceSummary()
        summary.totalFiles = files.count
        summary.totalBytes = files.reduce(0) { $0 + $1.byteCount }
        summary.ignoredItems = ignoredItems
        for file in files {
            summary.counts[file.kind, default: 0] += 1
        }
        return summary
    }

    private func classify(root: URL, files: [WorkspaceFile]) -> WorkspaceKind {
        var signals: Set<WorkspaceKind> = []
        let fileNames = Set(files.map(\.name))

        if FileManager.default.fileExists(atPath: root.appendingPathComponent(".obsidian").path) {
            return .obsidian
        }

        if fileNames.contains("Package.swift")
            || fileNames.contains("package.json")
            || fileNames.contains("pyproject.toml")
            || fileNames.contains("Cargo.toml")
            || fileNames.contains("go.mod")
            || files.contains(where: { $0.kind == .code }) {
            signals.insert(.code)
        }

        if files.contains(where: { [.pdf, .document, .presentation].contains($0.kind) }) {
            signals.insert(.research)
        }

        if files.contains(where: { $0.kind == .data }) {
            signals.insert(.data)
        }

        if signals.count > 1 { return .mixed }
        return signals.first ?? .general
    }

    private func classifyFile(_ url: URL) -> WorkspaceFileKind {
        switch url.pathExtension.lowercased() {
        case let ext where FileKindSuffixes.markdown.contains(ext): .markdown
        case let ext where FileKindSuffixes.text.contains(ext): .text
        case let ext where FileKindSuffixes.code.contains(ext): .code
        case let ext where FileKindSuffixes.document.contains(ext): .document
        case let ext where FileKindSuffixes.presentation.contains(ext): .presentation
        case let ext where FileKindSuffixes.pdf.contains(ext): .pdf
        case let ext where FileKindSuffixes.data.contains(ext): .data
        case let ext where FileKindSuffixes.image.contains(ext): .image
        default: .other
        }
    }
}
