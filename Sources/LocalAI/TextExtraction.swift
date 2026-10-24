import Foundation
import PDFKit

struct TextExtractionResult: Sendable {
    var text: String
    var lineCount: Int
}

enum TextExtractionError: Error, Sendable {
    case unsupportedType
    case tooLarge
    case unreadable
}

extension WorkspaceFileKind {
    var canEnterContext: Bool {
        TextExtractor().supports(self)
    }

    /// The labeled supported-extension line for the Workspace info and Model
    /// Diagnostics UI: "Supported: *.md, *.markdown, ...".
    static var supportedSummary: (title: String, detail: String) {
        ("Supported", FileKindSuffixes.readable.map { "*.\($0)" }.joined(separator: ", "))
    }
}

struct TextExtractor: Sendable {
    var maxBytes = 1_500_000
    var maxSQLiteBytes: Int64 = 50_000_000
    var maxPDFBytes: Int64 = 100_000_000
    var maxExtractedCharacters = 2_000_000
    let ooxmlExtractor = OOXMLTextExtractor()
    let sqliteExtractor = SQLiteDataExtractor()

    func extract(from file: WorkspaceFile) throws -> TextExtractionResult {
        guard supports(file.kind) else {
            throw TextExtractionError.unsupportedType
        }

        guard file.kind == .pdf
            || isSQLiteDatabase(file)
            || file.byteCount <= maxBytes else {
            throw TextExtractionError.tooLarge
        }

        if file.kind == .pdf, file.byteCount > maxPDFBytes {
            throw TextExtractionError.tooLarge
        }

        if isSQLiteDatabase(file), file.byteCount > maxSQLiteBytes {
            throw TextExtractionError.tooLarge
        }

        let extractedText: String?
        if file.kind == .pdf {
            extractedText = readPDFText(from: file.url)
        } else if isSQLiteDatabase(file) {
            extractedText = try sqliteExtractor.extractDatabaseSummary(from: file.url)
        } else if file.kind == .document && file.url.pathExtension.lowercased() == "docx" {
            extractedText = try ooxmlExtractor.extractDOCXText(from: file.url)
        } else if file.kind == .presentation && file.url.pathExtension.lowercased() == "pptx" {
            extractedText = try ooxmlExtractor.extractPPTXText(from: file.url)
        } else {
            extractedText = try readText(from: file.url)
        }

        guard let text = extractedText else {
            throw TextExtractionError.unreadable
        }

        let normalized = normalize(text)
        return TextExtractionResult(
            text: normalized,
            lineCount: normalized.split(separator: "\n", omittingEmptySubsequences: false).count
        )
    }

    func supports(_ kind: WorkspaceFileKind) -> Bool {
        switch kind {
        case .markdown, .text, .code, .data, .pdf, .document, .presentation:
            true
        case .image, .folder, .other:
            false
        }
    }

    private func readText(from url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let ascii = String(data: data, encoding: .ascii) {
            return ascii
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return nil
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readPDFText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else {
            return nil
        }

        var pages: [String] = []
        var characters = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                continue
            }

            characters += text.count
            guard characters <= maxExtractedCharacters else {
                pages.append("[…][PDF text truncated at \(maxExtractedCharacters) characters.]")
                break
            }
            pages.append("[[page:\(index + 1)]]\n\(text)")
        }

        return pages.isEmpty ? nil : pages.joined(separator: "\n\n")
    }

    private func isSQLiteDatabase(_ file: WorkspaceFile) -> Bool {
        guard file.kind == .data else { return false }
        switch file.url.pathExtension.lowercased() {
        case "sqlite", "sqlite3", "db":
            return true
        default:
            return false
        }
    }
}
