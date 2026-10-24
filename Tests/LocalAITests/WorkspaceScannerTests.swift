import XCTest
@testable import LocalAI

final class WorkspaceScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceScannerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createFile(at relativePath: String, content: String = "") throws {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func createDirectory(at relativePath: String) throws {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - File scanning

    func testScanFindsAllFiles() throws {
        try createFile(at: "file1.txt", content: "hello")
        try createFile(at: "file2.md", content: "# Title")
        try createFile(at: "subdir/file3.swift", content: "import Foundation")

        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)

        XCTAssertEqual(workspace.summary.totalFiles, 3)
        XCTAssertTrue(workspace.files.contains { $0.relativePath == "file1.txt" })
        XCTAssertTrue(workspace.files.contains { $0.relativePath == "file2.md" })
        XCTAssertTrue(workspace.files.contains { $0.relativePath == "subdir/file3.swift" })
    }

    func testScanIgnoresDefaultDirectories() throws {
        try createFile(at: "visible.txt", content: "hello")
        try createFile(at: ".git/config", content: "git")
        try createFile(at: ".DS_Store", content: "ds")
        try createFile(at: "node_modules/pkg/index.js", content: "js")
        try createFile(at: "build/output.o", content: "build")

        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)

        XCTAssertEqual(workspace.summary.totalFiles, 1)
        XCTAssertTrue(workspace.summary.ignoredItems > 0)
        XCTAssertTrue(workspace.files.contains { $0.relativePath == "visible.txt" })
    }

    func testScanRespectsGitignore() throws {
        try createFile(at: ".gitignore", content: "*.tmp\nsecret/")
        try createFile(at: "normal.txt", content: "ok")
        try createFile(at: "temp.tmp", content: "should be ignored")
        try createFile(at: "secret/password.txt", content: "hidden")

        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)

        XCTAssertEqual(workspace.summary.totalFiles, 1)
        XCTAssertTrue(workspace.files.contains { $0.relativePath == "normal.txt" })
        XCTAssertFalse(workspace.files.contains { $0.relativePath == "temp.tmp" })
        XCTAssertFalse(workspace.files.contains { $0.relativePath == "secret/password.txt" })
    }

    func testScanGitignoreNegation() throws {
        try createFile(at: ".gitignore", content: "*.log\n!important.log")
        try createFile(at: "debug.log", content: "ignore")
        try createFile(at: "important.log", content: "keep")

        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)

        XCTAssertEqual(workspace.summary.totalFiles, 1)
        XCTAssertTrue(workspace.files.contains { $0.relativePath == "important.log" })
    }

    func testScanGitignoreDirectoryOnly() throws {
        try createFile(at: ".gitignore", content: "build/")
        try createFile(at: "build.txt", content: "keep")
        try createDirectory(at: "build")
        try createFile(at: "build/output.txt", content: "ignore")

        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)

        XCTAssertTrue(workspace.files.contains { $0.relativePath == "build.txt" })
        XCTAssertFalse(workspace.files.contains { $0.relativePath == "build/output.txt" })
    }

    // MARK: - File classification

    func testClassifyMarkdown() throws {
        try createFile(at: "doc.md")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.first?.kind, .markdown)
    }

    func testClassifyText() throws {
        try createFile(at: "notes.txt")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.first?.kind, .text)
    }

    func testClassifyCode() throws {
        try createFile(at: "main.swift")
        try createFile(at: "app.py")
        try createFile(at: "index.js")
        try createFile(at: "main.ts")
        try createFile(at: "main.go")
        try createFile(at: "Cargo.toml")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.summary.counts[.code], 6)
    }

    func testClassifyPDF() throws {
        try createFile(at: "doc.pdf")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.first?.kind, .pdf)
    }

    func testClassifyDocument() throws {
        try createFile(at: "doc.docx")
        try createFile(at: "doc.pages")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.filter { $0.kind == .document }.count, 2)
    }

    func testClassifyPresentation() throws {
        try createFile(at: "slides.pptx")
        try createFile(at: "slides.key")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.filter { $0.kind == .presentation }.count, 2)
    }

    func testClassifyData() throws {
        try createFile(at: "data.sqlite")
        try createFile(at: "data.db")
        try createFile(at: "data.csv")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.filter { $0.kind == .data }.count, 3)
    }

    func testClassifyImage() throws {
        try createFile(at: "photo.png")
        try createFile(at: "photo.jpg")
        try createFile(at: "photo.heic")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.filter { $0.kind == .image }.count, 3)
    }

    func testClassifyUnknown() throws {
        try createFile(at: "file.unknownext")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.files.first?.kind, .other)
    }

    // MARK: - File type guide (supported extensions)

    func testSupportedFileTypeSummaryListsAllReadableExtensions() {
        let summary = WorkspaceFileKind.supportedSummary
        XCTAssertEqual(summary.title, "Supported")
        for suffix in FileKindSuffixes.readable {
            XCTAssertTrue(summary.detail.contains(".\(suffix)"), "supported suffix .\(suffix) must be listed")
        }
    }

    func testSupportedFileTypeTableGroupsEveryReadableKind() {
        let table = FileKindSuffixes.supportedTable
        let groupedCount = table.reduce(0) { $0 + $1.extensions.count }
        XCTAssertEqual(groupedCount, FileKindSuffixes.readable.count)
        XCTAssertEqual(
            Set(table.map(\.title)),
            ["Markdown", "Text", "Code", "PDF", "Documents", "Presentations", "Data"]
        )
        XCTAssertNotNil(table.first { $0.title == "Code" && $0.extensions.contains("swift") })
    }

    func testBinaryOrUnsupportedFormatsNeverEnterContext() throws {
        for name in ["drawing.excalidraw", "plan.dwg", "part.cad", "run.sh"] {
            try createFile(at: name)
        }
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        for suffix in ["excalidraw", "dwg", "cad", "sh"] {
            let kind = workspace.files.first { $0.url.pathExtension.lowercased() == suffix }?.kind
            XCTAssertEqual(kind, .other, ".\(suffix) must classify as .other (unsupported)")
        }
        XCTAssertTrue(workspace.enterableFiles.allSatisfy { $0.kind.canEnterContext })
    }

    func testReadableSuffixesCoverAllClassifiableReadableKinds() throws {
        let readable = FileKindSuffixes.readable
        for suffix in readable {
            try createFile(at: "probe.\(suffix)")
            let scanner = WorkspaceScanner()
            let workspace = scanner.scan(url: tempDir)
            let kind = workspace.files.last?.kind
            XCTAssertTrue(kind != .image && kind != .other, "readable suffix \(suffix) must classify to a readable kind, got \(String(describing: kind))")
        }
    }

    // MARK: - Workspace kind classification

    func testClassifyObsidianWorkspace() throws {
        try createDirectory(at: ".obsidian")
        try createFile(at: "note.md")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.kind, .obsidian)
    }

    func testClassifyGeneralWorkspace() throws {
        try createFile(at: "readme.txt", content: "just text")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.kind, .general)
    }

    func testClassifyCodeWorkspace() throws {
        try createFile(at: "Package.swift", content: "")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.kind, .code)
    }

    func testClassifyResearchWorkspace() throws {
        try createFile(at: "paper.pdf")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.kind, .research)
    }

    func testClassifyDataWorkspace() throws {
        try createFile(at: "data.sqlite")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.kind, .data)
    }

    func testClassifyMixedWorkspace() throws {
        try createFile(at: "code.swift")
        try createFile(at: "doc.pdf")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.kind, .mixed)
    }

    // MARK: - Summary

    func testSummaryTotalBytes() throws {
        try createFile(at: "a.txt", content: "aaa")
        try createFile(at: "b.txt", content: "bbbb")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        XCTAssertEqual(workspace.summary.totalBytes, 7)
    }

    func testSummaryReadableSize() {
        var summary = WorkspaceSummary()
        summary.totalBytes = 1024
        XCTAssertEqual(summary.readableSize, "1 KB")
    }

    func testSummaryCountFor() {
        var summary = WorkspaceSummary()
        summary.counts[.code] = 3
        summary.counts[.text] = 2
        XCTAssertEqual(summary.count(for: .code), 3)
        XCTAssertEqual(summary.count(for: .text), 2)
        XCTAssertEqual(summary.count(for: .pdf), 0)
    }

    // MARK: - File sorting

    func testFilesAreSortedByRelativePath() throws {
        try createFile(at: "zebra.txt")
        try createFile(at: "apple.txt")
        try createFile(at: "mango.txt")
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)
        let paths = workspace.files.map(\.relativePath)
        XCTAssertEqual(paths, paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(paths, ["apple.txt", "mango.txt", "zebra.txt"])
    }
}
