// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Foundation
import os

struct TiboSignalClient {
    private let cancellation: RadarCancellation
    init(cancellation: RadarCancellation = RadarCancellation()) { self.cancellation = cancellation }
    private let profileURL = URL(string: "https://x.com/thsottiaux")!

    func fetchSignal(scheduledResetAt: Date?, translate: Bool = false) throws -> TiboResetSignal {
        var request = URLRequest(url: profileURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/139 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let data = try synchronousData(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw UsageError.malformedResponse
        }

        var posts = parsePosts(from: html)
        guard !posts.isEmpty else { throw UsageError.malformedResponse }
        posts.sort { $0.publishedAt > $1.publishedAt }

        var latest = posts[0]
        if let fullText = fetchFullPostText(id: latest.id), !fullText.isEmpty {
            latest = TiboPost(
                id: latest.id,
                text: fullText,
                translatedText: nil,
                publishedAt: latest.publishedAt
            )
            posts[0] = latest
        }
        guard !latest.text.isEmpty else { throw UsageError.malformedResponse }
        let translated = translate ? translateToChinese(latest.text) : nil
        let translatedLatest = TiboPost(
            id: latest.id,
            text: latest.text,
            translatedText: translated,
            publishedAt: latest.publishedAt
        )
        return makeSignal(
            posts: posts,
            latestPost: translatedLatest,
            scheduledResetAt: scheduledResetAt,
            isLive: true
        )
    }

    func parsePosts(from html: String) -> [TiboPost] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var legacyTextByID: [String: String] = [:]

        // Keep support for X's older server-rendered profile cards so already
        // cached page variants still retain their preview text.
        let legacyPattern = #"data-href="/thsottiaux/status/([0-9]+)"[\s\S]*?<meta content="([^"]*)" itemProp="text""#
        if let regex = try? NSRegularExpression(pattern: legacyPattern) {
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges == 3,
                      let idRange = Range(match.range(at: 1), in: html),
                      let textRange = Range(match.range(at: 2), in: html) else { continue }
                legacyTextByID[String(html[idRange])] = decodeHTMLEntities(String(html[textRange]))
            }
        }

