import XCTest
@testable import LocalAI

final class ModelsTests: XCTestCase {

    // MARK: - PermissionMode.derived

    func testDerivedPermissionModeAskEveryTime() {
        let permissions = WorkspacePermissions.askEveryTime
        XCTAssertEqual(PermissionMode.derived(from: permissions), .askEveryTime)
    }

    func testDerivedPermissionModeSafeAutomation() {
        let permissions = WorkspacePermissions.safeAutomation
        XCTAssertEqual(PermissionMode.derived(from: permissions), .safeAutomation)
    }

    func testDerivedPermissionModeAutonomous() {
        let permissions = WorkspacePermissions.autonomous
        XCTAssertEqual(PermissionMode.derived(from: permissions), .autonomous)
    }

    func testDerivedPermissionModeCustom() {
        let permissions = WorkspacePermissions(read: true, write: true, delete: true, shell: false, network: true, tools: false)
        XCTAssertEqual(PermissionMode.derived(from: permissions), .custom)
    }

    func testDerivedPermissionModeCustomWhenAllOnExceptNetwork() {
        let permissions = WorkspacePermissions(read: true, write: true, delete: true, shell: true, network: true, tools: true)
        XCTAssertEqual(PermissionMode.derived(from: permissions), .custom)
    }

    // MARK: - WorkspacePermissions.preset

