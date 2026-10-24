import Foundation
import SwiftUI

enum WorkspaceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case general = "General"
    case code = "Code"
    case obsidian = "Obsidian"
    case research = "Research"
    case data = "Data"
    case mixed = "Mixed"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "folder"
        case .code: "curlybraces"
        case .obsidian: "link"
        case .research: "doc.text.magnifyingglass"
        case .data: "cylinder.split.1x2"
        case .mixed: "square.grid.2x2"
        }
    }
}

enum WorkspaceFileKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case markdown = "Markdown"
    case text = "Text"
    case code = "Code"
    case pdf = "PDF"
    case document = "Document"
    case presentation = "Presentation"
    case data = "Data"
    case image = "Image"
    case folder = "Folder"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .markdown: "text.alignleft"
        case .text: "doc.plaintext"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .pdf: "doc.richtext"
        case .document: "doc.text"
        case .presentation: "rectangle.on.rectangle"
        case .data: "tablecells"
        case .image: "photo"
        case .folder: "folder"
        case .other: "doc"
        }
    }

    var tint: Color {
        switch self {
        case .markdown: .blue
        case .text: .secondary
        case .code: .purple
        case .pdf: .red
        case .document: .indigo
        case .presentation: .orange
        case .data: .green
        case .image: .pink
        case .folder: .accentColor
        case .other: .secondary
        }
    }
}

struct WorkspaceFile: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let relativePath: String
    let kind: WorkspaceFileKind
    let byteCount: Int64

    var name: String { url.lastPathComponent }
}

struct WorkspaceSummary: Sendable {
    var totalFiles = 0
    var totalBytes: Int64 = 0
    var ignoredItems = 0
    var counts: [WorkspaceFileKind: Int] = [:]

    var readableSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    func count(for kind: WorkspaceFileKind) -> Int {
        counts[kind, default: 0]
    }
}

struct Workspace: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    var kind: WorkspaceKind
    var files: [WorkspaceFile]
    var summary: WorkspaceSummary
    var scannedAt: Date

    var name: String { url.lastPathComponent }
    var path: String { url.path }

    var enterableFiles: [WorkspaceFile] {
        files.filter { $0.kind.canEnterContext }
    }
}

enum StudioMode: String, Codable, Sendable {
    case dashboard
    case generalChat
    case workspace
}

struct RecentWorkspace: Identifiable, Codable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var kind: WorkspaceKind
    var openedAt: Date
    var totalFiles: Int
}

enum PermissionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case askEveryTime = "Ask Every Time"
    case safeAutomation = "Safe Automation"
    case autonomous = "Autonomous"
    case custom = "Custom"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .askEveryTime:
            "Read is allowed. Writes, shell, delete, network, and tools require review."
        case .safeAutomation:
            "Read and workspace writes are allowed. Delete, shell, and network require review."
        case .autonomous:
            "All local actions are allowed after explicit activation."
        case .custom:
            "Individually toggled permissions."
        }
    }

    static func derived(from permissions: WorkspacePermissions) -> PermissionMode {
        if permissions == .askEveryTime { return .askEveryTime }
        if permissions == .safeAutomation { return .safeAutomation }
        if permissions == .autonomous { return .autonomous }
        return .custom
    }
}

struct WorkspacePermissions: Hashable, Codable, Sendable {
    var read: Bool
    var write: Bool
    var delete: Bool
    var shell: Bool
    var network: Bool
    var tools: Bool

    func grants(_ required: RequiredPermissions) -> Bool {
        if required.contains(.write), !write { return false }
        if required.contains(.delete), !delete { return false }
        if required.contains(.shell), !shell { return false }
        if required.contains(.network), !network { return false }
        return true
    }

    static let askEveryTime = WorkspacePermissions(read: true, write: false, delete: false, shell: false, network: false, tools: false)
    static let safeAutomation = WorkspacePermissions(read: true, write: true, delete: false, shell: false, network: false, tools: false)
    static let autonomous = WorkspacePermissions(read: true, write: true, delete: true, shell: true, network: false, tools: true)

    static func preset(for mode: PermissionMode) -> WorkspacePermissions? {
        switch mode {
        case .askEveryTime: .askEveryTime
        case .safeAutomation: .safeAutomation
        case .autonomous: .autonomous
        case .custom: nil
        }
    }
}

