import Foundation

struct SessionUsage {
    let sessionId: String
    let projectPath: String
    var model: String

    // Last API call (context window state)
    var lastInputTokens: Int = 0
    var lastOutputTokens: Int = 0
    var lastCacheCreation: Int = 0
    var lastCacheRead: Int = 0

    // Cumulative (session total)
    var totalOutputTokens: Int = 0
    var apiCallCount: Int = 0
    var costUSD: Double = 0.0

    // Session timing
    var startTime: Date?
    var lastUpdateTime: Date?

    // Computed
    var contextTokens: Int {
        lastInputTokens + lastOutputTokens + lastCacheCreation + lastCacheRead
    }

    var contextWindowSize: Int {
        contextTokens > Constants.defaultContextWindow
            ? Constants.extendedContextWindow
            : Constants.defaultContextWindow
    }

    var contextPercentage: Double {
        guard contextWindowSize > 0 else { return 0 }
        return Double(contextTokens) / Double(contextWindowSize) * 100
    }

    var isCompacted: Bool {
        // Detect if context dropped significantly (heuristic: >50% drop from previous)
        false // Will be set externally when comparing with previous state
    }

    var durationString: String {
        guard let start = startTime else { return "--" }
        let elapsed = (lastUpdateTime ?? Date()).timeIntervalSince(start)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var shortProjectPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if projectPath.hasPrefix(home) {
            return "~" + projectPath.dropFirst(home.count)
        }
        return projectPath
    }
}

struct ProjectMetrics: Identifiable {
    var id: String { path }
    let path: String
    var cost: Double
    var lastSessionId: String?
    var modelUsage: [String: ModelUsageEntry]?

    var shortPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
