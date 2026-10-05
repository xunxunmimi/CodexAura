// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import CryptoKit
import Foundation

struct CodexAppServerClient {
    let home: URL
    let environment: [String: String]
    let historyStore: TokenHistoryStore
    let executableOverride: URL?

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         historyStore: TokenHistoryStore = TokenHistoryStore(), executable: URL? = nil) {
        self.environment = environment
        self.historyStore = historyStore
        self.executableOverride = executable
        let custom = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty {
            home = URL(fileURLWithPath: NSString(string: custom).expandingTildeInPath, isDirectory: true).standardizedFileURL
        } else { home = homeDirectory.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL }
    }

    func fetchSnapshot(localTokenLogsEnabled: Bool = false) throws -> UsageSnapshot {
        let executable = try locateCodexExecutable()
        var childEnvironment = environment
        childEnvironment["CODEX_HOME"] = home.path // One chosen home for both RPC and optional logs.
        let rpc = try StdioRPCClient(executable: executable, environment: childEnvironment)
        defer { rpc.close() }
        try rpc.send(id: 1, method: "initialize", params: ["clientInfo": ["name": "CodexAura", "version": "0.4.0"]])
        _ = try rpc.response(id: 1, method: "initialize")
        try rpc.send(method: "initialized")
        try rpc.send(id: 2, method: "account/rateLimits/read")
        try rpc.send(id: 3, method: "account/usage/read")
        try rpc.send(id: 4, method: "account/read", params: ["refreshToken": false])
        var warnings: [String] = []
        func result(id: Int, method: String) -> [String: Any]? {
            do { return try rpc.response(id: id, method: method) }
            catch { warnings.append(error.localizedDescription); return nil }
        }
        let rate = result(id: 2, method: "account/rateLimits/read")
        let usage = result(id: 3, method: "account/usage/read")
        let account = result(id: 4, method: "account/read")
        let local = localTokenLogsEnabled ? LocalTokenReader().read(sessionsRoot: home.appendingPathComponent("sessions")) : LocalTokenReader.Reading()
        if local.limited { warnings.append("本地日志读取达到安全上限；统计仅供参考。") }
        return makeSnapshot(rateResult: rate, usageResult: usage, accountResult: account, local: local.totals, warnings: warnings)
    }

    func locateCodexExecutable() throws -> URL {
        if let executableOverride { return executableOverride }
        let explicit = environment["CODEXAURA_CODEX_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty {
            let path = NSString(string: explicit).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: path) else { throw UsageError.codexNotFound }
            return URL(fileURLWithPath: path)
        }
        let candidates = ["/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path]
        let paths = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { String($0) + "/codex" }
        if let path = (candidates + paths).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return URL(fileURLWithPath: path) }
        throw UsageError.codexNotFound
    }

    func makeSnapshot(rateResult: [String: Any]?, usageResult: [String: Any]?, accountResult: [String: Any]?, local: [String: Int64] = [:], warnings: [String] = [], now: Date = Date()) -> UsageSnapshot {
        let bucket = (rateResult?["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any] ?? rateResult?["rateLimits"] as? [String: Any]
        let windows = [bucket?["primary"], bucket?["secondary"]].compactMap { $0 as? [String: Any] }
        let window = windows.max { (UsageNumbers.tokens($0["windowDurationMins"]) ?? 0) < (UsageNumbers.tokens($1["windowDurationMins"]) ?? 0) }
        let duration = UsageNumbers.tokens(window?["windowDurationMins"]).flatMap { $0 > 0 && $0 <= Int64(Int.max) ? Int($0) : nil }
        let used = UsageNumbers.number(window?["usedPercent"]).flatMap { (0...100).contains($0) ? $0 : nil }
        // Bound dates before UI countdown conversion; malformed remote values must not trap.
        let reset = UsageNumbers.number(window?["resetsAt"]).flatMap { (0...32_503_680_000).contains($0) ? Date(timeIntervalSince1970: $0) : nil }
        let daily = parseDailyUsage(usageResult)
        let account = accountResult?["account"] as? [String: Any]
        let identity = (account?["id"] as? String) ?? (account?["email"] as? String)
        let historyKey = identity.flatMap { $0.isEmpty ? nil : "CodexAura.DailyTokenHistory.v2." + fingerprint(home.path + "\n" + $0) }
        var history = historyKey.map { historyStore.load($0) } ?? [:]
        let today = DateKeys.key(for: now)
        let yesterday = DateKeys.key(for: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        func resolved(_ key: String) -> DailyUsage {
            if let value = daily[key] { return DailyUsage(dateKey: key, tokens: value, source: .account) }
            if let value = history[key] { return DailyUsage(dateKey: key, tokens: value, source: .history) }
            if let value = local[key] { return DailyUsage(dateKey: key, tokens: value, source: .localLogs) }
            return DailyUsage(dateKey: key, tokens: nil)
        }
        let todayUsage = resolved(today)
        let yesterdayUsage = resolved(yesterday)
        if let historyKey {
            for (day, value) in daily { history[day] = value } // Explicit zero stays zero, never max with another source.
            history = Dictionary(uniqueKeysWithValues: history.sorted { $0.key < $1.key }.suffix(14))
            historyStore.save(history, key: historyKey)
        }
        let plan = (bucket?["planType"] as? String) ?? (account?["planType"] as? String)
        var messages = warnings
        if used == nil { messages.append("额度数据不可用；没有将缺失值解释为剩余额度。") }
        if todayUsage.tokens == nil || yesterdayUsage.tokens == nil { messages.append("部分日统计不可用；本地日志补充默认关闭。") }
        return UsageSnapshot(usedPercent: used, resetsAt: reset, windowDurationMins: duration, planName: plan?.uppercased(), today: todayUsage, yesterday: yesterdayUsage, updatedAt: now, warning: messages.isEmpty ? nil : messages.joined(separator: "\n"))
    }

    func parseDailyUsage(_ result: [String: Any]?) -> [String: Int64] {
        guard let buckets = result?["dailyUsageBuckets"] as? [[String: Any]] else { return [:] }
        var values: [String: Int64] = [:]
        for bucket in buckets {
            guard let date = bucket["startDate"] as? String,
                  date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                  let tokens = UsageNumbers.tokens(bucket["tokens"]) else { continue }
            values[date] = max(values[date] ?? 0, tokens)
        }
        return values
    }

    private func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Tests use defaults:nil so no real user's preferences are read or written.
final class TokenHistoryStore {
    private let defaults: UserDefaults?
    private var memory: [String: [String: Int64]] = [:]
    init(defaults: UserDefaults? = .standard) { self.defaults = defaults }
    func load(_ key: String) -> [String: Int64] {
        if let defaults { return defaults.dictionary(forKey: key)?.compactMapValues { UsageNumbers.tokens($0) } ?? [:] }
        return memory[key] ?? [:]
    }
    func save(_ values: [String: Int64], key: String) {
        if let defaults { defaults.set(values.mapValues { NSNumber(value: $0) }, forKey: key) }
        else { memory[key] = values }
    }
}