enum TaskStatus: String, Codable, Sendable {
    case draft = "Draft"
    case planned = "Planned"
    case queued = "Queued"
    case running = "Running"
    case complete = "Complete"
    case needsReview = "Needs Review"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

extension TaskStatus {
    var symbol: String {
        switch self {
        case .needsReview: "exclamationmark.triangle.fill"
        case .running: "play.circle"
        case .complete: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        default: "list.bullet.clipboard"
        }
    }

    var tint: Color {
        switch self {
        case .needsReview: .orange
        case .running: .blue
        case .complete: .green
        case .failed: .red
        case .cancelled: .secondary
        default: .blue
        }
    }
}

struct StudioTask: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String
    var prompt: String
    var outputMode: TaskOutputMode
    var status: TaskStatus
    var plan: [String]
    var activity: [ActivityEvent]
    var resultMarkdown: String?
    var citations: [SourceCitation] = []
    var actionItems: [ActionItemRecord] = []
    var fileOperationPlan: FileOperationPlan?
}

struct RequiredPermissions: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let write = RequiredPermissions(rawValue: 1 << 0)
    static let delete = RequiredPermissions(rawValue: 1 << 1)
    static let shell = RequiredPermissions(rawValue: 1 << 2)
    static let network = RequiredPermissions(rawValue: 1 << 3)

    static let none: RequiredPermissions = []
}

struct TaskTemplate: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var prompt: String
    var reviewRequired: Bool
    var outputMode: TaskOutputMode
    var required: RequiredPermissions = .none
}

enum TaskOutputMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case markdown = "Markdown"
    case actionItems = "Action Items"
    case questionAnswer = "Q&A"
    case structuredJSON = "Structured JSON"
    case filePlan = "Review Plan"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .markdown: "doc.text"
        case .actionItems: "checklist"
        case .questionAnswer: "text.bubble"
        case .structuredJSON: "curlybraces"
        case .filePlan: "arrow.triangle.branch"
        }
    }
}

struct ActivityEvent: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String
    var detail: String
    var state: ActivityState
}

struct ChatThread: Identifiable, Codable, Sendable {
    var id = UUID()
    var contextKey: String
    var title: String
    var isTitleEdited = false
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []
}

struct ChatMessage: Identifiable, Codable, Sendable {
    var id = UUID()
    var role: ChatRole
    var markdown: String
    var citations: [SourceCitation] = []
    var filePlan: FileOperationPlan?
    var planApproved: Bool?
    var createdAt = Date()

    var isFailed: Bool {
        markdown.hasPrefix("> [!ERROR]") || markdown.hasPrefix("> [!WARNING]")
    }
}

enum SavedResponseKind: String, Codable, Sendable {
    case chat = "Chat"
    case tool = "Tool"
}

struct SavedResponse: Identifiable, Codable, Sendable {
    var id = UUID()
    var contextKey: String
    var title: String
    var markdown: String
    var kind: SavedResponseKind
    var createdAt = Date()
    var sourceMessageID: UUID?
}

enum ChatRole: String, Codable, Sendable {
    case user = "You"
    case assistant = "Local AI"
}

enum ActivityState: String, Codable, Sendable, Equatable {
    case pending
    case running
    case done
    case review
    case failed

    var symbol: String {
        switch self {
        case .pending: "circle"
        case .running: "play.circle"
        case .done: "checkmark.circle.fill"
        case .review: "exclamationmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .secondary
        case .running: .blue
        case .done: .green
        case .review: .orange
        case .failed: .red
        }
    }
}

struct ModelStatus: Sendable {
    var title: String
    var detail: String
    var isAvailable: Bool
    var contextWindow: Int
    var supportedLanguages: [String] = []
    var currentLocaleSupported = true
    var useCaseAvailability: [String: Bool] = [:]
    var checkedAt = Date()

    var isOnDeviceProvider: Bool {
        isAvailable && !title.localizedCaseInsensitiveContains("mock")
    }
}

enum MCPTransportType: String, Codable, CaseIterable, Identifiable, Sendable {
    case stdio = "stdio"
    case streamableHTTP = "Streamable HTTP"

    var id: String { rawValue }

    var isRemote: Bool {
        self == .streamableHTTP
    }

    var symbol: String {
        switch self {
        case .stdio: "terminal"
        case .streamableHTTP: "globe"
        }
    }
}

