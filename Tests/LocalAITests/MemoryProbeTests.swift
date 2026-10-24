import XCTest
import Darwin
import NaturalLanguage
@testable import LocalAI

final class MemoryProbeTests: XCTestCase {
    private func currentRSSKB() -> Int {
        var r = rusage()
        guard getrusage(RUSAGE_SELF, &r) == 0 else { return -1 }
        return Int(r.ru_maxrss / 1024)
    }

    private func rssMB(_ label: String, baseline: Int) -> Int {
        let now = currentRSSKB()
        let mb = Double(now) / 1024
        let delta = Double(now - baseline) / 1024
        print("[MEM] peakRSS=\(mb)MB delta=\(delta)MB -- \(label)")
        return now
    }

    func testMemoryProbeNLEmbeddingFirstUse() throws {
        guard ProcessInfo.processInfo.environment["MEM_PROBE"] == "1" else { throw XCTSkip("Diagnostic probe") }
        let baseline = currentRSSKB()
        let start = Date()
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let vector = embedding?.vector(for: "hello world")
        let elapsed = Date().timeIntervalSince(start)
        let delta = (Double(currentRSSKB() - baseline) / 1024)
        print("[MEM] NLEmbedding firstUse: loaded=\(vector != nil) modelLoadedSeconds=\(elapsed) peakDeltaMB=\(delta)")
    }

