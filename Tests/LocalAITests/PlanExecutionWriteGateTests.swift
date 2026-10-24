import XCTest
@testable import LocalAI

final class PlanExecutionWriteGateTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlanExecutionTests_\(UUID().uuidString)")
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

    // MARK: - Write gating: validate rejects non-checked sources

    func testValidateRejectsUncheckedFile() throws {
        let source = try createFile(named: "unchecked.txt")
        let operation = PlanOperationEntry(from: "unchecked.txt", to: "docs")
        let result = PlanOperationParser.validate(
            operation: operation,
            checkedPaths: ["other.txt"],
            directory: tempDir
        )
        XCTAssertEqual(result, "not a checked file")
    }

    // MARK: - Overwrite conflicts

    func testValidateRejectsDestinationAlreadyExists() throws {
        _ = try createFile(named: "source.txt", content: "source")
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("docs"), withIntermediateDirectories: true)
        _ = try createFile(named: "docs/source.txt", content: "target")

        let operation = PlanOperationEntry(from: "source.txt", to: "docs")
        let result = PlanOperationParser.validate(
            operation: operation,
            checkedPaths: ["source.txt"],
            directory: tempDir
        )
        XCTAssertEqual(result, "destination already exists")
    }

    func testValidateRejectsSameDirectoryMove() throws {
        let source = try createFile(named: "README.md")
        let operation = PlanOperationEntry(from: "README.md", to: "")
        let result = PlanOperationParser.validate(
            operation: operation,
            checkedPaths: ["README.md"],
            directory: tempDir
        )
        XCTAssertNotNil(result, "Moving file to its own directory should fail validation")
    }

    // MARK: - Destination path parsing through symlink boundary

    func testResolveDestinationThroughSymlinkToOutside() throws {
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlanExecOutside_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }

        let symlinkURL = tempDir.appendingPathComponent("linked_dir")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideDir)

        let result = PlanOperationParser.resolveDestination("linked_dir/escape.txt", in: tempDir)
        XCTAssertNil(result, "Destination through symlink to outside should be rejected")
    }

    // MARK: - Absolute path rejection

    func testResolveDestinationAbsoluteRejects() {
        XCTAssertNil(PlanOperationParser.resolveDestination("/etc/passwd", in: tempDir))
        XCTAssertNil(PlanOperationParser.resolveDestination("/tmp/escape", in: tempDir))
    }

    // MARK: - Parent traversal rejection

    func testResolveDestinationParentTraversalRejects() {
        XCTAssertNil(PlanOperationParser.resolveDestination("../escape", in: tempDir))
        XCTAssertNil(PlanOperationParser.resolveDestination("../../escape", in: tempDir))
        XCTAssertNil(PlanOperationParser.resolveDestination("sub/../../../escape", in: tempDir))
    }

    // MARK: - No-op operations

    func testValidateNoOpDestinationSameFolder() throws {
        _ = try createFile(named: "file.txt")
        let operation = PlanOperationEntry(from: "file.txt", to: ".")

        let result = PlanOperationParser.validate(
            operation: operation,
            checkedPaths: ["file.txt"],
            directory: tempDir
        )
        XCTAssertNotNil(result, "Moving file to same folder (.) should fail validation as no-op")
    }

    func testResolveDestinationRootReturnsWorkspace() throws {
        let result = PlanOperationParser.resolveDestination(".", in: tempDir)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.standardizedFileURL.path, tempDir.standardizedFileURL.path)
    }

    // MARK: - Valid operations

    func testValidateValidMove() throws {
        _ = try createFile(named: "source.txt", content: "hello")

        let operation = PlanOperationEntry(from: "source.txt", to: "newdir")
        let result = PlanOperationParser.validate(
            operation: operation,
            checkedPaths: ["source.txt"],
            directory: tempDir
        )
        XCTAssertNil(result, "Valid move should pass validation")
    }

    func testValidateValidNestedMove() throws {
        _ = try createFile(named: "source.txt", content: "hello")

        let operation = PlanOperationEntry(from: "source.txt", to: "deep/nested/destination")
        let result = PlanOperationParser.validate(
            operation: operation,
            checkedPaths: ["source.txt"],
            directory: tempDir
        )
        XCTAssertNil(result, "Valid nested move should pass validation")
    }

    // MARK: - Source inside workspace

    func testSourceIsInsideWorkspaceRejectsOutside() {
        let outside = URL(fileURLWithPath: "/tmp/outside.txt")
        XCTAssertFalse(PlanOperationParser.sourceIsInsideWorkspace(outside, root: tempDir))
    }

    func testSourceIsInsideWorkspaceAcceptsInside() throws {
        let file = try createFile(named: "inside.txt")
        XCTAssertTrue(PlanOperationParser.sourceIsInsideWorkspace(file, root: tempDir))
    }

    // MARK: - Multiple operations: partial failure

    func testValidatePartialFailureOneInvalidAmongValid() throws {
        _ = try createFile(named: "good1.txt", content: "1")
        _ = try createFile(named: "good2.txt", content: "2")

        let op1 = PlanOperationEntry(from: "good1.txt", to: "dest")
        let op2 = PlanOperationEntry(from: "nonexistent.txt", to: "dest")
        let op3 = PlanOperationEntry(from: "good2.txt", to: "dest")

        let results = [op1, op2, op3].map { op in
            PlanOperationParser.validate(operation: op, checkedPaths: ["good1.txt", "good2.txt", "nonexistent.txt"], directory: tempDir)
        }

        XCTAssertNil(results[0])
        XCTAssertEqual(results[1], "source does not exist")
        XCTAssertNil(results[2])
    }

    // MARK: - targetExists

    func testTargetExistsAfterMove() throws {
        let source = try createFile(named: "move.txt", content: "data")
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("dest"), withIntermediateDirectories: true)
        _ = try createFile(named: "dest/move.txt", content: "existing")

        XCTAssertTrue(PlanOperationParser.targetExists(source, to: "dest", root: tempDir))
    }

    func testTargetExistsFalseWhenNoConflict() throws {
        let source = try createFile(named: "move.txt", content: "data")
        let result = PlanOperationParser.targetExists(source, to: "newdest", root: tempDir)
        XCTAssertFalse(result)
    }

    // MARK: - extract + validate pipeline

    func testExtractThenValidateAllOperations() throws {
        _ = try createFile(named: "a.txt", content: "a")
        _ = try createFile(named: "b.txt", content: "b")

        let markdown = """
        ```json
        {"operations":[
            {"from":"a.txt","to":"docs"},
            {"from":"b.txt","to":"docs"}
        ]}
        ```
        """

        guard let result = PlanOperationParser.extract(from: markdown) else {
            XCTFail("Expected extraction to succeed")
            return
        }

        let checkedPaths: Set<String> = ["a.txt", "b.txt"]
        for op in result.operations {
            XCTAssertNil(PlanOperationParser.validate(operation: op, checkedPaths: checkedPaths, directory: tempDir))
        }
    }
}
