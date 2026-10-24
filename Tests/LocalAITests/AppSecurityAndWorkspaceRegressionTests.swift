import XCTest
@testable import LocalAI

final class AppSecurityAndWorkspaceRegressionTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSecurityTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAppSupportSecuresAppContainerPaths() throws {
        let appContainer = AppSupport.baseDirectory
        try FileManager.default.createDirectory(at: appContainer, withIntermediateDirectories: true)

        let secretDir = appContainer.appendingPathComponent("secure-dir")
        let secretFile = secretDir.appendingPathComponent("secret.txt")
        try FileManager.default.createDirectory(at: secretDir, withIntermediateDirectories: true)
        try "top secret".write(to: secretFile, atomically: true, encoding: .utf8)

        AppSupport.secure(secretDir, isDirectory: true)
        AppSupport.secure(secretFile, isDirectory: false)

        let dirPermissions = try FileManager.default.attributesOfItem(atPath: secretDir.path)[.posixPermissions] as? NSNumber
        let filePermissions = try FileManager.default.attributesOfItem(atPath: secretFile.path)[.posixPermissions] as? NSNumber

        XCTAssertEqual(dirPermissions?.intValue, 0o700)
        XCTAssertEqual(filePermissions?.intValue, 0o600)
    }

    func testAppSupportSecuresIntermediateDirectoriesForNestedPath() throws {
        let appContainer = AppSupport.baseDirectory
        try FileManager.default.createDirectory(at: appContainer, withIntermediateDirectories: true)

        // Simulate the chunk-index layout: base/Indexes/<hash>/chunks.sqlite
        let indexesDir = appContainer.appendingPathComponent("Indexes", isDirectory: true)
        let workspaceDir = indexesDir.appendingPathComponent("abc123", isDirectory: true)
        let indexFile = workspaceDir.appendingPathComponent("chunks.sqlite")
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        try Data("index".utf8).write(to: indexFile)

        let fm = FileManager.default
        // Force permissive modes so the test fails unless secure() actually tightens them.
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: indexesDir.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workspaceDir.path)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: indexFile.path)

        AppSupport.secure(indexFile, isDirectory: false)

        let filePerms = try fm.attributesOfItem(atPath: indexFile.path)[.posixPermissions] as? NSNumber
        let workspacePerms = try fm.attributesOfItem(atPath: workspaceDir.path)[.posixPermissions] as? NSNumber
        let indexesPerms = try fm.attributesOfItem(atPath: indexesDir.path)[.posixPermissions] as? NSNumber

        XCTAssertEqual(filePerms?.intValue, 0o600)
        XCTAssertEqual(workspacePerms?.intValue, 0o700, "nested index directory must be restricted")
        XCTAssertEqual(indexesPerms?.intValue, 0o700, "intermediate index directory must be restricted")
    }

    func testAppSupportDoesNotSecurePathsOutsideContainer() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let file = outside.appendingPathComponent("outside.txt")
        try "outside".write(to: file, atomically: true, encoding: .utf8)

        let originalDirPerms = try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber
        let originalFilePerms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber

        AppSupport.secure(outside, isDirectory: true)
        AppSupport.secure(file, isDirectory: false)

        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber, originalDirPerms)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber, originalFilePerms)
    }

    func testWorkspaceIgnoreRulesHonorsNegationAndDirectoryOnlyPatterns() throws {
        try "*.log\n!important.log\noutdir/\n".write(to: tempDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        try createFile(at: "debug.log")
        try createFile(at: "important.log")
        try createFile(at: "build.txt")
        try createFile(at: "outdir/output.txt")

        let rules = WorkspaceIgnoreRules(root: tempDir)

        XCTAssertTrue(rules.shouldSkip(url: tempDir.appendingPathComponent("debug.log"), root: tempDir, isDirectory: false))
        XCTAssertFalse(rules.shouldSkip(url: tempDir.appendingPathComponent("important.log"), root: tempDir, isDirectory: false))
        XCTAssertFalse(rules.shouldSkip(url: tempDir.appendingPathComponent("build.txt"), root: tempDir, isDirectory: false))
        XCTAssertTrue(rules.shouldSkip(url: tempDir.appendingPathComponent("outdir"), root: tempDir, isDirectory: true))
        XCTAssertFalse(rules.shouldSkip(url: tempDir.appendingPathComponent("outdir/output.txt"), root: tempDir, isDirectory: false))
        XCTAssertFalse(WorkspaceScanner().scan(url: tempDir).files.contains { $0.relativePath == "outdir/output.txt" })
    }

    func testWorkspaceScannerSkipsSymlinksThatEscapesRoot() throws {
        let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent("workspace_escape_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        let outsideFile = outsideDir.appendingPathComponent("outside.txt")
        try "sensitive".write(to: outsideFile, atomically: true, encoding: .utf8)

        let escapedLink = tempDir.appendingPathComponent("escaped_link.txt")
        try FileManager.default.createSymbolicLink(at: escapedLink, withDestinationURL: outsideFile)
        let scanner = WorkspaceScanner()
        let workspace = scanner.scan(url: tempDir)

        XCTAssertFalse(workspace.files.contains { $0.relativePath == "escaped_link.txt" })
    }

    func testPlanOperationParserRejectsTraversalViaSymlinkBoundary() throws {
        let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent("plan_parser_escape_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        let symlinkURL = tempDir.appendingPathComponent("linked_dir")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideDir)
        try createFile(at: "source.txt", content: "data")

        let result = PlanOperationParser.resolveDestination("linked_dir/child", in: tempDir)
        XCTAssertNil(result)

        let validation = PlanOperationParser.validate(
            operation: PlanOperationEntry(from: "source.txt", to: "linked_dir/child"),
            checkedPaths: ["source.txt"],
            directory: tempDir
        )
        XCTAssertEqual(validation, "destination outside the workspace")
    }

    func testGitSnapshotDoesNotRunConfiguredFsmonitorHookOrTextconvDriver() throws {
        // SEC-003: every git invocation must pass `-c core.fsmonitor=false` and
        // `--no-textconv`, so a workspace-configured fsmonitor hook or textconv
        // driver never executes. We prove it behaviorally: if the hardening
        // regresses, git runs the spy scripts and the markers appear.
        guard processGit(["init", "-q"], in: tempDir) == 0 else {
            throw XCTSkip("git is not available in this test environment")
        }
        try createFile(at: "a.txt", content: "hello world\n")

        let fsmonitorMarker = tempDir.appendingPathComponent("fsmonitor-ran")
        let textconvMarker = tempDir.appendingPathComponent("textconv-ran")
        try createExecutableScript("fsmonitor-spy.sh", content: "#!/bin/sh\necho called >> '\(fsmonitorMarker.path)'\nexit 0\n")
        try createExecutableScript("textconv-spy.sh", content: "#!/bin/sh\necho called >> '\(textconvMarker.path)'\nexit 0\n")

        _ = processGit(["add", "a.txt"], in: tempDir)
        _ = processGit(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"], in: tempDir)
        _ = processGit(["config", "core.fsmonitor", fsmonitorMarker.deletingLastPathComponent().appendingPathComponent("fsmonitor-spy.sh").path], in: tempDir)
        _ = processGit(["config", "diff.evil.textconv", tempDir.appendingPathComponent("textconv-spy.sh").path], in: tempDir)
        try createFile(at: ".gitattributes", content: "*.txt diff=evil\n")
        try "hello changed\n".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let snapshot = GitWorkspaceReader().snapshot(for: tempDir)

        XCTAssertNotNil(snapshot, "snapshot should succeed against the adversarial repo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fsmonitorMarker.path), "configured fsmonitor hook must NOT run")
        XCTAssertFalse(FileManager.default.fileExists(atPath: textconvMarker.path), "configured textconv driver must NOT run")
    }

    private func processGit(_ arguments: [String], in directory: URL) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func createExecutableScript(_ name: String, content: String) throws {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func createFile(at relativePath: String, content: String = "") throws {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
