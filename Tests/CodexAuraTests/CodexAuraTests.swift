// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Foundation
import os
import XCTest
@testable import CodexAura

final class CodexAuraTests: XCTestCase {
    func testNativePlacementSeedsRightSideWithoutOverwritingDraggedPosition() throws {
        let suite = "CodexAuraTests.placement." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(987, forKey: "NSStatusItem Preferred Position unrelated-app")
        StatusItemPlacement.prepare(defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: StatusItemPlacement.positionKey), 100)
        XCTAssertTrue(defaults.bool(forKey: StatusItemPlacement.visibleKey))
        defaults.set(240, forKey: StatusItemPlacement.positionKey)
        StatusItemPlacement.prepare(defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: StatusItemPlacement.positionKey), 240)
        StatusItemPlacement.prepare(defaults: defaults, reset: true)
        XCTAssertEqual(defaults.integer(forKey: StatusItemPlacement.positionKey), 100)
        XCTAssertEqual(defaults.integer(forKey: "NSStatusItem Preferred Position unrelated-app"), 987)
    }

    func testStatusItemWaitsForLayoutThenRepairsBeforeDockFallback() {
        var recovery = StatusAnchorRecovery()
        XCTAssertEqual(recovery.update(usable: false, now: 0), .wait)
        XCTAssertEqual(recovery.update(usable: false, now: 0.65), .wait)
        XCTAssertEqual(recovery.update(usable: false, now: 7), .wait)
        XCTAssertEqual(recovery.update(usable: false, now: 8), .recreate)
        XCTAssertEqual(recovery.update(usable: false, now: 10), .wait)
        XCTAssertEqual(recovery.update(usable: false, now: 12), .offerDock)
        XCTAssertEqual(recovery.update(usable: true, now: 13), .ready)
        XCTAssertEqual(recovery.update(usable: false, now: 14), .wait)
        XCTAssertEqual(recovery.update(usable: false, now: 22), .offerDock)
    }

    func testDisplayRelayoutDoesNotImmediatelyTriggerRecovery() {
        var recovery = StatusAnchorRecovery()
        XCTAssertEqual(recovery.update(usable: false, now: 0), .wait)
        recovery.layoutChanged()
        XCTAssertEqual(recovery.update(usable: false, now: 9), .wait)
        XCTAssertEqual(recovery.update(usable: true, now: 10), .ready)
        XCTAssertEqual(recovery.update(usable: false, now: 30), .wait)
        XCTAssertEqual(recovery.update(usable: true, now: 31), .ready)
    }

    func testStaleQuotaOnlyRetainedForMatchingAccount() {
        var previous = client().makeSnapshot(rateResult: rate(), usageResult: daily(100),
            accountResult: account("account-a"))
        previous.resetCreditAvailableCount = 3
        var next = client().makeSnapshot(rateResult: nil, usageResult: daily(200),
            accountResult: account("account-a"))
        next.preserveQuotaIfUnavailable(from: previous)
        XCTAssertEqual(next.remainingPercent, 75)
        XCTAssertEqual(next.today.tokens, 200)
        XCTAssertTrue(next.isQuotaStale)
        XCTAssertEqual(next.quotaUpdatedAt, previous.quotaUpdatedAt)
        XCTAssertNil(next.resetCreditAvailableCount)
        for accountID in ["account-b", ""] {
            var other = client().makeSnapshot(rateResult: nil, usageResult: nil,
                accountResult: account(accountID))
            other.preserveQuotaIfUnavailable(from: previous)
            XCTAssertNil(other.usedPercent)
            XCTAssertFalse(other.isQuotaStale)
        }
        var recovered = client().makeSnapshot(rateResult: rate(used: 40),
            usageResult: nil, accountResult: account("account-a"))
        recovered.preserveQuotaIfUnavailable(from: next)
        XCTAssertEqual(recovered.remainingPercent, 60)
        XCTAssertFalse(recovered.isQuotaStale)
    }

    func testSlowQuotaResponseBeyondOldFourSecondLimit() throws {
        try withTemporaryDirectory { root in
            let executable = try mock("""
import json,sys,time
for line in sys.stdin:
    q=json.loads(line)
    if 'id' not in q: continue
    method=q['method']
    if method=='account/rateLimits/read':
        time.sleep(4.3)
        result={'rateLimits':{'primary':{'usedPercent':30,'windowDurationMins':10080}}}
    elif method=='account/read': result={'account':{'id':'fictional-slow-account'}}
    else: result={}
    print(json.dumps({'id':q['id'],'result':result}),flush=True)
""", root: root)
            let c = CodexAppServerClient(environment: [:], homeDirectory: root,
                historyStore: TokenHistoryStore(defaults: nil), executable: executable)
            XCTAssertEqual(try c.fetchSnapshot().remainingPercent, 70)
        }
    }

    func testNotchedStatusAnchorIgnoresSafeAreaVerticalMismatch() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let safe = CGRect(x: 830, y: 960, width: 682, height: 22)
        XCTAssertTrue(StatusAnchorGeometry.isUsable(
            item: CGRect(x: 1000, y: 946, width: 24, height: 24),
            screen: screen, menuBarHeight: 38, rightSafeArea: safe))
        XCTAssertFalse(StatusAnchorGeometry.isUsable(
            item: CGRect(x: 818, y: 950, width: 24, height: 24),
            screen: screen, menuBarHeight: 38, rightSafeArea: safe))
    }

    func testStatusAnchorRejectsOffscreenAndContentArea() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        for item in [
            CGRect(x: -20, y: 1254, width: 24, height: 24),
            CGRect(x: -1800, y: 500, width: 24, height: 24),
            CGRect.zero
        ] {
            XCTAssertFalse(StatusAnchorGeometry.isUsable(
                item: item, screen: screen, menuBarHeight: 24, rightSafeArea: nil))
        }
        XCTAssertTrue(StatusAnchorGeometry.isUsable(
            item: CGRect(x: -300, y: 1254, width: 24, height: 24),
            screen: screen, menuBarHeight: 24, rightSafeArea: nil))
    }

    private func client(home: String = "/tmp/codexaura-fictional-home", history: TokenHistoryStore = TokenHistoryStore(defaults: nil)) -> CodexAppServerClient {
        CodexAppServerClient(environment: ["CODEX_HOME": home], homeDirectory: URL(fileURLWithPath: "/tmp/codexaura-unused-home"), historyStore: history)
    }
    private func rate(minutes: Int = 300, used: Double = 25) -> [String: Any] {
        ["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": used, "windowDurationMins": minutes]]]]
    }
    private func account(_ id: String) -> [String: Any] { ["account": ["id": id, "type": "chatgpt"]] }
    private func daily(_ value: Int64, day: String = DateKeys.today) -> [String: Any] { ["dailyUsageBuckets": [["startDate": day, "tokens": value]]] }

    func testWindowLabelsUseReturnedDuration() {
        let short = client().makeSnapshot(rateResult: rate(), usageResult: nil, accountResult: nil)
        XCTAssertEqual(short.windowTitle, "5 小时额度")
        XCTAssertEqual(short.remainingPercent, 75)
        let week = client().makeSnapshot(rateResult: rate(minutes: 10_080), usageResult: nil, accountResult: nil)
        XCTAssertEqual(week.windowTitle, "每周额度")
    }

    func testBothQuotaWindowsAndResetCardsPreserveMissingValues() {
        let snapshot = client().makeSnapshot(rateResult: [
            "rateLimits": [
                "primary": ["usedPercent": 99, "windowDurationMins": 300],
                "secondary": ["usedPercent": 12, "windowDurationMins": 10_080]
            ],
            "rateLimitResetCredits": ["availableCount": 2, "credits": [
                ["id": "a", "status": "available", "expiresAt": 1_800_000_000],
                ["id": "b", "status": "used"],
                ["id": "c", "status": "available", "expiresAt": "invalid"]
            ]]
        ], usageResult: nil, accountResult: nil)
        XCTAssertEqual(snapshot.weeklyRemainingPercent, 88)
        XCTAssertEqual(snapshot.fiveHourRemainingPercent, 1)
        XCTAssertEqual(snapshot.resetCreditAvailableCount, 2)
        XCTAssertEqual(snapshot.resetCredits.count, 2)
        XCTAssertNil(snapshot.resetCredits.last?.expiresAt)
        XCTAssertNil(UsageSnapshot.empty.resetCreditAvailableCount)
    }

    func testModernBundledCodexPathsAreConsideredBeforeLegacy() {
        let paths = CodexAppServerClient.executableCandidates(applicationRoots: [URL(fileURLWithPath: "/tmp/fictional-applications")])
        XCTAssertTrue(paths.contains("/tmp/fictional-applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
        XCTAssertTrue(paths[0].contains("codex-cli/CodexCLI.app"))
    }

    func testLatestPostAloneDeterminesRadarScore() {
        let client = TiboSignalClient()
        let latest = TiboPost(id: "2", text: "Tomorrow we bring back the 5h limit", translatedText: nil, publishedAt: Date())
        let older = TiboPost(id: "1", text: "we have reset", translatedText: nil, publishedAt: Date().addingTimeInterval(-60))
        let signal = client.makeSignal(posts: [older, latest], latestPost: latest, scheduledResetAt: nil, isLive: true)
        XCTAssertEqual(signal.probability, 8)
        XCTAssertEqual(signal.signalPostID, "2")
    }

    func testModernXPostBodyMatchesItsOwnID() {
        let client = TiboSignalClient()
        let html = #"bodyText:"Full\npost text",canonicalPath:"/thsottiaux/status/123""#
        XCTAssertEqual(client.parseFullPostText(from: html, id: "123"), "Full\npost text")
        XCTAssertNil(client.parseFullPostText(from: html, id: "456"))
    }
    func testUnknownIsNotZeroOrFullQuota() {
        let snapshot = client().makeSnapshot(rateResult: nil, usageResult: nil, accountResult: nil)
        XCTAssertNil(snapshot.remainingPercent)
        XCTAssertNil(snapshot.today.tokens)
        XCTAssertEqual(snapshot.today.source, .unavailable)
    }
    func testServerZeroOverridesHistoryAndLocalEstimate() {
        let history = TokenHistoryStore(defaults: nil)
        let c = client(history: history)
        _ = c.makeSnapshot(rateResult: rate(), usageResult: daily(999), accountResult: account("a"))
        let result = c.makeSnapshot(rateResult: rate(), usageResult: daily(0), accountResult: account("a"), local: [DateKeys.today: 500])
        XCTAssertEqual(result.today.tokens, 0)
        XCTAssertEqual(result.today.source, .account)
    }
    func testHistoryCannotCrossAccountsOrHomes() {
        let history = TokenHistoryStore(defaults: nil)
        let c = client(history: history)
        _ = c.makeSnapshot(rateResult: rate(), usageResult: daily(123), accountResult: account("a"))
        XCTAssertNil(c.makeSnapshot(rateResult: rate(), usageResult: nil, accountResult: account("b")).today.tokens)
        XCTAssertNil(client(home: "/tmp/codexaura-other-fictional-home", history: history).makeSnapshot(rateResult: rate(), usageResult: nil, accountResult: account("a")).today.tokens)
        XCTAssertEqual(c.makeSnapshot(rateResult: rate(), usageResult: nil, accountResult: account("a")).today.source, .history)
        XCTAssertNil(c.makeSnapshot(rateResult: rate(), usageResult: nil, accountResult: nil).today.tokens)
    }
    func testCustomHomeReplacesDefaultHome() {
        let c = client(home: "/tmp/codexaura-chosen-home")
        XCTAssertEqual(c.home.path, "/tmp/codexaura-chosen-home")
    }
    func testInvalidNumericValuesCannotTrap() {
        for value: Any in [true, -1, 1.25, Double.infinity, Double.nan, Double(Int64.max), "NaN"] { XCTAssertNil(UsageNumbers.tokens(value)) }
        XCTAssertEqual(UsageNumbers.tokens("42"), 42)
        let invalid = client().makeSnapshot(rateResult: rate(used: 200), usageResult: nil, accountResult: nil)
        XCTAssertNil(invalid.remainingPercent)
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codexaura-fictional-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    func testStreamedLogsDoNotDoubleCountRepeatedCumulativeEvents() throws {
        try withTemporaryDirectory { root in
            let stamp = ISO8601DateFormatter().string(from: Date())
            func event(total: Int, last: Int) throws -> String {
                let object: [String: Any] = ["timestamp": stamp, "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["total_tokens": total], "last_token_usage": ["total_tokens": last]]]]
                return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            }
            let lines = ["{\"type\":\"response_item\",\"text\":\"fictional conversation, not parsed\"}", try event(total: 100, last: 10), try event(total: 100, last: 10), try event(total: 130, last: 30)]
            try (lines.joined(separator: "\n") + "\n").write(to: root.appendingPathComponent("fake.jsonl"), atomically: true, encoding: .utf8)
            let result = LocalTokenReader().read(sessionsRoot: root)
            XCTAssertEqual(result.totals[DateKeys.today], 40)
            XCTAssertFalse(result.limited)
        }
    }
    func testLongConversationLineIsSkippedWithinMemoryBound() throws {
        try withTemporaryDirectory { root in
            try (String(repeating: "x", count: 300_000) + "\n").write(to: root.appendingPathComponent("fake.jsonl"), atomically: true, encoding: .utf8)
            let result = LocalTokenReader().read(sessionsRoot: root)
            XCTAssertTrue(result.limited)
            XCTAssertTrue(result.totals.isEmpty)
        }
    }

    private func mock(_ source: String, root: URL) throws -> URL {
        let file = root.appendingPathComponent("mock-codex")
        try ("#!/usr/bin/python3\n" + source).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    func testUnsupportedUsageDoesNotHideSuccessfulQuotaOrExposeRawError() throws {
        try withTemporaryDirectory { root in
            let executable = try mock("""
import json,sys
assert sys.argv[1:]==['app-server']
for line in sys.stdin:
    q=json.loads(line)
    if 'id' not in q: continue
    method=q['method']
    if method=='initialize': result={}
    elif method=='account/rateLimits/read': result={'rateLimits':{'primary':{'usedPercent':25,'windowDurationMins':300}}}
    elif method=='account/read': result={'account':{'id':'fictional-account','type':'chatgpt'}}
    else:
        print(json.dumps({'id':q['id'],'error':{'code':-32601,'message':'fictional-secret-should-not-reach-ui'}}),flush=True)
        continue
    print(json.dumps({'id':q['id'],'result':result}),flush=True)
""", root: root)
            let c = CodexAppServerClient(environment: ["CODEX_HOME": root.appendingPathComponent("isolated-home").path], homeDirectory: root, historyStore: TokenHistoryStore(defaults: nil), executable: executable)
            let snapshot = try c.fetchSnapshot()
            XCTAssertEqual(snapshot.remainingPercent, 75)
            XCTAssertNil(snapshot.today.tokens)
            XCTAssertTrue(snapshot.warning?.contains("RPC -32601") == true)
            XCTAssertFalse(snapshot.warning?.contains("fictional-secret") == true)
        }
    }
    func testCancellationRejectsFutureNetworkTasksWithoutStartingThem() {
        let cancellation = RadarCancellation()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let first = session.dataTask(with: URL(string: "https://example.invalid/fictional")!)
        XCTAssertTrue(cancellation.register(first))
        cancellation.cancel()
        XCTAssertTrue(cancellation.isCancelled)
        let next = session.dataTask(with: URL(string: "https://example.invalid/fictional")!)
        XCTAssertFalse(cancellation.register(next))
        // No task is resumed; this test makes no network request.
    }
    func testTransportDrainsLargeStderrWithoutDeadlock() throws {
        try withTemporaryDirectory { root in
            let executable = try mock("""
import json,sys
for line in sys.stdin:
    q=json.loads(line)
    sys.stderr.write('fictional-stderr-'*20000)
    sys.stderr.flush()
    print(json.dumps({'id':q['id'],'result':{}}),flush=True)
""", root: root)
            let rpc = try StdioRPCClient(executable: executable, environment: [:], timeout: 8)
            defer { rpc.close() }
            try rpc.send(id: 1, method: "initialize")
            _ = try rpc.response(id: 1, method: "initialize", timeout: 6)
        }
    }
    func testUnresponsiveProcessHasBoundedTimeoutAndCleanup() throws {
        try withTemporaryDirectory { root in
            let executable = try mock("""
import json,signal,sys,time
signal.signal(signal.SIGTERM,signal.SIG_IGN)
for line in sys.stdin:
    q=json.loads(line)
    if q['method']=='initialize': print(json.dumps({'id':q['id'],'result':{}}),flush=True)
    else: time.sleep(30)
""", root: root)
            let rpc = try StdioRPCClient(executable: executable, environment: [:], timeout: 8)
            try rpc.send(id: 1, method: "initialize")
            _ = try rpc.response(id: 1, method: "initialize", timeout: 6)
            let began = Date()
            try rpc.send(id: 2, method: "fictional/hang")
            XCTAssertThrowsError(try rpc.response(id: 2, method: "fictional/hang", timeout: 0.2))
            rpc.close()
            XCTAssertLessThan(Date().timeIntervalSince(began), 2)
        }
    }
}

extension CodexAuraTests {
    @MainActor
    func testTimeoutRetainsLastSnapshotAndRecoveryClearsStale() async throws {
        let count = OSAllocatedUnfairLock(initialState: 0)
        let store = UsageStore(defaults: nil, fetchUsage: { _ in
            let attempt = count.withLock { value in value += 1; return value }
            if attempt == 2 { throw UsageError.timeout }
            var snapshot = UsageSnapshot.empty
            snapshot.usedPercent = attempt == 1 ? 30 : 40
            snapshot.accountKey = "synthetic-account"
            snapshot.updatedAt = Date(timeIntervalSince1970: 100)
            snapshot.resetCreditAvailableCount = 3
            return snapshot
        })
        store.refresh()
        try await waitForUsageToFinish(store)
        store.refresh()
        try await waitForUsageToFinish(store)
        XCTAssertEqual(store.snapshot.remainingPercent, 70)
        XCTAssertTrue(store.snapshot.isQuotaStale)
        XCTAssertEqual(store.snapshot.updatedAt, Date(timeIntervalSince1970: 100))
        XCTAssertNil(store.snapshot.resetCreditAvailableCount)
        XCTAssertTrue(store.errorMessage?.contains("非实时") == true)
        store.refresh()
        try await waitForUsageToFinish(store)
        XCTAssertEqual(store.snapshot.remainingPercent, 60)
        XCTAssertFalse(store.snapshot.isQuotaStale)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    private func waitForUsageToFinish(_ store: UsageStore) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while store.isRefreshing, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.isRefreshing, "The offline usage refresh should finish promptly")
    }

    @MainActor
    func testLogSwitchCancelsAndRetriesRadarWithoutDiscardingCompletedThrottle() async throws {
        let firstStarted = expectation(description: "first offline radar started")
        let firstCancelled = expectation(description: "first offline radar observed cancellation")
        let firstReturned = expectation(description: "old offline radar returned")
        let replacementApplied = expectation(description: "replacement radar applied immediately")
        let obsoleteApplied = expectation(description: "cancelled result must never appear")
        obsoleteApplied.isInverted = true
        let probe = UsageStoreProbe(firstStarted: firstStarted, firstCancelled: firstCancelled,
                                    firstReturned: firstReturned)
        defer { probe.releaseFirst.signal() }
        let store = UsageStore(defaults: nil, fetchUsage: { try probe.usage(localEnabled: $0) },
                               fetchSignal: { try probe.radar(cancellation: $0, translate: $2) })
        let observation = store.$tiboSignal.sink { signal in
            if signal.reason == "live-2" { replacementApplied.fulfill() }
            if signal.reason == "obsolete" { obsoleteApplied.fulfill() }
        }
        defer { observation.cancel() }

        store.setRadarEnabled(true)
        await fulfillment(of: [firstStarted], timeout: 3)
        XCTAssertEqual(probe.radarCount, 1)
        store.setLocalTokenLogsEnabled(true)
        await fulfillment(of: [firstCancelled, replacementApplied], timeout: 3)
        XCTAssertEqual(probe.radarCount, 2, "A cancelled attempt cannot leave a thirty-minute wait")
        XCTAssertEqual(probe.usageFlags, [false, true])
        XCTAssertEqual(probe.translationFlags, [false, false])
        XCTAssertTrue(store.radarEnabled)
        XCTAssertFalse(store.translationEnabled)
        XCTAssertTrue(store.localTokenLogsEnabled)

        probe.releaseFirst.signal()
        await fulfillment(of: [firstReturned], timeout: 3)
        await fulfillment(of: [obsoleteApplied], timeout: 0.15)
        XCTAssertEqual(store.tiboSignal.reason, "live-2")

        store.setLocalTokenLogsEnabled(false)
        try await waitForUsageToFinish(store)
        XCTAssertEqual(probe.radarCount, 2, "A completed radar attempt keeps its normal throttle")
        XCTAssertEqual(probe.usageFlags, [false, true, false])
        XCTAssertEqual(store.tiboSignal.reason, "live-2")
    }

    @MainActor
    func testLogAndTranslationSettingsCannotEnableDisabledRadar() async throws {
        let probe = UsageStoreProbe()
        let store = UsageStore(defaults: nil, fetchUsage: { try probe.usage(localEnabled: $0) },
                               fetchSignal: { try probe.radar(cancellation: $0, translate: $2) })
        XCTAssertFalse(store.localTokenLogsEnabled)
        XCTAssertFalse(store.radarEnabled)
        XCTAssertFalse(store.translationEnabled)
        store.setTranslationEnabled(true)
        try await waitForUsageToFinish(store)
        store.setLocalTokenLogsEnabled(true)
        try await waitForUsageToFinish(store)
        XCTAssertTrue(store.localTokenLogsEnabled)
        XCTAssertTrue(store.translationEnabled)
        XCTAssertFalse(store.radarEnabled)
        store.setLocalTokenLogsEnabled(false)
        try await waitForUsageToFinish(store)
        XCTAssertTrue(store.translationEnabled, "Log settings cannot silently change translation consent")
        XCTAssertFalse(store.radarEnabled)
        XCTAssertEqual(store.tiboSignal, .disabled)
        XCTAssertEqual(probe.usageFlags, [false, true, false])
        XCTAssertEqual(probe.radarCount, 0, "Neither switch can start an external radar request")
    }
}

/// Models an in-flight fetch without starting URLSession, Codex, or a real account.
private final class UsageStoreProbe: Sendable {
    private struct State: Sendable {
        var usageFlags: [Bool] = []
        var translationFlags: [Bool] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let firstStarted: XCTestExpectation?
    private let firstCancelled: XCTestExpectation?
    private let firstReturned: XCTestExpectation?
    let releaseFirst = DispatchSemaphore(value: 0)

    init(firstStarted: XCTestExpectation? = nil, firstCancelled: XCTestExpectation? = nil,
         firstReturned: XCTestExpectation? = nil) {
        self.firstStarted = firstStarted
        self.firstCancelled = firstCancelled
        self.firstReturned = firstReturned
    }
    var usageFlags: [Bool] { state.withLock { $0.usageFlags } }
    var translationFlags: [Bool] { state.withLock { $0.translationFlags } }
    var radarCount: Int { state.withLock { $0.translationFlags.count } }

    func usage(localEnabled: Bool) throws -> UsageSnapshot {
        state.withLock { $0.usageFlags.append(localEnabled) }
        return .empty
    }
    func radar(cancellation: RadarCancellation, translate: Bool) throws -> TiboResetSignal {
        let count = state.withLock { value in
            value.translationFlags.append(translate)
            return value.translationFlags.count
        }
        var signal = TiboResetSignal.unavailable()
        signal.reason = "live-\(count)"
        if count == 1, let firstStarted {
            firstStarted.fulfill()
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while !cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < deadline { usleep(1_000) }
            guard cancellation.isCancelled else { throw UsageError.timeout }
            firstCancelled?.fulfill()
            guard releaseFirst.wait(timeout: .now() + 3) == .success else { throw UsageError.timeout }
            signal.reason = "obsolete"
            firstReturned?.fulfill()
        }
        return signal
    }
}
