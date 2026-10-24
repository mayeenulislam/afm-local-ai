import XCTest
@testable import LocalAI

final class TaskExecutionSelectionTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskExecutionSelectionTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeService() -> TaskExecutionService {
        TaskExecutionService()
    }

    private func makeWorkspace() -> Workspace {
        let files = [
            WorkspaceFile(url: tempDir.appendingPathComponent("GIT-BACKUP.md"), relativePath: "GIT-BACKUP.md", kind: .markdown, byteCount: 100),
            WorkspaceFile(url: tempDir.appendingPathComponent("BRAINSTORMING/01-BRAND-NICHE.md"), relativePath: "BRAINSTORMING/01-BRAND-NICHE.md", kind: .markdown, byteCount: 100),
            WorkspaceFile(url: tempDir.appendingPathComponent("scripts/generate.py"), relativePath: "scripts/generate.py", kind: .code, byteCount: 100)
        ]
        return Workspace(url: tempDir, kind: .general, files: files, summary: WorkspaceSummary(), scannedAt: Date())
    }

    private func makeChunks() -> [TextChunk] {
        [
            TextChunk(workspacePath: tempDir.path, filePath: "GIT-BACKUP.md", fileKind: "Markdown", title: "GIT Backup", content: "# GIT Backup\n\nDaily backup habit.", ordinal: 0, startLine: nil, endLine: nil, pageNumber: nil, slideNumber: nil, tokenEstimate: 40, contentHash: "a"),
            TextChunk(workspacePath: tempDir.path, filePath: "BRAINSTORMING/01-BRAND-NICHE.md", fileKind: "Markdown", title: "Brand Niche", content: "# Brand Niche\n\nOne niche for short videos.", ordinal: 0, startLine: nil, endLine: nil, pageNumber: nil, slideNumber: nil, tokenEstimate: 40, contentHash: "b"),
            TextChunk(workspacePath: tempDir.path, filePath: "scripts/generate.py", fileKind: "Code", title: "generate", content: "def generate_video():\n    pass", ordinal: 0, startLine: nil, endLine: nil, pageNumber: nil, slideNumber: nil, tokenEstimate: 30, contentHash: "c")
        ]
    }

    private func explainTemplate() -> TaskTemplate {
        TaskTemplate(title: "Explain Codebase", subtitle: "Detect architecture, entry points, tests, and scripts.", symbol: "curlybraces.square", prompt: "Explain this code workspace from the checked files in plain English.", reviewRequired: false, outputMode: .markdown)
    }

    func testExplainCodebaseStartsWithWorkspaceOverview() throws {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512)
        let selected = try makeService().selectChunks(for: explainTemplate(), workspace: makeWorkspace(), from: makeChunks(), budget: budget)
        XCTAssertNotNil(selected.first)
        XCTAssertEqual(selected.first?.fileKind, "Summary")
        XCTAssertTrue(selected.first?.content.contains("GIT-BACKUP.md") == true)
        XCTAssertTrue(selected.first?.content.contains("generate.py") == true)
        XCTAssertLessThanOrEqual(selected.reduce(0) { $0 + $1.tokenEstimate }, budget.selectedChunks)
    }

    func testSummarizeDoesNotAddOverview() throws {
        let template = TaskTemplate(title: "Summarize", subtitle: "Condense checked files into a cited Markdown brief.", symbol: "doc.text.magnifyingglass", prompt: "Summarize the checked workspace files with citations and major themes.", reviewRequired: false, outputMode: .markdown)
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512)
        let selected = try makeService().selectChunks(for: template, workspace: makeWorkspace(), from: makeChunks(), budget: budget)
        XCTAssertFalse(selected.contains { $0.fileKind == "Summary" })
    }

    private func makeChunk(_ path: String, title: String, content: String, hash: String) -> TextChunk {
        TextChunk(workspacePath: tempDir.path, filePath: path, fileKind: "Markdown", title: title, content: content, ordinal: 0, startLine: nil, endLine: nil, pageNumber: nil, slideNumber: nil, tokenEstimate: 10, contentHash: hash)
    }

    func testSemanticCandidatePoolIsBoundedWhenFTSIsEmpty() throws {
        let chunks = (0..<200).map { makeChunk("f\($0).md", title: "File \($0)", content: "plain content \($0)", hash: "h\($0)") }
        let pool = makeService().semanticCandidatePool(chunks: chunks, ftsMatches: [], keywords: ["video"], limit: 60)
        XCTAssertLessThanOrEqual(pool.count, 60)
        XCTAssertEqual(Set(pool.map(\.contentHash)).count, pool.count, "pool must not contain duplicates")
    }

    func testSemanticCandidatePoolPrioritizesFTSAndKeywordMatches() throws {
        let keywordChunk = makeChunk("notes.md", title: "Notes", content: "video script planning notes", hash: "kw")
        let plain = (0..<120).map { makeChunk("p\($0).txt", title: "Plain \($0)", content: "unrelated filler text", hash: "p\($0)") }
        let chunks = plain + [keywordChunk]
        let pool = makeService().semanticCandidatePool(chunks: chunks, ftsMatches: [keywordChunk], keywords: ["video", "script"], limit: 60)
        XCTAssertEqual(pool.first?.contentHash, "kw", "FTS matches come first")
        XCTAssertLessThanOrEqual(pool.count, 60)
        XCTAssertGreaterThanOrEqual(pool.count, 1)
    }

    func testExplainSelectChunksWithManyChunksStaysBounded() throws {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512)
        let chunks = (0..<120).map { makeChunk("doc\($0).md", title: "Doc \($0)", content: "workspace architecture notes entry point", hash: "d\($0)") }
        let selected = try makeService().selectChunks(for: explainTemplate(), workspace: makeWorkspace(), from: chunks, budget: budget)
        XCTAssertFalse(selected.isEmpty)
        XCTAssertLessThanOrEqual(selected.count, 12)
        XCTAssertLessThanOrEqual(selected.reduce(0) { $0 + $1.tokenEstimate }, budget.selectedChunks)
    }

    func testSelectChunksIsStableAcrossRuns() throws {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512)
        let service = makeService()
        let first = try service.selectChunks(for: explainTemplate(), workspace: makeWorkspace(), from: makeChunks(), budget: budget)
        let second = try service.selectChunks(for: explainTemplate(), workspace: makeWorkspace(), from: makeChunks(), budget: budget)
        XCTAssertEqual(first.map(\.contentHash), second.map(\.contentHash), "selection must be deterministic across repeated runs")
    }
}