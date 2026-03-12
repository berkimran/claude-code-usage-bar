import Foundation

struct RateLimitInfo {
    // Primary (representative claim - usually 5h)
    var status: String = "unknown"             // allowed, allowed_warning, rejected
    var representativeClaim: String = ""        // e.g. "five_hour"

    // 5-hour window
    var fiveHourUtilization: Double = 0        // 0.0 - 1.0
    var fiveHourReset: Date?
    var fiveHourStatus: String = ""

    // 7-day window
    var sevenDayUtilization: Double = 0        // 0.0 - 1.0
    var sevenDayReset: Date?
    var sevenDayStatus: String = ""

    // Overage
    var overageStatus: String = ""
    var overageDisabledReason: String = ""

    var lastUpdated: Date = Date()

    // Computed
    var primaryPercentage: Double {
        fiveHourUtilization * 100
    }

    var weeklyPercentage: Double {
        sevenDayUtilization * 100
    }

    var fiveHourResetString: String {
        guard let reset = fiveHourReset else { return "--" }
        let remaining = reset.timeIntervalSince(Date())
        if remaining <= 0 { return "now" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var sevenDayResetString: String {
        guard let reset = sevenDayReset else { return "--" }
        let remaining = reset.timeIntervalSince(Date())
        if remaining <= 0 { return "now" }
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        return "\(hours)h"
    }

    var isWarning: Bool {
        status == "allowed_warning" || fiveHourStatus == "allowed_warning"
    }

    var isRejected: Bool {
        status == "rejected"
    }
}
