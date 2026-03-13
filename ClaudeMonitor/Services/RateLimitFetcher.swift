import Foundation
import Security

final class RateLimitFetcher {
    private var accessToken: String?
    private var lastFetchTime: Date = .distantPast
    private let minimumFetchInterval: TimeInterval = 60
    private let logFile: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/claude-monitor.log")

    private lazy var session: URLSession = {
        URLSession(configuration: .ephemeral)
    }()

    init() {
        loadToken()
    }

    func fetch() async -> RateLimitInfo? {
        guard Date().timeIntervalSince(lastFetchTime) >= minimumFetchInterval else {
            return nil
        }

        if accessToken == nil { loadToken() }
        guard let token = accessToken else {
            writeLog("ERROR no credentials in keychain")
            return nil
        }

        lastFetchTime = Date()
        return await doFetch(token: token)
    }

    func reloadToken() {
        loadToken()
    }

    private func loadToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            accessToken = nil
            return
        }

        accessToken = token
    }

    private func doFetch(token: String) async -> RateLimitInfo? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = jsonData

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode != 200 {
                writeLog("ERROR HTTP \(httpResponse.statusCode)")
            }
            let info = parseHeaders(httpResponse)
            writeLog("OK 5h=\(String(format: "%.1f%%", info.primaryPercentage)) 7d=\(String(format: "%.1f%%", info.weeklyPercentage)) status=\(info.status)")
            return info
        } catch {
            writeLog("ERROR \(error.localizedDescription)")
            return nil
        }
    }

    private func writeLog(_ message: String) {
        let fm = FileManager.default
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if fm.fileExists(atPath: logFile.path) {
            // Truncate if over 512KB
            if let attrs = try? fm.attributesOfItem(atPath: logFile.path),
               let size = attrs[.size] as? UInt64, size > 512_000 {
                try? "".write(to: logFile, atomically: false, encoding: .utf8)
            }
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            fm.createFile(atPath: logFile.path, contents: data)
        }
    }

    private func parseHeaders(_ response: HTTPURLResponse) -> RateLimitInfo {
        let headers = response.allHeaderFields

        func header(_ name: String) -> String? {
            for (key, value) in headers {
                if let k = key as? String, k.lowercased() == name.lowercased() {
                    return value as? String
                }
            }
            return nil
        }

        var info = RateLimitInfo()

        info.status = header("anthropic-ratelimit-unified-status") ?? "unknown"
        info.representativeClaim = header("anthropic-ratelimit-unified-representative-claim") ?? ""

        if let util = header("anthropic-ratelimit-unified-5h-utilization"), let val = Double(util) {
            info.fiveHourUtilization = val
        }
        if let reset = header("anthropic-ratelimit-unified-5h-reset"), let epoch = TimeInterval(reset) {
            info.fiveHourReset = Date(timeIntervalSince1970: epoch)
        }
        info.fiveHourStatus = header("anthropic-ratelimit-unified-5h-status") ?? ""

        if let util = header("anthropic-ratelimit-unified-7d-utilization"), let val = Double(util) {
            info.sevenDayUtilization = val
        }
        if let reset = header("anthropic-ratelimit-unified-7d-reset"), let epoch = TimeInterval(reset) {
            info.sevenDayReset = Date(timeIntervalSince1970: epoch)
        }
        info.sevenDayStatus = header("anthropic-ratelimit-unified-7d-status") ?? ""

        info.overageStatus = header("anthropic-ratelimit-unified-overage-status") ?? ""
        info.overageDisabledReason = header("anthropic-ratelimit-unified-overage-disabled-reason") ?? ""
        info.lastUpdated = Date()

        return info
    }
}
