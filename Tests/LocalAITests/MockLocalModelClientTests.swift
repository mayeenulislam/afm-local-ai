import XCTest
@testable import LocalAI

@MainActor
final class MockLocalModelClientTests: XCTestCase {

    private func sampleBudget() -> ContextBudget {
        ContextBudget(
            limit: 4096,
            instructions: 120,
            selectedChunks: 4096 - 120 - 512 - 240,
            expectedResponse: 512,
            promptOverhead: 240
        )
    }

    // MARK: - Availability

    func testMockAvailability() async {
        let client = MockLocalModelClient()
        let status = await client.availability()

        XCTAssertEqual(status.title, "Mock Local Model")
        XCTAssertEqual(status.detail, "Ready. Using deterministic local mock responses until Foundation Models execution is enabled.")
        XCTAssertTrue(status.isAvailable)
        XCTAssertEqual(status.contextWindow, 4096)
        XCTAssertEqual(status.supportedLanguages, ["en"])
        XCTAssertTrue(status.currentLocaleSupported)
    }

    func testMockDisplayName() {
        let client = MockLocalModelClient()
        XCTAssertEqual(client.displayName, "Mock Local Model")
    }

    // MARK: - streamResponse

    func testStreamResponseDefaultMode() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Summarize",
            prompt: "Summarize this.",
            chunks: [sampleChunk()],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        var partials: [String] = []
        var completed: LocalModelResult?

        for try await event in client.streamResponse(to: request) {
            switch event {
            case .partialMarkdown(let markdown):
                partials.append(markdown)
            case .completed(let result):
                completed = result
            }
        }

