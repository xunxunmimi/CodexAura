// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Foundation

/// Optional folder estimate: stream bytes, decode only token events, never conversations.
struct LocalTokenReader {
    struct Reading {
        var totals: [String: Int64] = [:]
        var limited = false
    }

    func read(sessionsRoot: URL, now: Date = Date()) -> Reading {
        var reading = Reading()
        let start = Calendar.current.startOfDay(for: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        let dayKeys = Set([DateKeys.key(for: now), DateKeys.key(for: yesterday)])
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let files = manager.enumerator(at: sessionsRoot, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return reading }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        var byteBudget = 64 * 1_024 * 1_024
        var fileCount = 0
        for case let url as URL in files {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  (values.contentModificationDate ?? .distantPast) >= yesterday,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            fileCount += 1
            if fileCount > 250 || byteBudget <= 0 { try? handle.close(); reading.limited = true; break }
            defer { try? handle.close() }
            var pending = Data()
            var skippingLongLine = false
            var previousCumulative: Int64?
            func consume(_ line: Data) {
                guard line.range(of: Data("token_count".utf8)) != nil,
                      let text = String(data: line, encoding: .utf8),
                      text.range(of: #""type"\s*:\s*"event_msg""#, options: .regularExpression) != nil,
                      text.range(of: #""type"\s*:\s*"token_count""#, options: .regularExpression) != nil,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["type"] as? String == "event_msg",
                      let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let stamp = object["timestamp"] as? String,
                      let date = fractional.date(from: stamp) ?? basic.date(from: stamp) else { return }
                let last = (info["last_token_usage"] ?? info["lastTokenUsage"]) as? [String: Any]
                let total = (info["total_token_usage"] ?? info["totalTokenUsage"]) as? [String: Any]
                let lastValue = UsageNumbers.tokens(last?["total_tokens"] ?? last?["totalTokens"])
                let cumulative = UsageNumbers.tokens(total?["total_tokens"] ?? total?["totalTokens"])
                let delta: Int64?
                if let cumulative, let previousCumulative, cumulative >= previousCumulative {
                    delta = cumulative - previousCumulative // Repeated cumulative events count zero.
                } else { delta = lastValue }
                if let cumulative { previousCumulative = cumulative }
                let key = DateKeys.key(for: date)
                guard dayKeys.contains(key), let delta, delta >= 0 else { return }
                let sum = (reading.totals[key] ?? 0).addingReportingOverflow(delta)
                if sum.overflow { reading.limited = true; return }
                reading.totals[key] = sum.partialValue
            }
            while byteBudget > 0 {
                guard let chunk = try? handle.read(upToCount: min(65_536, byteBudget)), !chunk.isEmpty else { break }
                byteBudget -= chunk.count
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    if !skippingLongLine, newline <= 262_144 { consume(Data(pending[..<newline])) }
                    else { reading.limited = true }
                    pending.removeSubrange(...newline)
                    skippingLongLine = false
                }
                if pending.count > 262_144 { pending.removeAll(keepingCapacity: true); skippingLongLine = true; reading.limited = true }
            }
            if !pending.isEmpty, !skippingLongLine { consume(pending) }
            if byteBudget <= 0 { reading.limited = true }
        }
        return reading
    }
}

enum UsageNumbers {
    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.doubleValue.isFinite ? value.doubleValue : nil
        }
        if let text = value as? String, let value = Double(text), value.isFinite { return value }
        return nil
    }
    static func tokens(_ value: Any?) -> Int64? {
        guard let value = number(value), value >= 0, value.rounded(.towardZero) == value,
              value < Double(Int64.max) else { return nil }
        return Int64(value)
    }
}
