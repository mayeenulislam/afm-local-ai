import XCTest
@testable import LocalAI

final class TextChunkerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextChunkerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFile(relativePath: String, kind: WorkspaceFileKind = .text) -> WorkspaceFile {
        WorkspaceFile(
            url: tempDir.appendingPathComponent(relativePath),
            relativePath: relativePath,
            kind: kind,
            byteCount: 0
        )
    }

    private func makeWorkspace() -> Workspace {
        Workspace(
            url: tempDir,
            kind: .general,
            files: [],
            summary: WorkspaceSummary(),
            scannedAt: Date()
        )
    }

    // MARK: - Basic chunking

    func testEmptyTextProducesNoChunks() {
        let file = makeFile(relativePath: "empty.txt")
        let extraction = TextExtractionResult(text: "", lineCount: 0)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertTrue(chunks.isEmpty)
    }

    func testWhitespaceOnlyTextProducesNoChunks() {
        let file = makeFile(relativePath: "ws.txt")
        let extraction = TextExtractionResult(text: "   \n\n  \t  \n", lineCount: 3)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertTrue(chunks.isEmpty)
    }

    func testShortTextProducesSingleChunk() {
        let file = makeFile(relativePath: "short.txt")
        let extraction = TextExtractionResult(text: "Short content here.", lineCount: 1)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].content, "Short content here.")
        XCTAssertEqual(chunks[0].ordinal, 0)
        XCTAssertNotNil(chunks[0].contentHash)
    }

    func testChunkContentHashIsSHA256() {
        let file = makeFile(relativePath: "hash.txt")
        let extraction = TextExtractionResult(text: "test content", lineCount: 1)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].contentHash.count, 64)
    }

    // MARK: - Token estimation

    func testTokenEstimationForText() {
        let file = makeFile(relativePath: "tokens.txt")
        let text = String(repeating: "a", count: 100)
        let extraction = TextExtractionResult(text: text, lineCount: 1)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].tokenEstimate, 29)
    }

    func testTokenEstimationForCode() {
        let file = makeFile(relativePath: "code.swift", kind: .code)
        let text = String(repeating: "a", count: 96)
        let extraction = TextExtractionResult(text: text, lineCount: 1)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].tokenEstimate, 32)
    }

    func testTokenEstimationMinimumOne() {
        let file = makeFile(relativePath: "tiny.txt")
        let extraction = TextExtractionResult(text: "a", lineCount: 1)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertEqual(chunks[0].tokenEstimate, 1)
    }

    // MARK: - Large unit splitting

    func testLargeUnitGetsSplit() {
        let file = makeFile(relativePath: "large.swift", kind: .code)
        let text = String(repeating: "a", count: 700 * 4)
        let extraction = TextExtractionResult(text: text, lineCount: 700)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertGreaterThan(chunks.count, 1)
    }

    // MARK: - Page markers

    func testPageMarkerCreatesSeparateChunks() {
        let file = makeFile(relativePath: "doc.pdf", kind: .pdf)
        let text = "[[page:1]]\nFirst page content.\n[[page:2]]\nSecond page content."
        let extraction = TextExtractionResult(text: text, lineCount: 4)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        let page1 = chunks.first { $0.pageNumber == 1 }
        let page2 = chunks.first { $0.pageNumber == 2 }
        XCTAssertNotNil(page1)
        XCTAssertNotNil(page2)
    }

    // MARK: - Slide markers

    func testSlideMarkerCreatesSeparateChunks() {
        let file = makeFile(relativePath: "slides.pptx", kind: .presentation)
        let text = "[[slide:1]]\nSlide one.\n[[slide:2]]\nSlide two."
        let extraction = TextExtractionResult(text: text, lineCount: 4)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        let slide1 = chunks.first { $0.slideNumber == 1 }
        let slide2 = chunks.first { $0.slideNumber == 2 }
        XCTAssertNotNil(slide1)
        XCTAssertNotNil(slide2)
    }

    // MARK: - Markdown boundaries

    func testMarkdownHeadingBoundary() {
        let file = makeFile(relativePath: "doc.md", kind: .markdown)
        let text = "# Section 1\nContent for section 1.\n\n# Section 2\nContent for section 2."
        let extraction = TextExtractionResult(text: text, lineCount: 6)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        let section1 = chunks.first { $0.content.contains("Section 1") }
        let section2 = chunks.first { $0.content.contains("Section 2") }
        XCTAssertNotNil(section1)
        XCTAssertNotNil(section2)
    }

    // MARK: - Code boundaries

    func testCodeFunctionBoundary() {
        let file = makeFile(relativePath: "code.swift", kind: .code)
        let body = Array(repeating: "        let value = compute(input) // padded line", count: 8).joined(separator: "\n")
        let text = (1...6).map {
            "import Foundation\n\nfunc function\($0)() { // body \($0)\n\(body)\n}"
        }.joined(separator: "\n\n")
        let extraction = TextExtractionResult(text: text, lineCount: 12 * 6)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
    }

    // MARK: - Title inference

    func testTitleInferredFromFirstLine() {
        let file = makeFile(relativePath: "doc.md", kind: .markdown)
        let text = "# My Title\n\nSome body content."
        let extraction = TextExtractionResult(text: text, lineCount: 3)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].title, "My Title")
    }

    func testTitleFallsBackWhenFirstLineTooLong() {
        let file = makeFile(relativePath: "longtitle.md")
        let longLine = String(repeating: "a", count: 100)
        let text = "# \(longLine)\n\nBody."
        let extraction = TextExtractionResult(text: text, lineCount: 3)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].title, "longtitle.md")
    }

    func testTitleFallsBackForNoHeading() {
        let file = makeFile(relativePath: "plain.txt")
        let extraction = TextExtractionResult(text: "No heading here, just text.", lineCount: 1)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        XCTAssertEqual(chunks[0].title, "plain.txt")
    }

    // MARK: - Line tracking

    func testChunkStartAndEndLinesTracked() {
        let file = makeFile(relativePath: "lines.txt")
        let paragraph = Array(repeating: "This line of content is padded with words so the paragraph crosses the token target.", count: 20).joined(separator: "\n")
        let text = Array(repeating: paragraph, count: 5).joined(separator: "\n\n")
        let extraction = TextExtractionResult(text: text, lineCount: 100)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        for chunk in chunks {
            XCTAssertNotNil(chunk.startLine)
            XCTAssertNotNil(chunk.endLine)
        }
    }

    func testChunkOrdinalIncrementing() {
        let file = makeFile(relativePath: "ordinals.txt")
        let text = String(repeating: "word ", count: 500)
        let extraction = TextExtractionResult(text: text, lineCount: 1)
        let chunker = TextChunker(targetTokenCount: 50, maximumTokenCount: 600)
        let chunks = chunker.chunks(for: file, workspace: makeWorkspace(), extraction: extraction)
        XCTAssertEqual(chunks.count, chunks.indices.map { $0 }.count)

        for (index, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.ordinal, index)
        }
    }

    // MARK: - Workspace path metadata

    func testChunkStoresWorkspacePath() {
        let workspace = makeWorkspace()
        let file = makeFile(relativePath: "test.txt")
        let extraction = TextExtractionResult(text: "content", lineCount: 1)
        let chunker = TextChunker()
        let chunks = chunker.chunks(for: file, workspace: workspace, extraction: extraction)

        XCTAssertEqual(chunks[0].workspacePath, workspace.path)
        XCTAssertEqual(chunks[0].filePath, "test.txt")
        XCTAssertEqual(chunks[0].fileKind, "Text")
    }
}
