import Foundation

struct ActionItemRecord: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var title: String
    var owner: String?
    var dueDate: String?
    var sourcePath: String
    var sourceLocation: String?
    var confidence: Double
}

struct WorkspaceSummaryRecord: Hashable, Codable, Sendable {
    var title: String
    var overview: String
    var keyThemes: [String]
    var sourcePaths: [String]
    var openQuestions: [String]
}

struct RenamePlanRecord: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var currentPath: String
    var proposedPath: String
    var reason: String
    var riskLevel: PlanRiskLevel
}

enum PlanRiskLevel: String, Hashable, Codable, Sendable {
    case low
    case medium
    case high
}

struct FileOperationPlan: Hashable, Codable, Sendable {
    var summary: String
    var operations: [RenamePlanRecord]
    var requiresApproval: Bool
}