        // X's current profile HTML no longer emits the old itemProp="text"
        // meta node. Discover posts from their stable status URLs, then load
        // the complete body from the newest post's own page.
        let idPattern = #"(?:data-href|href)="/thsottiaux/status/([0-9]+)""#
        guard let regex = try? NSRegularExpression(pattern: idPattern) else { return [] }
        var seen = Set<String>()

        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges == 2,
                  let idRange = Range(match.range(at: 1), in: html) else { return nil }
            let id = String(html[idRange])
            guard seen.insert(id).inserted,
                  let publishedAt = dateFromSnowflake(id) else { return nil }
            return TiboPost(
                id: id,
                text: legacyTextByID[id] ?? "",
                translatedText: nil,
                publishedAt: publishedAt
            )
        }
    }

    private func fetchFullPostText(id: String) -> String? {
        guard let url = URL(string: "https://x.com/thsottiaux/status/\(id)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/139 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let data = try? synchronousData(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return parseFullPostText(from: html, id: id)
    }

    func parseFullPostText(from html: String, id: String) -> String? {
        // X's current status page exposes the complete focal post here.
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        let bodyTextPattern = #"bodyText:"((?:\\.|[^"\\])*)",canonicalPath:"/thsottiaux/status/"#
            + escapedID
            + #"""#
        if let value = capturedSerializedString(in: html, pattern: bodyTextPattern) {
            return value
        }

        let encodedID = Data("Tweet:\(id)".utf8).base64EncodedString()
        let noteAnchor = NSRegularExpression.escapedPattern(
            for: "\"client:\(encodedID):note_tweet\""
        )
        let notePattern = noteAnchor
            + #":\$R\[[0-9]+\]=\{[\s\S]{0,4000}?__typename:"NoteTweet",text:"((?:\\.|[^"\\])*)""#

        if let value = capturedSerializedString(in: html, pattern: notePattern) {
            return value
        }

        // Ordinary posts do not have NoteTweet data. Their focal tweet's
        // full_text is still more reliable than the profile card summary.
        let detailsAnchor = NSRegularExpression.escapedPattern(
            for: "\"client:\(encodedID):details\""
        )
        let detailsPattern = detailsAnchor
            + #":\$R\[[0-9]+\]=\{[\s\S]{0,2500}?full_text:"((?:\\.|[^"\\])*)""#
        return capturedSerializedString(in: html, pattern: detailsPattern)
    }

    private func capturedSerializedString(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
              ),
              match.numberOfRanges == 2,
              let range = Range(match.range(at: 1), in: source) else { return nil }

        let escaped = String(source[range])
        guard let data = ("\"" + escaped + "\"").data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
              ) as? String else { return nil }
        let text = decodeHTMLEntities(decoded).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func makeSignal(
        posts: [TiboPost],
        latestPost: TiboPost,
        scheduledResetAt: Date?,
        isLive: Bool
    ) -> TiboResetSignal {
        let now = Date()
        let age = max(now.timeIntervalSince(latestPost.publishedAt), 0)
        let recent = age < 14 * 86_400
        let base = baseScore(for: latestPost.text)
        var probability = recent ? 8 + (base.score - 8) * pow(0.5, age / 3_600 / 48) : 8

        if let scheduledResetAt {
            let hoursToScheduledReset = scheduledResetAt.timeIntervalSince(now) / 3_600
            if hoursToScheduledReset > 0, hoursToScheduledReset <= 24 {
                probability -= 5
            }
        }

        let rounded = Int(min(max(probability.rounded(), 3), 99))
        let verdict: String
        switch rounded {
        case 80...: verdict = "强信号"
        case 60...: verdict = "中等信号"
        case 35...: verdict = "弱信号"
        default: verdict = "暂时平静"
        }

        return TiboResetSignal(
            probability: rounded,
            verdict: verdict,
            reason: recent ? base.reason : "最新帖子超过 14 天，没有近期信号",
            latestPost: latestPost,
            signalPostID: recent ? latestPost.id : nil,
            isLive: isLive,
            updatedAt: now
        )
    }

    private func baseScore(for text: String) -> (score: Double, reason: String) {
        let value = text.lowercased()
        let negativePhrases = ["no reset", "won't reset", "will not reset", "not resetting"]
        if negativePhrases.contains(where: value.contains) {
            return (5, "Tibo 明确否定了近期重置")
        }

        let confirmedPhrases = ["reset button pressed", "we have reset", "i have reset", "reset is done", "reset has been propagated", "reset was propagated", "limits have been reset"]
        if confirmedPhrases.contains(where: value.contains) {
            return (99, "Tibo 已明确表示按下了重置按钮")
        }

        let scheduledPhrases = ["will reset", "i'll reset", "reset tomorrow", "reset again tomorrow"]
        if scheduledPhrases.contains(where: value.contains) {
            return (97, "Tibo 明确预告了即将重置")
        }

        if value.contains("reset button"), value.contains("gifted") || value.contains("new") || value.contains("fancy") {
            return (88, "Tibo 刚晒出新的 reset button，强信号")
        }
        if value.contains("reset button") {
            return (82, "Tibo 再次提到 reset button")
        }
        if value.contains("occasional resets") {
            return (64, "Tibo 将 occasional resets 列为 Codex 特性")
        }
        if value.contains("reset") {
            return (52, "Tibo 的帖子出现了 reset 关键词")
        }
        return (8, "这条帖子没有明显 reset 信号")
    }

    private func translateToChinese(_ text: String) -> String? {
        guard var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "zh-CN"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("CodexAura/0.4.1", forHTTPHeaderField: "User-Agent")
        guard let data = try? synchronousData(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else { return nil }

        let translated = segments.compactMap { segment -> String? in
            guard let values = segment as? [Any], let value = values.first as? String else { return nil }
            return value
        }.joined()
        return translated.isEmpty ? nil : translated
    }

    private func synchronousData(for request: URLRequest) throws -> Data {
        guard !cancellation.isCancelled else { throw UsageError.cancelled }
        let semaphore = DispatchSemaphore(value: 0)
        var output: Result<Data, Error>?
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                output = .failure(error)
                return
            }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let data else {
                output = .failure(UsageError.malformedResponse)
                return
            }
            output = .success(data)
        }
        guard cancellation.register(task) else { throw UsageError.cancelled }
        defer { cancellation.clearTask() }
        task.resume()

        guard semaphore.wait(timeout: .now() + request.timeoutInterval + 2) == .success,
              let output else {
            throw UsageError.timeout
        }
        return try output.get()
    }

    private func dateFromSnowflake(_ id: String) -> Date? {
        guard let value = UInt64(id) else { return nil }
        let milliseconds = (value >> 22) + 1_288_834_974_657
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#10;", with: "\n")
    }
}

/// Turning an external feature off cancels its active request and gates later requests.
final class RadarCancellation: Sendable {
    private struct State: Sendable {
        var cancelled = false
        var task: URLSessionDataTask?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    var isCancelled: Bool { state.withLock { $0.cancelled } }
    func register(_ task: URLSessionDataTask) -> Bool {
        let accepted = state.withLock { value in
            guard !value.cancelled else { return false }
            value.task = task
            return true
        }
        if !accepted { task.cancel() }
        return accepted
    }
    func clearTask() { state.withLock { $0.task = nil } }
    func cancel() {
        let active = state.withLock { value in
            value.cancelled = true
            let active = value.task
            value.task = nil
            return active
        }
        active?.cancel()
    }
}
