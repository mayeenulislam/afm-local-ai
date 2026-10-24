import XCTest
@testable import LocalAI

final class ChunkIndexStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChunkIndexTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeSampleChunks() -> [TextChunk] {
        [
            TextChunk(
                workspacePath: tempDir.path,
                filePath: "README.md",
                fileKind: "Markdown",
                title: "Readme",
                content: "This is a sample readme file about the project.",
                ordinal: 0,
                startLine: 1,
                endLine: 2,
                pageNumber: nil,
                slideNumber: nil,
                tokenEstimate: 15,
                contentHash: "hash1"
            ),
            TextChunk(
                workspacePath: tempDir.path,
                filePath: "main.swift",
                fileKind: "Code",
                title: "Main",
                content: "import Foundation\n\nfunc main() {\n    print(\"hello\")\n}",
                ordinal: 0,
                startLine: 1,
                endLine: 4,
                pageNumber: nil,
                slideNumber: nil,
                tokenEstimate: 20,
                contentHash: "hash2"
            ),
            TextChunk(
                workspacePath: tempDir.path,
                filePath: "docs/guide.md",
                fileKind: "Markdown",
                title: "Guide",
                content: "A guide to using the application effectively.",
                ordinal: 0,
                startLine: 1,
                endLine: 1,
                pageNumber: nil,
                slideNumber: nil,
                tokenEstimate: 12,
                contentHash: "hash3"
            )
        ]
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

    // MARK: - Save and Load round-trip

    func testSaveAndLoadRoundTrip() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()

        let urls = try store.save(chunks: chunks, for: workspace)

        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.sqliteURL.path))

        let loaded = try store.load(for: workspace)
        XCTAssertEqual(loaded.count, chunks.count)
        XCTAssertEqual(loaded[0].filePath, chunks[0].filePath)
        XCTAssertEqual(loaded[0].content, chunks[0].content)
        XCTAssertEqual(loaded[1].content, chunks[1].content)
    }

    func testLoadMissingIndexThrows() throws {
        let store = ChunkIndexStore()
        let workspace = makeWorkspace()

        do {
            _ = try store.load(for: workspace)
            XCTFail("Expected error loading non-existent index")
        } catch {
        }
    }

    func testSaveEmptyChunks() throws {
        let store = ChunkIndexStore()
        let workspace = makeWorkspace()

        let urls = try store.save(chunks: [], for: workspace)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.jsonURL.path))

        let loaded = try store.load(for: workspace)
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Search (FTS)

    func testSearchReturnsMatchingChunks() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()
        _ = try store.save(chunks: chunks, for: workspace)

        let results = try store.search(workspace: workspace, query: "sample", limit: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.filePath == "README.md" })
    }

    func testSearchMultipleTerms() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()
        _ = try store.save(chunks: chunks, for: workspace)

        let results = try store.search(workspace: workspace, query: "readme project", limit: 10)
        XCTAssertFalse(results.isEmpty)
    }

    func testSearchNoMatchesReturnsEmpty() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()
        _ = try store.save(chunks: chunks, for: workspace)

        let results = try store.search(workspace: workspace, query: "completelynonexistentterm12345", limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchEmptyQueryReturnsAll() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()
        _ = try store.save(chunks: chunks, for: workspace)

        let results = try store.search(workspace: workspace, query: "", limit: 10)
        XCTAssertEqual(results.count, min(chunks.count, 10))
    }

    func testSearchRespectsLimit() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()
        _ = try store.save(chunks: chunks, for: workspace)

        let results = try store.search(workspace: workspace, query: "", limit: 2)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Delete

    func testDeleteIndexRemovesDirectory() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()

        _ = try store.save(chunks: chunks, for: workspace)

        store.deleteIndex(for: workspace.path)

        do {
            _ = try store.load(for: workspace)
            XCTFail("Expected to not find index after deletion")
        } catch {
        }
    }

    func testDeleteIndexForUnknownPathDoesNotCrash() {
        let store = ChunkIndexStore()
        store.deleteIndex(for: "/nonexistent/path/that/does/not/exist")
    }

    // MARK: - FTS query sanitization

    func testSearchSanitizesQuery() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()
        _ = try store.save(chunks: chunks, for: workspace)

        let results = try store.search(workspace: workspace, query: "sample!@#test$%^&*()", limit: 10)
        XCTAssertNotNil(results)
    }

    func testSearchWithShortWordsOnly() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace = makeWorkspace()
        _ = try store.save(chunks: chunks, for: workspace)

        let results = try store.search(workspace: workspace, query: "ab cd", limit: 10)
        XCTAssertEqual(results.count, min(chunks.count, 10))
    }

    // MARK: - Stable workspace key

    func testConcurrentSavesDoNotFail() async throws {
        let store = ChunkIndexStore()
        let workspace = makeWorkspace()
        let chunks = makeSampleChunks()

        let failures = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    (try? store.save(chunks: chunks, for: workspace)) == nil
                }
            }
            var count = 0
            for await didFail in group where didFail { count += 1 }
            return count
        }

        XCTAssertEqual(failures, 0, "Concurrent chunk-index saves must serialize instead of failing with SQLITE_BUSY")
        let loaded = try store.load(for: workspace)
        XCTAssertEqual(loaded.count, chunks.count)
    }

    func testStableWorkspaceKeyIsDeterministic() throws {
        let store = ChunkIndexStore()
        let chunks = makeSampleChunks()
        let workspace1 = makeWorkspace()
        let workspace2 = makeWorkspace()

        let urls1 = try store.save(chunks: chunks, for: workspace1)
        let urls2 = try store.save(chunks: chunks, for: workspace2)

        XCTAssertEqual(urls1.jsonURL.deletingLastPathComponent().path,
                       urls2.jsonURL.deletingLastPathComponent().path)
    }
}