        XCTAssertFalse(partials.isEmpty)
        XCTAssertNotNil(completed)
        XCTAssertTrue(completed!.markdown.contains("Summarize"))
        XCTAssertEqual(completed!.citations.count, 1)
        XCTAssertEqual(completed!.tokenEstimate, request.contextBudget.used)
    }

    func testStreamResponseActionItemsMode() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Extract Actions",
            prompt: "Extract actions",
            chunks: [chunkWithContent("TODO: Fix the login bug. FIXME: update docs.")],
            contextBudget: sampleBudget(),
            outputMode: .actionItems
        )

        var completed: LocalModelResult?
        for try await event in client.streamResponse(to: request) {
            if case .completed(let result) = event {
                completed = result
            }
        }

        XCTAssertNotNil(completed)
        XCTAssertTrue(completed!.markdown.contains("## Action Items"))
        XCTAssertEqual(completed!.actionItems.count, 1)
        XCTAssertEqual(completed!.actionItems[0].sourcePath, "test.swift")
        XCTAssertEqual(completed!.actionItems[0].confidence, 0.62)
    }

    func testStreamResponseActionItemsNoMatches() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Extract Actions",
            prompt: "Extract actions",
            chunks: [chunkWithContent("Nothing relevant here.")],
            contextBudget: sampleBudget(),
            outputMode: .actionItems
        )

        var completed: LocalModelResult?
        for try await event in client.streamResponse(to: request) {
            if case .completed(let result) = event {
                completed = result
            }
        }

        XCTAssertNotNil(completed)
        XCTAssertTrue(completed!.markdown.contains("No action items found"))
        XCTAssertTrue(completed!.actionItems.isEmpty)
    }

    func testStreamResponseFilePlanMode() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Organize Files",
            prompt: "Organize files",
            chunks: [sampleChunk(), chunkWithName("Other.swift")],
            contextBudget: sampleBudget(),
            outputMode: .filePlan
        )

        var completed: LocalModelResult?
        for try await event in client.streamResponse(to: request) {
            if case .completed(let result) = event {
                completed = result
            }
        }

        XCTAssertNotNil(completed)
        XCTAssertTrue(completed!.markdown.contains("## Safe File Plan"))
        XCTAssertNotNil(completed!.fileOperationPlan)
        XCTAssertEqual(completed!.fileOperationPlan?.operations.count, 2)
        XCTAssertEqual(completed!.fileOperationPlan?.operations[0].proposedPath, "Organized")
        XCTAssertTrue(completed!.fileOperationPlan?.requiresApproval ?? false)
    }

    func testStreamResponseFilePlanContainsValidJSON() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Organize Files",
            prompt: "Organize files",
            chunks: [sampleChunk()],
            contextBudget: sampleBudget(),
            outputMode: .filePlan
        )

        var completed: LocalModelResult?
        for try await event in client.streamResponse(to: request) {
            if case .completed(let result) = event {
                completed = result
            }
        }

        guard let markdown = completed?.markdown else {
            XCTFail("Expected result")
            return
        }

        let jsonRange = markdown.range(of: "```json")
        XCTAssertNotNil(jsonRange)

        let after = markdown[jsonRange!.upperBound...]
        let endRange = after.range(of: "```")
        XCTAssertNotNil(endRange)

        let jsonBlock = String(after[..<endRange!.lowerBound])
        let data = jsonBlock.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        let ops = parsed!["operations"] as? [[String: Any]]
        XCTAssertNotNil(ops)
        XCTAssertEqual(ops!.count, 1)
        XCTAssertEqual(ops![0]["from"] as? String, "README.md")
        XCTAssertEqual(ops![0]["to"] as? String, "Organized")
    }

    func testStreamResponseFilePlanEmptyChunks() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Organize Files",
            prompt: "Organize files",
            chunks: [],
            contextBudget: sampleBudget(),
            outputMode: .filePlan
        )

        var completed: LocalModelResult?
        for try await event in client.streamResponse(to: request) {
            if case .completed(let result) = event {
                completed = result
            }
        }

        XCTAssertNotNil(completed)
        XCTAssertTrue(completed!.markdown.contains("## File Plan"))
        XCTAssertTrue(completed!.markdown.contains("No file operations were proposed."))
        XCTAssertNil(completed!.fileOperationPlan)
    }

    func testStreamResponseGeneralChatMode() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "General Chat",
            prompt: "Hello world",
            chunks: [],
            contextBudget: sampleBudget(),
            outputMode: .questionAnswer
        )

        var completed: LocalModelResult?
        for try await event in client.streamResponse(to: request) {
            if case .completed(let result) = event {
                completed = result
            }
        }

        XCTAssertNotNil(completed)
        XCTAssertTrue(completed!.markdown.contains("## General Chat"))
        XCTAssertTrue(completed!.markdown.contains("Hello world"))
    }

    func testStreamResponseStructuredJSONMode() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Extract to JSON",
            prompt: "Extract records",
            chunks: [sampleChunk()],
            contextBudget: sampleBudget(),
            outputMode: .structuredJSON
        )

        var completed: LocalModelResult?
        for try await event in client.streamResponse(to: request) {
            if case .completed(let result) = event {
                completed = result
            }
        }

        XCTAssertNotNil(completed)
        XCTAssertTrue(completed!.markdown.contains("## Extract to JSON"))
        XCTAssertTrue(completed!.markdown.contains("README.md"))
    }

    func testStreamResponseCancellation() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Summarize",
            prompt: "test",
            chunks: [sampleChunk()],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        let task = Task {
            for try await _ in client.streamResponse(to: request) {
            }
        }

        task.cancel()
        do {
            try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        }
    }

    func testStreamResponseProgressiveAccumulation() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Summarize",
            prompt: "test",
            chunks: [sampleChunk()],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        var partials: [String] = []
        for try await event in client.streamResponse(to: request) {
            if case .partialMarkdown(let md) = event {
                partials.append(md)
            }
        }

        XCTAssertGreaterThan(partials.count, 1)
        for i in 1..<partials.count {
            XCTAssertGreaterThanOrEqual(partials[i].count, partials[i - 1].count)
        }
    }

    // MARK: - respond

    func testRespondReturnsLatestResult() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Test",
            prompt: "test",
            chunks: [sampleChunk()],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        let result = try await client.respond(to: request)
        XCTAssertTrue(result.markdown.contains("Test"))
        XCTAssertEqual(result.citations.count, 1)
    }

    func testRespondConversationSummary() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Conversation Summary",
            prompt: "Summarize",
            chunks: [],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        let result = try await client.respond(to: request)
        XCTAssertTrue(result.markdown.contains("Conversation memory (mock)"))
    }

    func testRespondFallsBackToPartialWhenNoCompleted() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Test",
            prompt: "test",
            chunks: [sampleChunk()],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        let result = try await client.respond(to: request)
        XCTAssertFalse(result.markdown.isEmpty)
        XCTAssertEqual(result.tokenEstimate, request.contextBudget.used)
    }

    // MARK: - Behavior of private helpers via public interface

    func testCitationsExcerptTruncatesLongContent() async throws {
        let longContent = String(repeating: "This is a long document content. ", count: 100)
        let chunk = TextChunk(
            workspacePath: "/tmp/workspace",
            filePath: "long.txt",
            fileKind: "Text",
            title: nil,
            content: longContent,
            ordinal: 0,
            startLine: 1,
            endLine: 100,
            pageNumber: nil,
            slideNumber: nil,
            tokenEstimate: 100,
            contentHash: "abc"
        )

        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Summarize",
            prompt: "test",
            chunks: [chunk],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        let result = try await client.respond(to: request)
        let citation = result.citations.first
        XCTAssertNotNil(citation)
        XCTAssertLessThanOrEqual(citation!.excerpt.count, 240)
    }

    func testOneLineSummaryTruncatesLongContent() async throws {
        let longContent = String(repeating: "word ", count: 100)
        let chunk = TextChunk(
            workspacePath: "/tmp/workspace",
            filePath: "test.txt",
            fileKind: "Text",
            title: nil,
            content: longContent,
            ordinal: 0,
            startLine: 1,
            endLine: 1,
            pageNumber: nil,
            slideNumber: nil,
            tokenEstimate: 10,
            contentHash: "abc"
        )

        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Summarize",
            prompt: "test",
            chunks: [chunk],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        let result = try await client.respond(to: request)
        XCTAssertTrue(result.markdown.contains("word"))
    }

    func testActionItemsFilteredByKeywords() async throws {
        let client = MockLocalModelClient()
        let chunk = TextChunk(
            workspacePath: "/tmp/workspace",
            filePath: "tasks.swift",
            fileKind: "Code",
            title: nil,
            content: "TODO: implement feature X. FIXME: fix bug Y. ACTION: review PR. Just regular text.",
            ordinal: 0,
            startLine: 1,
            endLine: 1,
            pageNumber: nil,
            slideNumber: nil,
            tokenEstimate: 10,
            contentHash: "abc"
        )

        let request = LocalModelRequest(
            taskTitle: "Extract Actions",
            prompt: "extract",
            chunks: [chunk],
            contextBudget: sampleBudget(),
            outputMode: .actionItems
        )

        let result = try await client.respond(to: request)
        XCTAssertEqual(result.actionItems.count, 1)
    }

    func testActionItemsChecksFirst8ChunksOnly() async throws {
        let client = MockLocalModelClient()
        let chunks = (0..<10).map { i in
            TextChunk(
                workspacePath: "/tmp/workspace",
                filePath: "file\(i).txt",
                fileKind: "Text",
                title: nil,
                content: "TODO: task \(i)",
                ordinal: 0,
                startLine: 1,
                endLine: 1,
                pageNumber: nil,
                slideNumber: nil,
                tokenEstimate: 5,
                contentHash: "hash\(i)"
            )
        }

        let request = LocalModelRequest(
            taskTitle: "Extract Actions",
            prompt: "extract",
            chunks: chunks,
            contextBudget: sampleBudget(),
            outputMode: .actionItems
        )

        let result = try await client.respond(to: request)
        XCTAssertEqual(result.actionItems.count, 8)
    }

    func testNoCitationsWhenNoChunks() async throws {
        let client = MockLocalModelClient()
        let request = LocalModelRequest(
            taskTitle: "Summarize",
            prompt: "test",
            chunks: [],
            contextBudget: sampleBudget(),
            outputMode: .markdown
        )

        let result = try await client.respond(to: request)
        XCTAssertTrue(result.citations.isEmpty)
    }

    // MARK: - Helpers

    private func sampleChunk() -> TextChunk {
        TextChunk(
            workspacePath: "/tmp/workspace",
            filePath: "README.md",
            fileKind: "Markdown",
            title: "Test Document",
            content: "This is a sample document for testing purposes. It has some content to chunk.",
            ordinal: 0,
            startLine: 1,
            endLine: 3,
            tokenEstimate: 20,
            contentHash: "abc123"
        )
    }

    private func chunkWithContent(_ content: String) -> TextChunk {
        TextChunk(
            workspacePath: "/tmp/workspace",
            filePath: "test.swift",
            fileKind: "Code",
            title: nil,
            content: content,
            ordinal: 0,
            startLine: 1,
            endLine: 1,
            tokenEstimate: 10,
            contentHash: "hash"
        )
    }

    private func chunkWithName(_ name: String) -> TextChunk {
        TextChunk(
            workspacePath: "/tmp/workspace",
            filePath: name,
            fileKind: "Code",
            title: nil,
            content: "Content of \(name)",
            ordinal: 1,
            startLine: 1,
            endLine: 1,
            tokenEstimate: 10,
            contentHash: "hash2"
        )
    }
}
