import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Collects file-move proposals made by the on-device model via tool calls.
/// The tool only *records* a proposal — the real `FileManager` move happens later
/// in `AppState.approvePlan`, gated on the Write permission. This keeps
/// plan-before-action intact while getting reliable structured moves from AFM.
actor OrganizerProposalStore {
    static let shared = OrganizerProposalStore()
    private var proposals: [(from: String, toFolder: String)] = []
    private var workspaceRoot: URL = URL(fileURLWithPath: "/")

    var currentRoot: URL? { workspaceRoot }

    func begin(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
        proposals = []
    }

    func record(_ from: String, _ toFolder: String) {
        proposals.append((from: stripWorkspace(from), toFolder: stripWorkspace(toFolder)))
    }

    func all() -> [(from: String, toFolder: String)] { proposals }

    private func stripWorkspace(_ path: String) -> String {
        let root = workspaceRoot.standardizedFileURL.path
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(root), trimmed.count > root.count {
            return String(trimmed.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return trimmed
    }
}

@available(macOS 26.0, *)
struct FileListerTool: FoundationModels.Tool {
    typealias Output = String
    let name = "list_workspace_files"
    let description = "List the files in the current workspace. Call this first to see what files are available before deciding moves."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let root = await OrganizerProposalStore.shared.currentRoot
        guard let root else { return "No workspace is open." }
        let filePaths = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return filePaths.isEmpty ? "The workspace is empty." : filePaths.joined(separator: "\n")
    }
}

@available(macOS 26.0, *)
struct OrganizerTool: FoundationModels.Tool {
    typealias Output = String
    let name = "organize_file"
    let description = "Move a single checked workspace file into a destination folder within the workspace. Call this once per file you want to move. The source must be one of the exact file names listed by list_workspace_files; the destination must be a relative folder path inside the workspace (e.g. 'docs'). Do not set the destination folder to the file's current folder."

    @Generable
    struct Arguments {
        @Guide(description: "The exact source file name to move, as listed by list_workspace_files.")
        var source: String
        @Guide(description: "A relative folder path inside the workspace to move the file into (e.g. 'docs').")
        var destination: String
    }

    func call(arguments: Arguments) async throws -> String {
        await OrganizerProposalStore.shared.record(arguments.source, arguments.destination)
        return "Proposed moving \(arguments.source) into the '\(arguments.destination)' folder. It will run only after the user approves."
    }
}
#endif
