import Foundation
import zlib

/// Thread-safe accumulator for subprocess stdout streamed via `readabilityHandler`.
private final class OutputBuffer: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var storage: Data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard storage.count < limit else { return }
        let remaining = limit - storage.count
        storage.append(data.prefix(remaining))
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct OOXMLTextExtractor: Sendable {
    /// Hard ceiling on `textutil` output; the source document is already capped
    /// upstream, but a crafted archive can expand several-fold on conversion.
    static let maxTextUtilOutputBytes = 8_000_000

    /// Total decompressed bytes allowed across all PPTX slide/notes entries, so a
    /// crafted archive with many expandable entries can't exhaust memory even if
    /// each entry individually stays under the per-entry cap.
    static let maxTotalDecompressedBytes = 100_000_000

    /// Ceiling on accumulated presentation text; extracting stops at this many chars.
    static let maxPresentationTextCharacters = 2_000_000

    func extractDOCXText(from url: URL) throws -> String? {
        try readViaTextUtil(url)
    }

    func extractPPTXText(from url: URL) throws -> String? {
        var archive = try ZipArchive(data: Data(contentsOf: url))
        let slidePaths = numberedPaths(
            archive.entries.keys.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") },
            prefix: "ppt/slides/slide",
            suffix: ".xml"
        )
        let notesPaths = Dictionary(
            uniqueKeysWithValues: numberedPaths(
                archive.entries.keys.filter { $0.hasPrefix("ppt/notesSlides/notesSlide") && $0.hasSuffix(".xml") },
                prefix: "ppt/notesSlides/notesSlide",
                suffix: ".xml"
            ).map { ($0.number, $0.path) }
        )

        var sections: [String] = []
        var textCharacters = 0
        for slide in slidePaths {
            var lines: [String] = []

            if let data = try archive.data(for: slide.path),
               let xml = String(data: data, encoding: .utf8) {
                let slideText = normalizePresentationML(xml)
                if !slideText.isEmpty {
                    lines.append(slideText)
                }
            }

            if let notesPath = notesPaths[slide.number],
               let notesData = try archive.data(for: notesPath),
               let notesXML = String(data: notesData, encoding: .utf8) {
                let notesText = normalizePresentationML(notesXML)
                if !notesText.isEmpty {
                    lines.append("Speaker notes:\n\(notesText)")
                }
            }

            if !lines.isEmpty {
                let section = "[[slide:\(slide.number)]]\n\(lines.joined(separator: "\n"))"
                textCharacters += section.count
                guard textCharacters <= Self.maxPresentationTextCharacters else {
                    sections.append("[…][Presentation text truncated at \(Self.maxPresentationTextCharacters) characters.]")
                    break
                }
                sections.append(section)
            }
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func readViaTextUtil(_ url: URL) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        // Use `--` to separate options from the file path, preventing a filename
        // starting with `-` (e.g., `-output.docx`) from being parsed as an option.
        process.arguments = ["-convert", "txt", "-stdout", "--", url.path]
        process.standardError = FileHandle.nullDevice
        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        // Drain the pipe as the child writes so a large document can't deadlock
        // on a full pipe buffer while the parent waits for exit.
        let buffer = OutputBuffer(limit: Self.maxTextUtilOutputBytes)
        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            buffer.append(chunk)
        }

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            throw error
        }
        // Hard cap so a corrupt/adversarial document can't hang extraction forever.
        if done.wait(timeout: .now() + 30) == .timedOut {
            outputHandle.readabilityHandler = nil
            process.terminate()
            _ = done.wait(timeout: .now() + 1)
        }
        outputHandle.readabilityHandler = nil
        let data = buffer.data
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private func normalizePresentationML(_ xml: String) -> String {
        var extracted: [String] = []
        let pattern = #"<a:t[^>]*>(.*?)</a:t>"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                guard match.numberOfRanges == 2,
                      let range = Range(match.range(at: 1), in: xml) else {
                    continue
                }
                let text = decodeXMLEntities(String(xml[range]))
                    .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    extracted.append(text)
                }
            }
        }

        if extracted.isEmpty {
            return normalizeGenericXML(xml)
        }
        return extracted.joined(separator: "\n")
    }

    private func normalizeGenericXML(_ xml: String) -> String {
        let text = xml
            .replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression)
        return decodeXMLEntities(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line
                    .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func numberedPaths(_ paths: [String], prefix: String, suffix: String) -> [(number: Int, path: String)] {
        paths.compactMap { path in
            guard path.hasPrefix(prefix), path.hasSuffix(suffix) else {
                return nil
            }
            let numberText = path
                .dropFirst(prefix.count)
                .dropLast(suffix.count)
            guard let number = Int(numberText) else {
                return nil
            }
            return (number, path)
        }
        .sorted { $0.number < $1.number }
    }

    private func decodeXMLEntities(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")

        decoded = decodeNumericEntities(in: decoded, pattern: #"&#(\d+);"#, radix: 10)
        decoded = decodeNumericEntities(in: decoded, pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
        return decoded
    }

    private func decodeNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            guard match.numberOfRanges == 2,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let numberRange = Range(match.range(at: 1), in: result),
                  let scalarValue = UInt32(result[numberRange], radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}

private struct ZipArchive {
    // Decompression cap guards against zip bombs: a small archive declaring a huge
    // uncompressed size must fail instead of exhausting memory.
    private static let maxUncompressedSize = 100_000_000

    let data: Data
    let entries: [String: ZipEntry]
    private var decompressedTotal = 0

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readEntries(from: data)
    }

    mutating func data(for path: String) throws -> Data? {
        guard let entry = entries[path] else {
            return nil
        }

        guard try data.uint32(at: entry.localHeaderOffset) == 0x0403_4b50 else {
            throw ZipArchiveError.invalidLocalHeader
        }

        let fileNameLength = try Int(data.uint16(at: entry.localHeaderOffset + 26))
        let extraLength = try Int(data.uint16(at: entry.localHeaderOffset + 28))
        let payloadOffset = entry.localHeaderOffset + 30 + fileNameLength + extraLength
        let payloadRange = try data.range(from: payloadOffset, length: entry.compressedSize)
        let remainingBudget = OOXMLTextExtractor.maxTotalDecompressedBytes - decompressedTotal

        // Pre-check: declared size (capped at per-entry max) must fit in remaining budget.
        // This prevents a malicious entry declaring 0 but expanding to 100MB from
        // bypassing the budget check.
        let declaredSize = min(entry.uncompressedSize, Self.maxUncompressedSize)
        guard declaredSize <= remainingBudget else {
            throw ZipArchiveError.decompressionLimitExceeded
        }

        let payload = data.subdata(in: payloadRange)
        let decompressed: Data
        switch entry.compressionMethod {
        case 0:
            decompressed = payload
        case 8:
            decompressed = try inflateRawDeflate(payload, maxBytes: remainingBudget)
        default:
            throw ZipArchiveError.unsupportedCompression(entry.compressionMethod)
        }
        guard decompressed.count <= remainingBudget else {
            throw ZipArchiveError.decompressionLimitExceeded
        }
        decompressedTotal += decompressed.count
        return decompressed
    }

    private static func readEntries(from data: Data) throws -> [String: ZipEntry] {
        let eocdOffset = try findEndOfCentralDirectory(in: data)
        let centralDirectoryOffset = try Int(data.uint32(at: eocdOffset + 16))
        let centralDirectorySize = try Int(data.uint32(at: eocdOffset + 12))
        let centralDirectoryEnd = centralDirectoryOffset + centralDirectorySize
        guard centralDirectoryEnd <= data.count else {
            throw ZipArchiveError.truncatedData
        }

        var entries: [String: ZipEntry] = [:]
        var offset = centralDirectoryOffset
        while offset < centralDirectoryEnd {
            guard try data.uint32(at: offset) == 0x0201_4b50 else {
                throw ZipArchiveError.invalidCentralDirectory
            }

            let method = try data.uint16(at: offset + 10)
            let compressedSize = try Int(data.uint32(at: offset + 20))
            let uncompressedSize = try Int(data.uint32(at: offset + 24))
            let fileNameLength = try Int(data.uint16(at: offset + 28))
            let extraLength = try Int(data.uint16(at: offset + 30))
            let commentLength = try Int(data.uint16(at: offset + 32))
            let localHeaderOffset = try Int(data.uint32(at: offset + 42))
            let nameRange = try data.range(from: offset + 46, length: fileNameLength)
            guard let name = String(data: data.subdata(in: nameRange), encoding: .utf8) else {
                throw ZipArchiveError.invalidCentralDirectory
            }

            entries[name] = ZipEntry(
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            )
            offset = nameRange.upperBound + extraLength + commentLength
        }
        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw ZipArchiveError.missingEndOfCentralDirectory
        }

        let searchStart = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= searchStart {
            if try data.uint32(at: offset) == 0x0605_4b50 {
                return offset
            }
            offset -= 1
        }
        throw ZipArchiveError.missingEndOfCentralDirectory
    }

    private func inflateRawDeflate(_ compressed: Data, maxBytes: Int) throws -> Data {
        guard maxBytes >= 0 else {
            throw ZipArchiveError.decompressionLimitExceeded
        }
        // Reserve only a modest amount up front; the per-chunk guard on output
        // count enforces the real cap, and a malicious huge declared size must
        // not trigger a huge allocation before it is ever checked.
        let reserve = min(max(maxBytes, 4096), 1_000_000)
        var stream = z_stream()
        let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else {
            throw ZipArchiveError.decompressionFailed(initResult)
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(reserve)
        let chunkSize = 16_384

        return try compressed.withUnsafeBytes { compressedBuffer in
            guard let compressedBase = compressedBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Data()
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: compressedBase)
            stream.avail_in = uInt(compressed.count)

            var buffer = [UInt8](repeating: 0, count: chunkSize)
            var status: Int32 = Z_OK
            repeat {
                status = buffer.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(outputBuffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                guard status == Z_OK || status == Z_STREAM_END else {
                    throw ZipArchiveError.decompressionFailed(status)
                }

                let produced = buffer.count - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                    guard output.count <= maxBytes else {
                        throw ZipArchiveError.decompressionLimitExceeded
                    }
                }
            } while status != Z_STREAM_END

            return output
        }
    }
}

private struct ZipEntry {
    var compressionMethod: UInt16
    var compressedSize: Int
    var uncompressedSize: Int
    var localHeaderOffset: Int
}

private enum ZipArchiveError: LocalizedError {
    case missingEndOfCentralDirectory
    case invalidCentralDirectory
    case invalidLocalHeader
    case truncatedData
    case unsupportedCompression(UInt16)
    case decompressionFailed(Int32)
    case decompressionLimitExceeded

    var errorDescription: String? {
        switch self {
        case .missingEndOfCentralDirectory:
            "PPTX archive is missing its ZIP directory."
        case .invalidCentralDirectory:
            "PPTX archive directory is invalid."
        case .invalidLocalHeader:
            "PPTX archive entry header is invalid."
        case .truncatedData:
            "PPTX archive data is truncated."
        case .unsupportedCompression(let method):
            "PPTX archive uses unsupported compression method \(method)."
        case .decompressionFailed(let code):
            "PPTX decompression failed with zlib code \(code)."
        case .decompressionLimitExceeded:
            "PPTX decompression exceeded the 100 MB safety limit."
        }
    }
}

private extension Data {
    func range(from offset: Int, length: Int) throws -> Range<Data.Index> {
        guard offset >= 0, length >= 0, offset + length <= count else {
            throw ZipArchiveError.truncatedData
        }
        return offset..<(offset + length)
    }

    func uint16(at offset: Int) throws -> UInt16 {
        let range = try range(from: offset, length: 2)
        let bytes = self[range]
        return UInt16(bytes[range.lowerBound]) | (UInt16(bytes[range.lowerBound + 1]) << 8)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        let range = try range(from: offset, length: 4)
        let bytes = self[range]
        let base = range.lowerBound
        return UInt32(bytes[base])
            | (UInt32(bytes[base + 1]) << 8)
            | (UInt32(bytes[base + 2]) << 16)
            | (UInt32(bytes[base + 3]) << 24)
    }
}