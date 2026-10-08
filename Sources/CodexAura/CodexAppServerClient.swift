// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import CryptoKit
import AppKit
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
        let rpc = try StdioRPCClient(executable: executable, environment: childEnvironment, timeout: 45)
        defer { rpc.close() }
        try rpc.send(id: 1, method: "initialize", params: ["clientInfo": ["name": "CodexAura", "version": "0.4.5"]])
        _ = try rpc.response(id: 1, method: "initialize", timeout: 8)
        try rpc.send(method: "initialized")
        try rpc.send(id: 2, method: "account/rateLimits/read")
        try rpc.send(id: 3, method: "account/usage/read")
        try rpc.send(id: 4, method: "account/read", params: ["refreshToken": false])
        var warnings: [String] = []
        func result(id: Int, method: String) -> [String: Any]? {
            do { return try rpc.response(id: id, method: method, timeout: id == 2 ? 25 : 5) }
            catch {
                if !warnings.contains(error.localizedDescription) { warnings.append(error.localizedDescription) }
                return nil
            }
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
        let candidates = Self.executableCandidates(applicationRoots: [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]) + ["com.openai.codex", "com.openai.chat"].compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }.flatMap { Self.bundledExecutableCandidates(in: $0) }
          + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path]
        let paths = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { String($0) + "/codex" }
        if let path = (candidates + paths).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return URL(fileURLWithPath: path) }
        throw UsageError.codexNotFound
    }

    static func bundledExecutableCandidates(in application: URL) -> [String] {
        ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
         "Contents/Resources/codex-cli/bin/codex",
         "Contents/Resources/codex"].map { application.appendingPathComponent($0).path }
    }

    static func executableCandidates(applicationRoots: [URL]) -> [String] {
        applicationRoots.flatMap { root in
            ["Codex.app", "ChatGPT.app"].flatMap {
                bundledExecutableCandidates(in: root.appendingPathComponent($0))
            }
        }
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
        var snapshot = UsageSnapshot(usedPercent: used, resetsAt: reset, windowDurationMins: duration, planName: plan?.uppercased(), today: todayUsage, yesterday: yesterdayUsage, updatedAt: now, warning: messages.isEmpty ? nil : messages.joined(separator: "\n"))
        snapshot.accountKey = historyKey
        snapshot.quotaUpdatedAt = used == nil ? nil : now
        snapshot.windows = windows.compactMap { value in
            guard let minutes = UsageNumbers.tokens(value["windowDurationMins"]),
                  minutes > 0, minutes <= 525_600 else { return nil }
            return QuotaWindow(
                usedPercent: UsageNumbers.number(value["usedPercent"]).flatMap { (0...100).contains($0) ? $0 : nil },
                resetsAt: Self.safeDate(value["resetsAt"]), durationMins: Int(minutes))
        }.sorted { $0.durationMins > $1.durationMins }
        if let payload = rateResult?["rateLimitResetCredits"] as? [String: Any] {
            snapshot.resetCreditAvailableCount = UsageNumbers.tokens(payload["availableCount"]).flatMap {
                $0 <= Int64(Int.max) ? Int($0) : nil
            }
            snapshot.resetCredits = (payload["credits"] as? [[String: Any]] ?? []).enumerated().compactMap { index, credit in
                let status = (credit["status"] as? String)?.lowercased()
                guard status == nil || status == "available" else { return nil }
                return RateLimitResetCredit(id: (credit["id"] as? String) ?? String(index),
                    title: (credit["title"] as? String) ?? "Full reset", expiresAt: Self.safeDate(credit["expiresAt"]))
            }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        }
        return snapshot
    }

    static func safeDate(_ value: Any?) -> Date? {
        UsageNumbers.number(value).flatMap {
            (0...32_503_680_000).contains($0) ? Date(timeIntervalSince1970: $0) : nil
        }
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