    func testMemoryProbeSelectSteps() throws {
        guard ProcessInfo.processInfo.environment["MEM_PROBE"] == "1" else { throw XCTSkip("Diagnostic probe") }
        let root = URL(fileURLWithPath: "/Users/mayeenulislam/Documents/ai-video-generation")
        let baseline = currentRSSKB()
        let workspace = try WorkspaceScanner().scan(url: root)
        let service = TaskExecutionService()
        let summary = try service.buildIndex(for: workspace)
        print("[MEM] probe select-steps: after scan+index peak=\((Double(currentRSSKB() - baseline) / 1024))MB chunks=\(summary.chunks.count)")

        func step(_ label: String, _ body: () -> Void) {
            let start = Date()
            body()
            let secs = Date().timeIntervalSince(start)
            let delta = Double(currentRSSKB() - baseline) / 1024
            print("[MEM] step \(label): time=\(secs)s peakDeltaMB=\(delta)")
        }

        let template = TaskTemplate(title: "Explain Codebase", subtitle: "Detect architecture, entry points, tests, and scripts.", symbol: "curlybraces.square", prompt: "Explain this code workspace from the checked files in plain English.", reviewRequired: false, outputMode: .markdown)

        step("ftsSearch") {
            _ = try? service.indexStore.search(workspace: workspace, query: "\(template.title) \(template.prompt)", limit: 40)
        }
        step("semanticRanked") {
            _ = service.semanticRetriever.rankedChunks(query: "\(template.title) \(template.subtitle) \(template.prompt)", chunks: summary.chunks, limit: 40)
        }
        step("selectChunks") {
            _ = try? service.selectChunks(for: template, workspace: workspace, from: summary.chunks, budget: ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512))
        }
        step("selectChunksAgain") {
            _ = try? service.selectChunks(for: template, workspace: workspace, from: summary.chunks, budget: ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512))
        }
        let summarize = TaskTemplate(title: "Summarize", subtitle: "Condense checked files into a cited Markdown brief.", symbol: "doc.text.magnifyingglass", prompt: "Summarize the checked workspace files with citations and major themes.", reviewRequired: false, outputMode: .markdown)
        step("selectChunksSummarize") {
            _ = try? service.selectChunks(for: summarize, workspace: workspace, from: summary.chunks, budget: ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512))
        }
    }

    func testMemoryProbeSemanticCache() throws {
        guard ProcessInfo.processInfo.environment["MEM_PROBE"] == "1" else { throw XCTSkip("Diagnostic probe") }
        let root = URL(fileURLWithPath: "/Users/mayeenulislam/Documents/ai-video-generation")
        let workspace = try WorkspaceScanner().scan(url: root)
        let service = TaskExecutionService()
        let summary = try service.buildIndex(for: workspace)
        let query = "Explain Codebase Detect architecture entry points tests scripts Explain this code workspace from the checked files in plain English."

        func time(_ label: String, _ body: () -> Void) {
            let start = Date()
            body()
            print("[MEM] cache \(label): \(Date().timeIntervalSince(start))s")
        }

        time("coldRank") {
            _ = service.semanticRetriever.rankedChunks(query: query, chunks: summary.chunks, limit: 40)
        }
        time("warmRank") {
            _ = service.semanticRetriever.rankedChunks(query: query, chunks: summary.chunks, limit: 40)
        }
    }

    func testMemoryProbeOpenWorkspacePathology() throws {
        guard ProcessInfo.processInfo.environment["MEM_PROBE"] == "1" else { throw XCTSkip("Diagnostic probe") }
        let root = ProcessInfo.processInfo.environment["LOCALAI_PROBE_ROOT"] ?? "/Users/mayeenulislam/Documents/ai-video-generation"
        print("[PROBE] root=\(root)")

        func time(_ label: String, _ body: () -> Void) {
            let start = Date()
            body()
            let secs = Date().timeIntervalSince(start)
            print("[PROBE] \(label): \(String(format: "%.3f", secs))s")
        }

        var workspace: Workspace!
        time("scan") { workspace = try! WorkspaceScanner().scan(url: URL(fileURLWithPath: root)) }
        print("[PROBE] scanned files=\(workspace.files.count) enterable=\(workspace.enterableFiles.count) kind=\(workspace.kind.rawValue)")

        var dirs = Set<String>()
        time("expandedDirectories") {
            for file in workspace.files {
                var components = file.relativePath.split(separator: "/")
                components.removeLast()
                while !components.isEmpty {
                    dirs.insert(components.joined(separator: "/"))
                    components.removeLast()
                }
            }
        }
        print("[PROBE] expandedDirectories count=\(dirs.count)")

        var tree: FileTree!
        time("fileTree") { tree = FileTree(workspace: workspace) }
        var totalNodes = 0
        func count(_ node: FileTreeNode) {
            totalNodes += 1
            for c in node.children { count(c) }
        }
        time("hydrateNodeCount") { tree.roots.forEach { count($0) } }
        print("[PROBE] roots=\(tree.roots.count) totalNodes=\(totalNodes)")
    }

    func testMemoryProbeScanIndexAndSelect() throws {
        guard ProcessInfo.processInfo.environment["MEM_PROBE"] == "1" else { throw XCTSkip("Diagnostic probe") }
        let root = URL(fileURLWithPath: "/Users/mayeenulislam/Documents/ai-video-generation")
        let baseline = currentRSSKB()
        print("[MEM] baseline peakRSS=\(Double(baseline) / 1024)MB")

        let workspace = try WorkspaceScanner().scan(url: root)
        var last = rssMB("scan", baseline: baseline)

        let service = TaskExecutionService()
        let summary = try service.buildIndex(for: workspace)
        last = rssMB("buildIndex", baseline: baseline)
        print("[MEM] buildIndex: chunks=\(summary.chunks.count) indexedFiles=\(summary.indexedFiles) skipped=\(summary.skippedFiles) totalChars=\(summary.chunks.reduce(0) { $0 + $1.content.count })")

        let template = TaskTemplate(title: "Explain Codebase", subtitle: "Detect architecture, entry points, tests, and scripts.", symbol: "curlybraces.square", prompt: "Explain this code workspace from the checked files in plain English.", reviewRequired: false, outputMode: .markdown)
        let budget = ContextBudget(limit: 4096, instructions: 120, selectedChunks: 2515, expectedResponse: 512)
        let selected = try service.selectChunks(for: template, workspace: workspace, from: summary.chunks, budget: budget)
        last = rssMB("selectChunks", baseline: baseline)
        print("[MEM] select: selected=\(selected.count) tokens=\(selected.reduce(0) { $0 + $1.tokenEstimate })")

        _ = last
    }
}