    func testPresetAskEveryTime() {
        let preset = WorkspacePermissions.preset(for: .askEveryTime)
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset, .askEveryTime)
    }

    func testPresetSafeAutomation() {
        let preset = WorkspacePermissions.preset(for: .safeAutomation)
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset, .safeAutomation)
    }

    func testPresetAutonomous() {
        let preset = WorkspacePermissions.preset(for: .autonomous)
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset, .autonomous)
    }

    func testPresetCustomReturnsNil() {
        XCTAssertNil(WorkspacePermissions.preset(for: .custom))
    }

    // MARK: - WorkspacePermissions.grants

    func testGrantsWhenAllRequiredPresent() {
        let permissions = WorkspacePermissions(read: true, write: true, delete: true, shell: true, network: true, tools: true)
        let required: RequiredPermissions = [.write, .delete, .shell]
        XCTAssertTrue(permissions.grants(required))
    }

    func testGrantsMissingWrite() {
        let permissions = WorkspacePermissions(read: true, write: false, delete: false, shell: false, network: false, tools: false)
        let required: RequiredPermissions = .write
        XCTAssertFalse(permissions.grants(required))
    }

    func testGrantsMissingDelete() {
        let permissions = WorkspacePermissions(read: true, write: true, delete: false, shell: true, network: true, tools: true)
        let required: RequiredPermissions = [.write, .delete]
        XCTAssertFalse(permissions.grants(required))
    }

    func testGrantsNoRequirements() {
        let permissions = WorkspacePermissions.askEveryTime
        XCTAssertTrue(permissions.grants(.none))
    }

    func testGrantsNetworkOnly() {
        let permissions = WorkspacePermissions(read: true, write: false, delete: false, shell: false, network: true, tools: false)
        XCTAssertTrue(permissions.grants(.network))
    }

    func testGrantsNotNetwork() {
        let permissions = WorkspacePermissions(read: true, write: false, delete: false, shell: false, network: false, tools: false)
        XCTAssertFalse(permissions.grants(.network))
    }

    func testGrantsShellOnly() {
        let permissions = WorkspacePermissions(read: true, write: false, delete: false, shell: true, network: false, tools: false)
        XCTAssertTrue(permissions.grants(.shell))
    }

    // MARK: - RequiredPermissions OptionSet

    func testRequiredPermissionsNone() {
        XCTAssertEqual(RequiredPermissions.none.rawValue, 0)
    }

    func testRequiredPermissionsUnion() {
        let combined: RequiredPermissions = [.write, .delete, .shell]
        XCTAssertTrue(combined.contains(.write))
        XCTAssertTrue(combined.contains(.delete))
        XCTAssertTrue(combined.contains(.shell))
        XCTAssertFalse(combined.contains(.network))
    }

    func testRequiredPermissionsRawValues() {
        XCTAssertEqual(RequiredPermissions.write.rawValue, 1 << 0)
        XCTAssertEqual(RequiredPermissions.delete.rawValue, 1 << 1)
        XCTAssertEqual(RequiredPermissions.shell.rawValue, 1 << 2)
        XCTAssertEqual(RequiredPermissions.network.rawValue, 1 << 3)
    }

    // MARK: - Preset definitions

    func testAskEveryTimePreset() {
        let p = WorkspacePermissions.askEveryTime
        XCTAssertTrue(p.read)
        XCTAssertFalse(p.write)
        XCTAssertFalse(p.delete)
        XCTAssertFalse(p.shell)
        XCTAssertFalse(p.network)
        XCTAssertFalse(p.tools)
    }

    func testSafeAutomationPreset() {
        let p = WorkspacePermissions.safeAutomation
        XCTAssertTrue(p.read)
        XCTAssertTrue(p.write)
        XCTAssertFalse(p.delete)
        XCTAssertFalse(p.shell)
        XCTAssertFalse(p.network)
    }

    func testAutonomousPreset() {
        let p = WorkspacePermissions.autonomous
        XCTAssertTrue(p.read)
        XCTAssertTrue(p.write)
        XCTAssertTrue(p.delete)
        XCTAssertTrue(p.shell)
        XCTAssertFalse(p.network)
        XCTAssertTrue(p.tools)
    }

    // MARK: - PermissionMode.description

    func testPermissionModeDescriptions() {
        XCTAssertEqual(PermissionMode.askEveryTime.description, "Read is allowed. Writes, shell, delete, network, and tools require review.")
        XCTAssertEqual(PermissionMode.safeAutomation.description, "Read and workspace writes are allowed. Delete, shell, and network require review.")
        XCTAssertEqual(PermissionMode.autonomous.description, "All local actions are allowed after explicit activation.")
        XCTAssertEqual(PermissionMode.custom.description, "Individually toggled permissions.")
    }

    // MARK: - TaskStatus

    func testTaskStatusSymbols() {
        XCTAssertEqual(TaskStatus.draft.symbol, "list.bullet.clipboard")
        XCTAssertEqual(TaskStatus.planned.symbol, "list.bullet.clipboard")
        XCTAssertEqual(TaskStatus.queued.symbol, "list.bullet.clipboard")
        XCTAssertEqual(TaskStatus.running.symbol, "play.circle")
        XCTAssertEqual(TaskStatus.complete.symbol, "checkmark.circle.fill")
        XCTAssertEqual(TaskStatus.needsReview.symbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(TaskStatus.failed.symbol, "xmark.circle.fill")
        XCTAssertEqual(TaskStatus.cancelled.symbol, "stop.circle.fill")
    }

    func testTaskStatusTints() {
        XCTAssertEqual(TaskStatus.complete.tint, .green)
        XCTAssertEqual(TaskStatus.failed.tint, .red)
        XCTAssertEqual(TaskStatus.running.tint, .blue)
        XCTAssertEqual(TaskStatus.needsReview.tint, .orange)
        XCTAssertEqual(TaskStatus.cancelled.tint, .secondary)
    }

    // MARK: - ActivityState

    func testActivityStateSymbols() {
        XCTAssertEqual(ActivityState.pending.symbol, "circle")
        XCTAssertEqual(ActivityState.running.symbol, "play.circle")
        XCTAssertEqual(ActivityState.done.symbol, "checkmark.circle.fill")
        XCTAssertEqual(ActivityState.review.symbol, "exclamationmark.circle.fill")
        XCTAssertEqual(ActivityState.failed.symbol, "xmark.circle.fill")
    }

    func testActivityStateTints() {
        XCTAssertEqual(ActivityState.done.tint, .green)
        XCTAssertEqual(ActivityState.failed.tint, .red)
        XCTAssertEqual(ActivityState.running.tint, .blue)
        XCTAssertEqual(ActivityState.review.tint, .orange)
        XCTAssertEqual(ActivityState.pending.tint, .secondary)
    }

    // MARK: - WorkspaceFileKind

    func testWorkspaceFileKindSymbols() {
        XCTAssertEqual(WorkspaceFileKind.markdown.symbol, "text.alignleft")
        XCTAssertEqual(WorkspaceFileKind.code.symbol, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(WorkspaceFileKind.pdf.symbol, "doc.richtext")
        XCTAssertEqual(WorkspaceFileKind.data.symbol, "tablecells")
    }

    func testWorkspaceFileKindReadableKinds() {
        for kind in [WorkspaceFileKind.markdown, .text, .code, .data, .pdf, .document, .presentation] {
            XCTAssertTrue(kind.canEnterContext, "\(kind) should be readable by the model")
        }
        for kind in [WorkspaceFileKind.image, .other, .folder] {
            XCTAssertFalse(kind.canEnterContext, "\(kind) should not enter context")
        }
    }

    func testWorkspaceFileKindCount() {
        XCTAssertEqual(WorkspaceFileKind.allCases.count, 10)
    }

    // MARK: - WorkspaceKind

    func testWorkspaceKindSymbols() {
        XCTAssertEqual(WorkspaceKind.general.symbol, "folder")
        XCTAssertEqual(WorkspaceKind.code.symbol, "curlybraces")
        XCTAssertEqual(WorkspaceKind.obsidian.symbol, "link")
        XCTAssertEqual(WorkspaceKind.research.symbol, "doc.text.magnifyingglass")
        XCTAssertEqual(WorkspaceKind.data.symbol, "cylinder.split.1x2")
        XCTAssertEqual(WorkspaceKind.mixed.symbol, "square.grid.2x2")
    }

    func testWorkspaceKindCount() {
        XCTAssertEqual(WorkspaceKind.allCases.count, 6)
    }

    // MARK: - TaskOutputMode

    func testTaskOutputModeSymbols() {
        XCTAssertEqual(TaskOutputMode.markdown.symbol, "doc.text")
        XCTAssertEqual(TaskOutputMode.actionItems.symbol, "checklist")
        XCTAssertEqual(TaskOutputMode.questionAnswer.symbol, "text.bubble")
        XCTAssertEqual(TaskOutputMode.structuredJSON.symbol, "curlybraces")
        XCTAssertEqual(TaskOutputMode.filePlan.symbol, "arrow.triangle.branch")
    }

    func testTaskOutputModeCount() {
        XCTAssertEqual(TaskOutputMode.allCases.count, 5)
    }

    // MARK: - MCPTransportType

    func testMCPTransportTypeIsRemote() {
        XCTAssertFalse(MCPTransportType.stdio.isRemote)
        XCTAssertTrue(MCPTransportType.streamableHTTP.isRemote)
    }

    func testMCPTransportTypeSymbols() {
        XCTAssertEqual(MCPTransportType.stdio.symbol, "terminal")
        XCTAssertEqual(MCPTransportType.streamableHTTP.symbol, "globe")
    }

    // MARK: - MCPServerConfig

    func testMCPServerConfigDetailLineStdio() {
        let server = MCPServerConfig(name: "Test", transport: .stdio, command: "uv", arguments: "run mcp-server --port 8080")
        XCTAssertEqual(server.detailLine, "uv run mcp-server --port 8080")
    }

    func testMCPServerConfigDetailLineStdioNoArgs() {
        let server = MCPServerConfig(name: "Test", transport: .stdio, command: "python3")
        XCTAssertEqual(server.detailLine, "python3")
    }

    func testMCPServerConfigDetailLineStdioNoCommand() {
        let server = MCPServerConfig(name: "Test", transport: .stdio, command: "")
        XCTAssertEqual(server.detailLine, "No command set")
    }

    func testMCPServerConfigDetailLineHTTP() {
        let server = MCPServerConfig(name: "Test", transport: .streamableHTTP, url: "http://localhost:8080/mcp")
        XCTAssertEqual(server.detailLine, "http://localhost:8080/mcp")
    }

    func testMCPServerConfigDetailLineHTTPWithHeaders() {
        let server = MCPServerConfig(name: "Test", transport: .streamableHTTP, url: "https://api.example.com/mcp", headers: ["Authorization": "Bearer token"])
        XCTAssertEqual(server.detailLine, "https://api.example.com/mcp  ·  1 header")
    }

    func testMCPServerConfigDetailLineHTTPWithMultipleHeaders() {
        let server = MCPServerConfig(name: "Test", transport: .streamableHTTP, url: "https://api.example.com/mcp", headers: ["Authorization": "Bearer token", "X-Custom": "value"])
        XCTAssertEqual(server.detailLine, "https://api.example.com/mcp  ·  2 headers")
    }

    func testMCPServerConfigDetailLineHTTPNoURL() {
        let server = MCPServerConfig(name: "Test", transport: .streamableHTTP, url: "")
        XCTAssertEqual(server.detailLine, "No URL set")
    }

    func testMCPServerConfigDecodingWithDefaults() throws {
        let json = #"""
        {"name": "Test Server"}
        """#
        let server = try JSONDecoder().decode(MCPServerConfig.self, from: Data(json.utf8))
        XCTAssertEqual(server.name, "Test Server")
        XCTAssertEqual(server.transport, .stdio)
        XCTAssertEqual(server.command, "")
        XCTAssertNotNil(server.id)
    }

    // MARK: - ChatMessage

    func testChatMessageIsFailedWithError() {
        let msg = ChatMessage(role: .assistant, markdown: "> [!ERROR]\n> Something went wrong.")
        XCTAssertTrue(msg.isFailed)
    }

    func testChatMessageIsFailedWithWarning() {
        let msg = ChatMessage(role: .assistant, markdown: "> [!WARNING]\n> Warning here.")
        XCTAssertTrue(msg.isFailed)
    }

    func testChatMessageIsNotFailed() {
        let msg = ChatMessage(role: .assistant, markdown: "## Summary\n\nAll good.")
        XCTAssertFalse(msg.isFailed)
    }

    // MARK: - TextChunk.location

    func testTextChunkLocationPageNumber() {
        let chunk = TextChunk(workspacePath: "/tmp", filePath: "doc.pdf", fileKind: "PDF", title: nil, content: "text", ordinal: 0, startLine: nil, endLine: nil, pageNumber: 5, slideNumber: nil, tokenEstimate: 10, contentHash: "abc")
        XCTAssertEqual(chunk.location, "page 5")
    }

    func testTextChunkLocationSlideNumber() {
        let chunk = TextChunk(workspacePath: "/tmp", filePath: "slides.pptx", fileKind: "Presentation", title: nil, content: "text", ordinal: 0, startLine: nil, endLine: nil, pageNumber: nil, slideNumber: 3, tokenEstimate: 10, contentHash: "abc")
        XCTAssertEqual(chunk.location, "slide 3")
    }

    func testTextChunkLocationLineRange() {
        let chunk = TextChunk(workspacePath: "/tmp", filePath: "code.swift", fileKind: "Code", title: nil, content: "text", ordinal: 0, startLine: 10, endLine: 15, pageNumber: nil, slideNumber: nil, tokenEstimate: 10, contentHash: "abc")
        XCTAssertEqual(chunk.location, "lines 10-15")
    }

    func testTextChunkLocationSingleLine() {
        let chunk = TextChunk(workspacePath: "/tmp", filePath: "code.swift", fileKind: "Code", title: nil, content: "text", ordinal: 0, startLine: 42, endLine: 42, pageNumber: nil, slideNumber: nil, tokenEstimate: 10, contentHash: "abc")
        XCTAssertEqual(chunk.location, "line 42")
    }

    func testTextChunkLocationNil() {
        let chunk = TextChunk(workspacePath: "/tmp", filePath: "file.txt", fileKind: "Text", title: nil, content: "text", ordinal: 0, startLine: nil, endLine: nil, pageNumber: nil, slideNumber: nil, tokenEstimate: 10, contentHash: "abc")
        XCTAssertNil(chunk.location)
    }

    // MARK: - SourceCitation

    func testSourceCitationDisplayTitleWithLocation() {
        let citation = SourceCitation(filePath: "doc.md", location: "lines 5-10", excerpt: "content")
        XCTAssertEqual(citation.displayTitle, "doc.md - lines 5-10")
    }

    func testSourceCitationDisplayTitleWithoutLocation() {
        let citation = SourceCitation(filePath: "doc.md", location: nil, excerpt: "content")
        XCTAssertEqual(citation.displayTitle, "doc.md")
    }

    func testSourceCitationDisplayTitleWithEmptyLocation() {
        let citation = SourceCitation(filePath: "doc.md", location: "", excerpt: "content")
        XCTAssertEqual(citation.displayTitle, "doc.md")
    }

    // MARK: - ContextBudget

    func testContextBudgetFixed() {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 1000, expectedResponse: 512, promptOverhead: 240)
        XCTAssertEqual(budget.fixed, 120 + 512 + 240)
    }

    func testContextBudgetUsed() {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 1000, expectedResponse: 512, promptOverhead: 240)
        XCTAssertEqual(budget.used, 120 + 512 + 240 + 1000)
    }

    func testContextContentBudget() {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 1000, expectedResponse: 512, promptOverhead: 240)
        XCTAssertEqual(budget.contentBudget, Int(Double(4096 - 120 - 512 - 240) * 0.8))
    }

    func testContextBudgetKeepsHeadroom() {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 1000, expectedResponse: 512, promptOverhead: 320)
        XCTAssertLessThan(budget.contentBudget, budget.limit - budget.fixed)
        XCTAssertLessThan(budget.used, budget.limit)
    }

    func testContextBudgetRetryBudgetNarrowsSelection() {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2000, expectedResponse: 512, promptOverhead: 320)
        let retry = budget.retryBudget
        XCTAssertGreaterThan(retry.selectedChunks, 0)
        XCTAssertLessThan(retry.selectedChunks, budget.contentBudget)
    }

    func testTruncatedChunksFitCapAndPreserveOrder() {
        let chunks = (0..<5).map { ordinal in
            TextChunk(workspacePath: "/tmp", filePath: "f\(ordinal).txt", fileKind: "Text", title: nil, content: "c\(ordinal)", ordinal: ordinal, startLine: nil, endLine: nil, pageNumber: nil, slideNumber: nil, tokenEstimate: 200, contentHash: "h\(ordinal)")
        }
        let truncated = chunks.truncated(to: 450)
        XCTAssertEqual(truncated.count, 2)
        XCTAssertEqual(truncated.map(\.ordinal), [0, 1])
    }

    func testContextBudgetFraction() {
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 1000, expectedResponse: 512, promptOverhead: 240)
        let expected = Double(budget.used) / Double(budget.limit)
        XCTAssertEqual(budget.fraction, expected)
    }

    func testContextBudgetFractionCappedAt1() {
        let budget = ContextBudget(limit: 100, instructions: 50, selectedChunks: 100, expectedResponse: 50, promptOverhead: 50)
        XCTAssertEqual(budget.fraction, 1.0)
    }

    func testContextBudgetFractionZeroWhenLimitZero() {
        let budget = ContextBudget(limit: 0, instructions: 0, selectedChunks: 0, expectedResponse: 0, promptOverhead: 0)
        XCTAssertEqual(budget.fraction, 0)
    }

    // MARK: - ContextBudgetMeter state

    func testMeterGreenWhenEstimateFitsWindowButExceedsContentBudget() {
        let budget = ContextBudget(limit: 32_000, instructions: 120, selectedChunks: 0, expectedResponse: 512, promptOverhead: 240)
        let contentBudget = budget.contentBudget
        let estimate = contentBudget + 1_000
        XCTAssertLessThan(estimate, budget.limit, "sanity: estimate inside the window, beyond content budget")
        XCTAssertEqual(ContextBudgetMeter.state(checkedEstimate: estimate, limit: budget.limit), .fits)
    }

    func testMeterOrangeWhenEstimateExceedsWindow() {
        let budget = ContextBudget(limit: 32_000, instructions: 120, selectedChunks: 0, expectedResponse: 512, promptOverhead: 240)
        XCTAssertEqual(ContextBudgetMeter.state(checkedEstimate: budget.limit + 1, limit: budget.limit), .selects)
    }

    func testMeterIdleWhenNothingChecked() {
        XCTAssertEqual(ContextBudgetMeter.state(checkedEstimate: 0, limit: 32_000), .idle)
    }

    // MARK: - ModelStatus

    func testModelStatusIsOnDeviceProvider() {
        let status = ModelStatus(title: "Apple Foundation Models", detail: "Available", isAvailable: true, contextWindow: 4096)
        XCTAssertTrue(status.isOnDeviceProvider)
    }

    func testModelStatusIsNotOnDeviceProviderWhenMock() {
        let status = ModelStatus(title: "Mock Local Model", detail: "Mock", isAvailable: true, contextWindow: 4096)
        XCTAssertFalse(status.isOnDeviceProvider)
    }

    func testModelStatusIsNotOnDeviceProviderWhenUnavailable() {
        let status = ModelStatus(title: "Apple Foundation Models", detail: "Unavailable", isAvailable: false, contextWindow: 4096)
        XCTAssertFalse(status.isOnDeviceProvider)
    }

    // MARK: - PlanRiskLevel

    func testPlanRiskLevelValues() {
        XCTAssertEqual(PlanRiskLevel.low.rawValue, "low")
        XCTAssertEqual(PlanRiskLevel.medium.rawValue, "medium")
        XCTAssertEqual(PlanRiskLevel.high.rawValue, "high")
    }
}
