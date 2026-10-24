import XCTest
@testable import LocalAI

final class PlanOperationParserTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlanOpTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createFile(named: String, content: String = "") throws -> URL {
        let url = tempDir.appendingPathComponent(named)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - extract

    func testExtractFromJsonCodeBlock() {
        let markdown = """
        Here is my plan.

        ```json
        {"operations":[{"from":"README.md","to":"docs"}]}
        ```

        Some trailing text.
        """

        guard let result = PlanOperationParser.extract(from: markdown) else {
            XCTFail("Expected non-nil result")
            return
        }

        XCTAssertEqual(result.operations.count, 1)
        XCTAssertEqual(result.operations[0].from, "README.md")
        XCTAssertEqual(result.operations[0].to, "docs")
        XCTAssertFalse(result.cleanMarkdown.contains("{\"operations\""))
    }

    func testExtractWithReasonField() {
        let markdown = """
        ```json
        {"operations":[{"from":"a.txt","to":"sub","reason":"Group text files"}]}
        ```
        """

        guard let result = PlanOperationParser.extract(from: markdown) else {
            XCTFail("Expected non-nil result")
            return
        }

        XCTAssertEqual(result.operations[0].reason, "Group text files")
    }

    func testExtractBareJsonObjectNotInFence() {
        let markdown = """
        My plan suggestion:

        {"operations":[{"from":"test.md","to":"docs/folder"}]}

        Done.
        """

        guard let result = PlanOperationParser.extract(from: markdown) else {
            XCTFail("Expected non-nil result")
            return
        }

        XCTAssertEqual(result.operations.count, 1)
        XCTAssertEqual(result.operations[0].from, "test.md")
        XCTAssertEqual(result.operations[0].to, "docs/folder")
        XCTAssertFalse(result.cleanMarkdown.contains("\"operations\""))
    }

    func testExtractReturnsNilWhenNoJsonBlock() {
        let markdown = "Just a regular markdown response with no JSON."
        XCTAssertNil(PlanOperationParser.extract(from: markdown))
    }

    func testExtractReturnsNilWhenOperationsEmpty() {
        let markdown = """
        ```json
        {"operations":[]}
        ```
        """
        XCTAssertNil(PlanOperationParser.extract(from: markdown))
    }

    func testExtractReturnsNilWhenJsonMalformed() {
        let markdown = "```json\n{\"operations\":[{\"from\":\"a\"]}]```"
        XCTAssertNil(PlanOperationParser.extract(from: markdown))
    }

    func testExtractReturnsNilWhenOperationsKeyMissing() {
        let markdown = "```json\n{\"moves\":[{\"from\":\"a.txt\",\"to\":\"b\"}]}```"
        XCTAssertNil(PlanOperationParser.extract(from: markdown))
    }

    func testExtractCleanMarkdownWhenJsonAtStart() {
        let markdown = """
        ```json
        {"operations":[{"from":"a.txt","to":"docs"}]}
        ```
        This is the explanation text.
        """

        guard let result = PlanOperationParser.extract(from: markdown) else {
            XCTFail("Expected non-nil result")
            return
        }

        XCTAssertEqual(result.cleanMarkdown, "This is the explanation text.")
    }

    func testExtractMultipleOperations() {
        let markdown = """
        ```json
        {"operations":[
            {"from":"a.txt","to":"docs"},
            {"from":"b.txt","to":"docs"},
            {"from":"c.md","to":"notes"}
        ]}
        ```
        """

        guard let result = PlanOperationParser.extract(from: markdown) else {
            XCTFail("Expected non-nil result")
            return
        }

        XCTAssertEqual(result.operations.count, 3)
        XCTAssertEqual(result.operations[0].from, "a.txt")
        XCTAssertEqual(result.operations[2].to, "notes")
    }

    // MARK: - resolveDestination

