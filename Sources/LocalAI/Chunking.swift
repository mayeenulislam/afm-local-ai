import CryptoKit
import Foundation

struct TextChunker: Sendable {
    var targetTokenCount = 450
    var maximumTokenCount = 600

    func chunks(for file: WorkspaceFile, workspace: Workspace, extraction: TextExtractionResult) -> [TextChunk] {
        let units = splitIntoUnits(extraction.text, kind: file.kind)
        var chunks: [TextChunk] = []
        var buffer: [TextUnit] = []
        var tokenCount = 0
        var ordinal = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            let content = buffer.map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                buffer.removeAll()
                tokenCount = 0
                return
            }

            let startLine = buffer.compactMap(\.startLine).min()
            let endLine = buffer.compactMap(\.endLine).max()
            let pageNumber = buffer.compactMap(\.pageNumber).first
            let slideNumber = buffer.compactMap(\.slideNumber).first
            chunks.append(
                TextChunk(
                    workspacePath: workspace.path,
                    filePath: file.relativePath,
                    fileKind: file.kind.rawValue,
                    title: inferTitle(from: content, fallback: file.name),
                    content: content,
                    ordinal: ordinal,
                    startLine: startLine,
                    endLine: endLine,
                    pageNumber: pageNumber,
                    slideNumber: slideNumber,
                    tokenEstimate: estimateTokens(content, kind: file.kind),
                    contentHash: hash(content)
                )
            )
            ordinal += 1
            buffer.removeAll()
            tokenCount = 0
        }

        for unit in units {
            let unitTokens = estimateTokens(unit.text, kind: file.kind)
            if !buffer.isEmpty {
                let pageChanged = unit.pageNumber != nil && unit.pageNumber != buffer.compactMap(\.pageNumber).first
                let slideChanged = unit.slideNumber != nil && unit.slideNumber != buffer.compactMap(\.slideNumber).first
                if pageChanged || slideChanged || tokenCount + unitTokens > targetTokenCount {
                    flush()
                }
            }

            if unitTokens > maximumTokenCount {
                for sliced in splitLargeUnit(unit, kind: file.kind) {
                    let slicedTokens = estimateTokens(sliced.text, kind: file.kind)
                    if !buffer.isEmpty, tokenCount + slicedTokens > targetTokenCount {
                        flush()
                    }
                    buffer.append(sliced)
                    tokenCount += slicedTokens
                }
            } else {
                buffer.append(unit)
                tokenCount += unitTokens
            }
        }

        flush()
        return chunks
    }

    private func splitIntoUnits(_ text: String, kind: WorkspaceFileKind) -> [TextUnit] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var units: [TextUnit] = []
        var buffer: [String] = []
        var startLine = 1
        var currentPage: Int?
        var currentSlide: Int?

        func flush(at endLine: Int) {
            let content = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                units.append(TextUnit(text: content, startLine: startLine, endLine: endLine, pageNumber: currentPage, slideNumber: currentSlide))
            }
            buffer.removeAll()
        }

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            if let page = pageMarker(line) {
                if !buffer.isEmpty {
                    flush(at: max(lineNumber - 1, startLine))
                }
                currentPage = page
                startLine = lineNumber + 1
                continue
            }
            if let slide = slideMarker(line) {
                if !buffer.isEmpty {
                    flush(at: max(lineNumber - 1, startLine))
                }
                currentSlide = slide
                startLine = lineNumber + 1
                continue
            }

            let startsBoundary = isBoundary(line, kind: kind)
            if startsBoundary, !buffer.isEmpty {
                flush(at: max(lineNumber - 1, startLine))
                startLine = lineNumber
            } else if buffer.isEmpty {
                startLine = lineNumber
            }

            buffer.append(line)

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               estimateTokens(buffer.joined(separator: "\n"), kind: kind) >= targetTokenCount / 2 {
                flush(at: lineNumber)
                startLine = lineNumber + 1
            }
        }

        if !buffer.isEmpty {
            flush(at: lines.count)
        }

        return units
    }

    private func isBoundary(_ line: String, kind: WorkspaceFileKind) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        if kind == .markdown {
            return trimmed.hasPrefix("#")
        }

        if kind == .code {
            return trimmed.hasPrefix("func ")
                || trimmed.hasPrefix("struct ")
                || trimmed.hasPrefix("class ")
                || trimmed.hasPrefix("enum ")
                || trimmed.hasPrefix("protocol ")
                || trimmed.hasPrefix("extension ")
                || trimmed.hasPrefix("import ")
        }

        return false
    }

    private func splitLargeUnit(_ unit: TextUnit, kind: WorkspaceFileKind) -> [TextUnit] {
        let maxChars = maxChunkCharacters(for: kind)
        let words = unit.text.split(separator: " ").map(String.init)
        guard words.count > 1 else {
            return splitByCharacter(unit, maxChars: maxChars)
        }

        var results: [TextUnit] = []
        var current: [String] = []
        var length = 0

        func flushSlice() {
            guard !current.isEmpty else { return }
            results.append(
                TextUnit(
                    text: current.joined(separator: " "),
                    startLine: unit.startLine,
                    endLine: unit.endLine,
                    pageNumber: unit.pageNumber,
                    slideNumber: unit.slideNumber
                )
            )
            current.removeAll()
            length = 0
        }

        for word in words {
            let added = word.count + (current.isEmpty ? 0 : 1)
            if !current.isEmpty, length + added > maxChars {
                flushSlice()
            }
            current.append(word)
            length += added
        }
        flushSlice()
        return results
    }

    private func splitByCharacter(_ unit: TextUnit, maxChars: Int) -> [TextUnit] {
        guard unit.text.count > maxChars else { return [unit] }
        var results: [TextUnit] = []
        var remaining = unit.text
        while remaining.count > maxChars {
            let slice = String(remaining.prefix(maxChars))
            results.append(
                TextUnit(text: slice, startLine: unit.startLine, endLine: unit.endLine, pageNumber: unit.pageNumber, slideNumber: unit.slideNumber)
            )
            remaining = String(remaining.dropFirst(maxChars))
        }
        if !remaining.isEmpty {
            results.append(
                TextUnit(text: remaining, startLine: unit.startLine, endLine: unit.endLine, pageNumber: unit.pageNumber, slideNumber: unit.slideNumber)
            )
        }
        return results
    }

    private func maxChunkCharacters(for kind: WorkspaceFileKind) -> Int {
        let charsPerToken = (kind == .code || kind == .data) ? 3.0 : 3.5
        return max(512, Int(Double(maximumTokenCount) * charsPerToken))
    }

    private func pageMarker(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[[page:"), trimmed.hasSuffix("]]") else {
            return nil
        }
        let number = trimmed
            .replacingOccurrences(of: "[[page:", with: "")
            .replacingOccurrences(of: "]]", with: "")
        return Int(number)
    }

    private func slideMarker(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[[slide:"), trimmed.hasSuffix("]]") else {
            return nil
        }
        let number = trimmed
            .replacingOccurrences(of: "[[slide:", with: "")
            .replacingOccurrences(of: "]]", with: "")
        return Int(number)
    }

    private func inferTitle(from content: String, fallback: String) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)

        guard let firstLine, firstLine.hasPrefix("#") else {
            return fallback
        }
        let title = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        guard !title.isEmpty, title.count < 90 else {
            return fallback
        }
        return title
    }

    func estimateTokens(_ text: String, kind: WorkspaceFileKind) -> Int {
        let charsPerToken = (kind == .code || kind == .data) ? 3.0 : 3.5
        return max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }

    private func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct TextUnit: Sendable {
    var text: String
    var startLine: Int
    var endLine: Int
    var pageNumber: Int?
    var slideNumber: Int?
}
