import Foundation

// MARK: - Root backup config

struct BackupConfig: Decodable {
    let projects: [String: ProjectConfig]?
}

// MARK: - Per-project config

struct ProjectConfig: Decodable {
    let lastCost: Double?
    let lastSessionId: String?
    let lastModelUsage: [String: ModelUsageEntry]?
    let lastTotalInputTokens: Int?
    let lastTotalOutputTokens: Int?
}

// MARK: - Model usage entry (JSON keys are camelCase, matching Swift property names)

struct ModelUsageEntry: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    let costUSD: Double?
}