    func testResolveDestinationValidRelative() throws {
        _ = try createFile(named: "source.txt")
        let result = PlanOperationParser.resolveDestination("docs", in: tempDir)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, tempDir.appendingPathComponent("docs").path)
    }

    func testResolveDestinationValidNested() throws {
        let result = PlanOperationParser.resolveDestination("docs/sub/folder", in: tempDir)
        XCTAssertNotNil(result)
        let expected = tempDir.appendingPathComponent("docs").appendingPathComponent("sub").appendingPathComponent("folder")
        XCTAssertEqual(result?.standardizedFileURL.path, expected.standardizedFileURL.path)
    }

    func testResolveDestinationEmptyReturnsNil() {
        XCTAssertNil(PlanOperationParser.resolveDestination("", in: tempDir))
        XCTAssertNil(PlanOperationParser.resolveDestination("   ", in: tempDir))
    }

    func testResolveDestinationAbsoluteReturnsNil() {
        XCTAssertNil(PlanOperationParser.resolveDestination("/etc/passwd", in: tempDir))
    }

    func testResolveDestinationTraversalReturnsNil() {
        XCTAssertNil(PlanOperationParser.resolveDestination("../escape", in: tempDir))
        XCTAssertNil(PlanOperationParser.resolveDestination("docs/../../escape", in: tempDir))
    }

    func testResolveDestinationWhenRootExists() throws {
        let result = PlanOperationParser.resolveDestination(".", in: tempDir)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.standardizedFileURL.path, tempDir.standardizedFileURL.path)
    }

    func testResolveDestinationExistingSubdir() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("existing"), withIntermediateDirectories: true)
        let result = PlanOperationParser.resolveDestination("existing/new", in: tempDir)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lastPathComponent, "new")
    }

    // MARK: - sourceIsInsideWorkspace

    func testSourceIsInsideWorkspaceTrue() throws {
        let file = try createFile(named: "inner.txt")
        XCTAssertTrue(PlanOperationParser.sourceIsInsideWorkspace(file, root: tempDir))
    }

    func testSourceIsInsideWorkspaceFalse() {
        let file = URL(fileURLWithPath: "/tmp/other.txt")
        XCTAssertFalse(PlanOperationParser.sourceIsInsideWorkspace(file, root: tempDir))
    }

    func testSourceIsInsideWorkspacePrefixCollision() throws {
        let sibling = tempDir.deletingLastPathComponent()
            .appendingPathComponent("PlanOpTests_other_path")
        try? FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }

        let file = sibling.appendingPathComponent("file.txt")
        XCTAssertFalse(PlanOperationParser.sourceIsInsideWorkspace(file, root: tempDir))
    }

    // MARK: - targetExists

    func testTargetExistsFalse() throws {
        let source = try createFile(named: "source.txt")
        XCTAssertFalse(PlanOperationParser.targetExists(source, to: "newfolder", root: tempDir))
    }

    func testTargetExistsTrue() throws {
        let source = try createFile(named: "source.txt")
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("dest"), withIntermediateDirectories: true)
        _ = try createFile(named: "dest/source.txt")
        XCTAssertTrue(PlanOperationParser.targetExists(source, to: "dest", root: tempDir))
    }

    // MARK: - validate

    func testValidateNotACheckedFile() throws {
        _ = try createFile(named: "source.txt")
        let operation = PlanOperationEntry(from: "source.txt", to: "docs")
        let result = PlanOperationParser.validate(operation: operation, checkedPaths: ["other.txt"], directory: tempDir)
        XCTAssertEqual(result, "not a checked file")
    }

    func testValidateSourceDoesNotExist() throws {
        let operation = PlanOperationEntry(from: "nonexistent.txt", to: "docs")
        let result = PlanOperationParser.validate(operation: operation, checkedPaths: ["nonexistent.txt"], directory: tempDir)
        XCTAssertEqual(result, "source does not exist")
    }

    func testValidateValidOperation() throws {
        _ = try createFile(named: "source.txt", content: "hello")
        let operation = PlanOperationEntry(from: "source.txt", to: "docs")
        let result = PlanOperationParser.validate(operation: operation, checkedPaths: ["source.txt"], directory: tempDir)
        XCTAssertNil(result)
    }

    func testValidateDestinationAlreadyExists() throws {
        _ = try createFile(named: "source.txt")
        _ = try createFile(named: "docs/source.txt")
        let operation = PlanOperationEntry(from: "source.txt", to: "docs")
        let result = PlanOperationParser.validate(operation: operation, checkedPaths: ["source.txt"], directory: tempDir)
        XCTAssertEqual(result, "destination already exists")
    }
}
