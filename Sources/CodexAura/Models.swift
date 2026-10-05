// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Foundation

enum DailyUsageSource: String, Equatable {
    case unavailable = "数据不可用"
    case account = "账号服务统计"
    case history = "该账号已观测历史"
    case localLogs = "本地目录估算（可能含多个账号）"
}

struct DailyUsage: Equatable {
    let dateKey: String
    let tokens: Int64?
    var source: DailyUsageSource = .unavailable
}

struct TiboPost: Equatable {
    let id: String
    let text: String
    let translatedText: String?
    let publishedAt: Date
    var url: URL? { URL(string: "https://x.com/thsottiaux/status/\(id)") }
}

struct TiboResetSignal: Equatable {
    var probability: Int?
    var verdict: String
    var reason: String
    var latestPost: TiboPost?
    var signalPostID: String?
    var isLive: Bool
    var updatedAt: Date

    static let checking = TiboResetSignal(probability: nil, verdict: "正在扫描", reason: "读取公开帖子…", latestPost: nil, signalPostID: nil, isLive: false, updatedAt: .distantPast)
    static let disabled = TiboResetSignal(probability: nil, verdict: "已关闭", reason: "雷达默认关闭；启用后会访问 X", latestPost: nil, signalPostID: nil, isLive: false, updatedAt: .distantPast)
    static func unavailable() -> TiboResetSignal {
        TiboResetSignal(probability: nil, verdict: "暂无信号", reason: "公开帖子暂时不可用；没有实时数据", latestPost: nil, signalPostID: nil, isLive: false, updatedAt: Date())
    }
}

struct UsageSnapshot: Equatable {
    var usedPercent: Double?
    var resetsAt: Date?
    var windowDurationMins: Int?
    var planName: String?
    var today: DailyUsage
    var yesterday: DailyUsage
    var updatedAt: Date
    var warning: String?

    static var empty: UsageSnapshot {
        UsageSnapshot(usedPercent: nil, resetsAt: nil, windowDurationMins: nil, planName: nil, today: DailyUsage(dateKey: DateKeys.today, tokens: nil), yesterday: DailyUsage(dateKey: DateKeys.yesterday, tokens: nil), updatedAt: .distantPast, warning: nil)
    }
    var remainingPercent: Double? {
        usedPercent.map { min(max(100 - $0, 0), 100) }
    }
    var windowTitle: String {
        guard let minutes = windowDurationMins else { return "额度窗口未知" }
        if minutes == 10_080 { return "每周额度" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
}

enum DateKeys {
    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static var today: String { key(for: Date()) }
    static var yesterday: String { key(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) }
}

enum UsageError: LocalizedError {
    case codexNotFound
    case launchFailed
    case cancelled
    case timeout
    case disconnected
    case malformedResponse
    case rpc(method: String, code: Int)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到兼容的 Codex 程序；请检查安装位置或 CODEXAURA_CODEX_PATH。"
        case .launchFailed: return "无法启动 Codex 数据服务；请检查程序安装和权限。"
        case .cancelled: return "请求已取消。"
        case .timeout: return "Codex 数据请求超时；请检查版本兼容性和网络。"
        case .disconnected: return "Codex 数据服务已退出；请检查版本兼容性。"
        case .malformedResponse: return "Codex 返回了无法识别的数据。"
        case .rpc(let method, let code): return "\(method) 暂不可用（RPC \(code)）。"
        }
    }
}
