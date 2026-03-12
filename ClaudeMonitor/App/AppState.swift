import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var rateLimit: RateLimitInfo?
    @Published var activeSession: SessionUsage?
    @Published var projects: [ProjectMetrics] = []
    @Published var isIdle: Bool = true
    @Published var showCostInMenuBar: Bool = UserDefaults.standard.object(forKey: "showCostInMenuBar") as? Bool ?? true
    @Published var refreshInterval: TimeInterval = max(1.0, UserDefaults.standard.double(forKey: "refreshInterval").nonZero ?? 60.0)
    @Published var lastError: String?

    private let rateLimitFetcher = RateLimitFetcher()
    private let sessionWatcher = SessionWatcher()
    private let jsonlParser = JSONLParser()
    private let backupReader = BackupReader()
    private var pollingTimer: Timer?
    private var currentSessionFile: URL?
    private var sleepWakeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupWatcher()
        setupPolling()
        setupSleepWakeHandling()
        refreshAll()
    }

    deinit {
        if let observer = sleepWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        sessionWatcher.stop()
        pollingTimer?.invalidate()
    }

    func refreshAll() {
        refreshBackupData()
        refreshActiveSession()
        fetchRateLimits()
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func setupWatcher() {
        sessionWatcher.start { [weak self] changedURL in
            self?.handleFileChange(changedURL)
        }
    }

    private func setupPolling() {
        $refreshInterval
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.pollingTimer?.invalidate()
                self?.pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    self?.refreshActiveSession()
                    self?.refreshBackupData()
                    self?.fetchRateLimits()
                }
            }
            .store(in: &cancellables)
    }

    private func setupSleepWakeHandling() {
        sleepWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.jsonlParser.reset()
            self?.refreshAll()
        }
    }

    private func fetchRateLimits() {
        Task {
            let info = await rateLimitFetcher.fetch()
            if let info = info {
                self.rateLimit = info
                self.lastError = nil
            } else if self.rateLimit == nil {
                self.lastError = "Could not fetch usage data"
            }
        }
    }

    private func handleFileChange(_ url: URL) {
        if url == currentSessionFile {
            if let update = jsonlParser.incrementalUpdate(fileURL: url) {
                updateSessionWithIncremental(update)
            }
        } else {
            switchToSession(fileURL: url)
        }
    }

    private func refreshActiveSession() {
        guard let (fileURL, projectPath) = sessionWatcher.findActiveSession() else {
            if activeSession != nil {
                activeSession = nil
                isIdle = true
                currentSessionFile = nil
            }
            return
        }

        if fileURL != currentSessionFile {
            switchToSession(fileURL: fileURL, projectPath: projectPath)
        } else {
            if let update = jsonlParser.incrementalUpdate(fileURL: fileURL) {
                updateSessionWithIncremental(update)
            }
        }
    }

    private func switchToSession(fileURL: URL, projectPath: String? = nil) {
        currentSessionFile = fileURL
        let result = jsonlParser.coldStart(fileURL: fileURL)

        let resolvedProjectPath: String
        if let pp = projectPath {
            resolvedProjectPath = pp
        } else {
            let dirName = fileURL.deletingLastPathComponent().lastPathComponent
            resolvedProjectPath = dirName.hasPrefix("-")
                ? dirName.replacingOccurrences(of: "-", with: "/")
                : dirName
        }
        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        let cost = backupReader.readLatestBackupCost(forProject: resolvedProjectPath) ?? 0

        var session = SessionUsage(
            sessionId: sessionId,
            projectPath: resolvedProjectPath,
            model: result.model.isEmpty ? "unknown" : result.model
        )
        session.lastInputTokens = result.lastInputTokens
        session.lastOutputTokens = result.lastOutputTokens
        session.lastCacheCreation = result.lastCacheCreation
        session.lastCacheRead = result.lastCacheRead
        session.totalOutputTokens = result.totalOutputTokens
        session.apiCallCount = result.apiCallCount
        session.costUSD = cost

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let created = attrs[.creationDate] as? Date {
            session.startTime = created
        }
        session.lastUpdateTime = Date()
        activeSession = session
        isIdle = false
    }

    private func updateSessionWithIncremental(_ update: JSONLParser.ParseResult) {
        guard var session = activeSession else { return }

        if update.lastInputTokens > 0 || update.lastOutputTokens > 0 {
            session.lastInputTokens = update.lastInputTokens
            session.lastOutputTokens = update.lastOutputTokens
            session.lastCacheCreation = update.lastCacheCreation
            session.lastCacheRead = update.lastCacheRead
        }

        session.totalOutputTokens += update.totalOutputTokens
        session.apiCallCount += update.apiCallCount
        if !update.model.isEmpty { session.model = update.model }
        session.lastUpdateTime = Date()

        if let cost = backupReader.readLatestBackupCost(forProject: session.projectPath) {
            session.costUSD = cost
        }

        activeSession = session
        isIdle = false
    }

    private func refreshBackupData() {
        let metrics = backupReader.readLatestBackup()
        if !metrics.isEmpty {
            projects = metrics
        }
        if var session = activeSession,
           let cost = metrics.first(where: { $0.path == session.projectPath })?.cost {
            session.costUSD = cost
            activeSession = session
        }
    }
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
