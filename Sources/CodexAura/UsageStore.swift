// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var tiboSignal = TiboResetSignal.disabled
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var localTokenLogsEnabled: Bool
    @Published private(set) var radarEnabled: Bool
    @Published private(set) var translationEnabled: Bool
    private let defaults: UserDefaults?
    private let fetchUsage: @Sendable (Bool) throws -> UsageSnapshot
    private let fetchSignal: @Sendable (RadarCancellation, Date?, Bool) throws -> TiboResetSignal
    private var timer: Timer?
    private var hasStarted = false
    private var lastSignalFetchAt = Date.distantPast
    private var settingsRevision = 0
    private var radarCancellation: RadarCancellation?

    // Tests supply memory-only settings and offline fetchers; production keeps the same clients.
    init(defaults: UserDefaults? = .standard,
         fetchUsage: @escaping @Sendable (Bool) throws -> UsageSnapshot = {
             try CodexAppServerClient().fetchSnapshot(localTokenLogsEnabled: $0)
         },
         fetchSignal: @escaping @Sendable (RadarCancellation, Date?, Bool) throws -> TiboResetSignal = {
             try TiboSignalClient(cancellation: $0).fetchSignal(scheduledResetAt: $1, translate: $2)
         }) {
        self.defaults = defaults
        self.fetchUsage = fetchUsage
        self.fetchSignal = fetchSignal
        localTokenLogsEnabled = defaults?.bool(forKey: "CodexAura.LocalLogsEnabled.v1") ?? false
        radarEnabled = defaults?.bool(forKey: "CodexAura.RadarEnabled.v1") ?? false
        translationEnabled = defaults?.bool(forKey: "CodexAura.TranslationEnabled.v1") ?? false
        if radarEnabled { tiboSignal = .checking }
    }

    func setLocalTokenLogsEnabled(_ value: Bool) {
        if let cancellation = radarCancellation {
            cancellation.cancel()
            radarCancellation = nil
            lastSignalFetchAt = .distantPast // The cancelled attempt must not block a replacement.
            if radarEnabled { tiboSignal = .checking }
        }
        localTokenLogsEnabled = value
        defaults?.set(value, forKey: "CodexAura.LocalLogsEnabled.v1")
        settingsRevision += 1
        snapshot = .empty
        refresh()
    }
    func setRadarEnabled(_ value: Bool) {
        radarCancellation?.cancel()
        radarCancellation = nil
        radarEnabled = value
        defaults?.set(value, forKey: "CodexAura.RadarEnabled.v1")
        settingsRevision += 1
        lastSignalFetchAt = .distantPast
        tiboSignal = value ? .checking : .disabled
        refresh()
    }
    func setTranslationEnabled(_ value: Bool) {
        radarCancellation?.cancel()
        radarCancellation = nil
        translationEnabled = value
        defaults?.set(value, forKey: "CodexAura.TranslationEnabled.v1")
        settingsRevision += 1
        lastSignalFetchAt = .distantPast
        if !value { tiboSignal.latestPost = nil }
        refresh()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        let localEnabled = localTokenLogsEnabled
        let fetchRadar = radarEnabled && Date().timeIntervalSince(lastSignalFetchAt) >= 1_800
        let translate = translationEnabled
        let revision = settingsRevision
        let fetchUsage = self.fetchUsage
        DispatchQueue.global(qos: .utility).async {
            let usage = Result { try fetchUsage(localEnabled) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.settingsRevision == revision else { self.refresh(); return }
                switch usage {
                case .success(var snapshot):
                    snapshot.preserveQuotaIfUnavailable(from: self.snapshot)
                    self.snapshot = snapshot
                    self.errorMessage = snapshot.warning
                case .failure(let error):
                    if case UsageError.timeout = error, self.snapshot.usedPercent != nil {
                        self.snapshot.isQuotaStale = true
                        self.snapshot.quotaUpdatedAt = self.snapshot.quotaUpdatedAt ?? self.snapshot.updatedAt
                        self.snapshot.resetCredits = []
                        self.snapshot.resetCreditAvailableCount = nil
                        self.errorMessage = "同步超时，显示上次成功数据（非实时，当前账号未重新确认）。"
                    } else {
                        self.snapshot = .empty
                        self.errorMessage = error.localizedDescription
                    }
                }
                if fetchRadar { self.refreshRadar(translate: translate, revision: revision) }
            }
        }
    }

    private func refreshRadar(translate: Bool, revision: Int) {
        guard radarEnabled else { return }
        lastSignalFetchAt = Date() // Throttle attempts as well as successful responses.
        let reset = snapshot.resetsAt
        let cancellation = RadarCancellation()
        radarCancellation = cancellation
        let fetchSignal = self.fetchSignal
        DispatchQueue.global(qos: .utility).async {
            let signal = (try? fetchSignal(cancellation, reset, translate)) ?? .unavailable()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.radarCancellation === cancellation else { return }
                self.radarCancellation = nil
                guard self.radarEnabled, self.settingsRevision == revision else { return }
                self.tiboSignal = signal
            }
        }
    }
}