struct MCPServerConfig: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var transport: MCPTransportType = .stdio
    var command: String = ""
    var arguments: String = ""
    var url: String = ""
    var headers: [String: String] = [:]
    var createdAt = Date()

    init(id: UUID = UUID(), name: String, transport: MCPTransportType = .stdio, command: String = "", arguments: String = "", url: String = "", headers: [String: String] = [:], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.url = url
        self.headers = headers
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        transport = try c.decodeIfPresent(MCPTransportType.self, forKey: .transport) ?? .stdio
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var detailLine: String {
        switch transport {
        case .stdio:
            var line = command
            if !arguments.isEmpty {
                line += " " + arguments
            }
            return line.isEmpty ? "No command set" : line
        case .streamableHTTP:
            var line = url.isEmpty ? "No URL set" : url
            if !headers.isEmpty {
                line += "  ·  \(headers.count) header\(headers.count == 1 ? "" : "s")"
            }
            return line
        }
    }
}

struct WorkspaceMCPSettings: Codable, Hashable, Sendable {
    var enabledServerIDs: [UUID] = []
}

struct MCPStatus: Sendable {
    var localServers: Int
    var remoteServers: Int
    var enabledTools: Int
}

struct SourceCitation: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var filePath: String
    var location: String?
    var excerpt: String

    var displayTitle: String {
        if let location, !location.isEmpty {
            "\(filePath) - \(location)"
        } else {
            filePath
        }
    }
}

struct TextChunk: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var workspacePath: String
    var filePath: String
    var fileKind: String
    var title: String?
    var content: String
    var ordinal: Int
    var startLine: Int?
    var endLine: Int?
    var pageNumber: Int?
    var slideNumber: Int?
    var obsidianTags: [String]? = nil
    var obsidianWikilinks: [String]? = nil
    var obsidianFrontmatter: [String: String]? = nil
    var tokenEstimate: Int
    var contentHash: String

    var location: String? {
        if let pageNumber {
            return "page \(pageNumber)"
        }
        if let slideNumber {
            return "slide \(slideNumber)"
        }
        guard let startLine else { return nil }
        if let endLine, endLine != startLine {
            return "lines \(startLine)-\(endLine)"
        }
        return "line \(startLine)"
    }
}

struct ObsidianMetadata: Hashable, Codable, Sendable {
    var frontmatter: [String: String] = [:]
    var tags: [String] = []
    var wikilinks: [String] = []
    var aliases: [String] = []
    var bodyText: String
}

struct ObsidianIndexSummary: Hashable, Sendable {
    var noteCount: Int = 0
    var frontmatterFieldCount: Int = 0
    var uniqueTags: [String] = []
    var wikilinkCount: Int = 0
    var uniqueWikilinks: Int = 0
    var topTags: [String] = []
}

struct GitWorkspaceSummary: Hashable, Sendable {
    var branch: String?
    var head: String?
    var changedFiles: Int = 0
    var hasStagedChanges = false
    var hasUnstagedChanges = false
    var hasUntrackedFiles = false
}

struct SemanticRetrievalSummary: Hashable, Sendable {
    var provider: String
    var isAvailable: Bool
    var embeddedChunks: Int = 0
}

struct ChunkIndexSummary: Sendable {
    var chunks: [TextChunk]
    var indexedFiles: Int
    var skippedFiles: Int
    var ignoredFiles: Int = 0
    var persistedURL: URL?
    var searchIndexURL: URL?
    var obsidianSummary: ObsidianIndexSummary?
    var gitSummary: GitWorkspaceSummary?
    var semanticSummary: SemanticRetrievalSummary?

    var tokenEstimate: Int {
        chunks.reduce(0) { $0 + $1.tokenEstimate }
    }
}

struct ContextBudget: Sendable {
    var limit: Int
    var instructions: Int
    var selectedChunks: Int
    var expectedResponse: Int
    var promptOverhead = 320
    var headroom = 0.8

    var fixed: Int {
        instructions + expectedResponse + promptOverhead
    }

    var used: Int {
        fixed + selectedChunks
    }

    var contentBudget: Int {
        max(0, Int(Double(max(0, limit - fixed)) * headroom))
    }

    var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1)
    }

    var retryBudget: ContextBudget {
        ContextBudget(
            limit: limit,
            instructions: instructions,
            selectedChunks: max(1, Int(Double(max(0, limit - fixed)) * 0.4)),
            expectedResponse: expectedResponse,
            promptOverhead: promptOverhead
        )
    }
}

extension Array where Element == TextChunk {
    func truncated(to tokenCap: Int) -> [TextChunk] {
        var selected: [TextChunk] = []
        var tokens = 0
        for chunk in self {
            guard tokens + chunk.tokenEstimate <= tokenCap else { break }
            selected.append(chunk)
            tokens += chunk.tokenEstimate
        }
        return selected
    }
}
