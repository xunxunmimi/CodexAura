// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import AppKit
import SwiftUI

struct DashboardView: View {
    var onPanelHeightChange: ((CGFloat) -> Void)? = nil
    @EnvironmentObject private var store: UsageStore
    @AppStorage("usdPerMillionTokens") private var usdPerMillionTokens = 1.25
    @State private var isDailyUsageExpanded = false
    @State private var isTiboExpanded = false
    @State private var showsSettings = false
    @State private var selectedDuration: Int?

    private var selectedWindow: QuotaWindow? {
        let windows = store.snapshot.windows
        if let selectedDuration, let selected = windows.first(where: { $0.durationMins == selectedDuration }) { return selected }
        return windows.first(where: { ($0.remainingPercent ?? 100) <= 1 }) ?? windows.first
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 14) {
                header

                QuotaAuraCard(
                    remainingPercent: selectedWindow?.remainingPercent ?? store.snapshot.remainingPercent,
                    resetsAt: selectedWindow?.resetsAt ?? store.snapshot.resetsAt,
                    planName: store.snapshot.planName,
                    windowTitle: selectedWindow?.title ?? store.snapshot.windowTitle,
                    isRefreshing: store.isRefreshing,
                    resetCreditCount: store.snapshot.resetCreditAvailableCount,
                    resetCredits: store.snapshot.resetCredits
                )

                if store.snapshot.windows.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(store.snapshot.windows, id: \.durationMins) { window in
                            Button { selectedDuration = window.durationMins } label: {
                                Text("\(window.title) · \(window.remainingPercent.map { "\(Int($0.rounded()))%" } ?? "—")")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(selectedWindow?.durationMins == window.durationMins ? .cyan.opacity(0.18) : .white.opacity(0.05), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if store.radarEnabled {
                TiboResetRadarCard(
                    signal: store.tiboSignal,
                    isExpanded: Binding(
                        get: { isTiboExpanded },
                        set: { value in
                            isTiboExpanded = value
                            if value { isDailyUsageExpanded = false }
                        }
                    )
                )

                }

                dailyUsageSection

                if let error = store.errorMessage {
                    errorBanner(error)
                }

                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .frame(width: 360, height: panelHeight)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isDailyUsageExpanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isTiboExpanded)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .onAppear { onPanelHeightChange?(panelHeight) }
        .onChange(of: panelHeight) { _, height in onPanelHeightChange?(height) }
    }

    private var panelHeight: CGFloat {
        let collapsedHeight: CGFloat = store.radarEnabled ? 410 : 348
        let dailyUsageHeight: CGFloat = isDailyUsageExpanded ? 112 : 0
        let tiboDetailHeight: CGFloat = store.radarEnabled && isTiboExpanded ? 236 : 0
        let contentHeight = collapsedHeight + dailyUsageHeight + tiboDetailHeight
        return contentHeight + (store.errorMessage == nil ? 0 : 82) + (store.snapshot.windows.count > 1 ? 42 : 0)
    }

    @ViewBuilder
    private var dailyUsageSection: some View {
        if isDailyUsageExpanded {
            ZStack(alignment: .top) {
                HStack(spacing: 10) {
                    DayMetricCard(
                        title: "今日",
                        icon: "sun.max.fill",
                        usage: store.snapshot.today,
                        rate: usdPerMillionTokens,
                        tint: Color(red: 0.32, green: 0.90, blue: 0.92),
                        comparisonMax: max(store.snapshot.today.tokens ?? 0, store.snapshot.yesterday.tokens ?? 0)
                    )
                    DayMetricCard(
                        title: "昨日",
                        icon: "moon.stars.fill",
                        usage: store.snapshot.yesterday,
                        rate: usdPerMillionTokens,
                        tint: Color(red: 0.68, green: 0.46, blue: 1.00),
                        comparisonMax: max(store.snapshot.today.tokens ?? 0, store.snapshot.yesterday.tokens ?? 0)
                    )
                }

                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isDailyUsageExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8.5, weight: .black))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.50), in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.09), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .help("收起今日与昨日用量")
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isDailyUsageExpanded = true
                    isTiboExpanded = false
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.20), .purple.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.cyan.opacity(0.88))
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("今日 / 昨日用量")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        Text("点击展开 Token 与估算费用")
                            .font(.system(size: 8.2, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(TokenFormatter.compact(store.snapshot.today.tokens)) · \(TokenFormatter.compact(store.snapshot.yesterday.tokens))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                        Text("今日 · 昨日")
                            .font(.system(size: 7.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.27))
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.cyan.opacity(0.68))
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(
                    LinearGradient(
                        colors: [.cyan.opacity(0.065), .purple.opacity(0.055), .white.opacity(0.025)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.cyan.opacity(0.16), .purple.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.95), .purple.opacity(0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .cyan.opacity(0.5), radius: 11)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("CODEX AURA")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(1.6)
                Text(statusText)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()

            Button { store.refresh() } label: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.07))

                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.82))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 30, height: 30)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var statusText: String {
        if store.isRefreshing { return "正在同步本机 Codex 数据…" }
        if store.snapshot.updatedAt == .distantPast { return "等待首次同步" }
        return "本地同步 · \(store.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(3)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.18), lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack {
            Button("CC · 设置与关于") { showsSettings = true }
                .buttonStyle(.plain)
                .popover(isPresented: $showsSettings) { SettingsAndAboutView().environmentObject(store) }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))

            Spacer()

            Menu {
                Button("$0.50 / 1M") { usdPerMillionTokens = 0.50 }
                Button("$1.25 / 1M") { usdPerMillionTokens = 1.25 }
                Button("$5.00 / 1M") { usdPerMillionTokens = 5.00 }
            } label: {
                Text("估算价 $\(usdPerMillionTokens, specifier: "%.2f")/M")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.72))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct TiboResetRadarCard: View {
    let signal: TiboResetSignal
    @Binding var isExpanded: Bool
    @State private var showsTranslation = true

    private var tint: Color {
        switch signal.probability ?? 0 {
        case 80...: return .pink
        case 60...: return .orange
        case 35...: return .purple
        default: return .cyan
        }
    }

    var body: some View {
        if isExpanded {
            expandedCard
        } else {
            collapsedCard
        }
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.16))
                        Image(systemName: "button.programmable")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("TIBO RESET RADAR")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(0.8)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(signal.isLive ? Color.green : Color.yellow)
                                .frame(width: 5, height: 5)
                            Text(signal.isLive ? "X 公开帖子实时信号" : "暂无实时数据")
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                    }

                    Spacer()

                    if let probability = signal.probability {
                        VStack(alignment: .trailing, spacing: -1) {
                            Text("\(probability)/100")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(tint)
                                .contentTransition(.numericText())
                            Text(signal.verdict)
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    } else {
                        Text("—").font(.caption)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(tint.opacity(0.72))
                        .frame(width: 16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起帖子详情" : "展开帖子详情")

            if isExpanded {
                if let post = signal.latestPost {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Picker("帖子语言", selection: $showsTranslation) {
                                Text("中文译文").tag(true)
                                Text("英文原文").tag(false)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .frame(width: 118)

                            Spacer()

                            Text("全文 \(displayedText(for: post).count) 字")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(tint.opacity(0.70))

                            Text(post.publishedAt, style: .relative)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.30))
                        }

                        ScrollView(.vertical, showsIndicators: true) {
                            Text(displayedText(for: post))
                                .font(.system(size: 10, weight: showsTranslation ? .medium : .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(showsTranslation ? 0.76 : 0.90))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 170)
                        .contentShape(Rectangle())
                        .onTapGesture { isExpanded = false }
                    }
                    .padding(10)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(tint.opacity(0.75))
                    Text(signal.reason)
                        .lineLimit(1)
                    Spacer(minLength: 5)
                    if let url = signal.latestPost?.url {
                        Link("查看原帖 ↗", destination: url)
                            .foregroundStyle(tint.opacity(0.88))
                    }
                }
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))

                Text("关键词分数 · 不是概率或重置承诺")
                    .font(.system(size: 7.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.24))
            } else if let post = signal.latestPost {
                HStack(spacing: 7) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint.opacity(0.80))
                    Text(post.translatedText ?? post.text)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(post.translatedText == nil ? 0.38 : 0.74))
                        .lineLimit(1)
                    Spacer(minLength: 5)
                    Text(post.publishedAt, style: .relative)
                        .font(.system(size: 7.8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.28))
                        .fixedSize()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在获取并翻译最新帖子…")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.40))
                    Spacer()
                }
                .padding(10)
                .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.09), .white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded = false }
        }
    }

    private func displayedText(for post: TiboPost) -> String {
        if showsTranslation {
            guard let translatedText = post.translatedText, !translatedText.isEmpty else {
                return "中文翻译未开启或暂时不可用，请在设置中开启，或切换英文原文。"
            }
            return translatedText
        }
        return post.text
    }

    private var collapsedCard: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.17))
                    Image(systemName: "button.programmable")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("TIBO RESET RADAR")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .tracking(0.55)
                        Circle()
                            .fill(signal.isLive ? Color.green : Color.yellow)
                            .frame(width: 4.5, height: 4.5)
                    }

                    Text(signal.latestPost?.translatedText ?? signal.latestPost?.text ?? signal.reason)
                        .font(.system(size: 9.2, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(signal.latestPost?.translatedText == nil ? 0.38 : 0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 7)

                if let probability = signal.probability {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("\(probability)/100")
                            .font(.system(size: 19, weight: .black, design: .rounded))
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                        Text(signal.verdict)
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                } else {
                    ProgressView().controlSize(.small)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundStyle(tint.opacity(0.72))
            }
            .padding(.horizontal, 11)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.09), .white.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("展开帖子详情")
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct QuotaAuraCard: View {
    let remainingPercent: Double?
    let resetsAt: Date?
    let planName: String?
    let windowTitle: String
    let isRefreshing: Bool
    let resetCreditCount: Int?
    let resetCredits: [RateLimitResetCredit]
    @State private var showsCredits = false
    private var lowQuota: Bool { remainingPercent.map { $0 <= 1 } ?? false }

    private var progress: Double {
        min(max((remainingPercent ?? 0) / 100, 0), 1)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                WeeklyEnergyRing(progress: progress)

                VStack(spacing: -1) {
                    if let remainingPercent {
                        Text("\(Int(remainingPercent.rounded()))")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(lowQuota ? Color.red : Color.white)
                            .contentTransition(.numericText())
                        Text(lowQuota ? (remainingPercent <= 0 ? "额度已用尽" : "仅剩 1%") : "% 可用")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(lowQuota ? Color.red : .white.opacity(0.55))
                    } else if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("—").font(.title)
                    }
                }
            }
            .frame(width: 132, height: 132)
            .overlay(alignment: .bottom) {
                if let resetCreditCount {
                    Button { showsCredits.toggle() } label: {
                        Label("重置卡 ×\(resetCreditCount)", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showsCredits) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("可用重置卡 ×\(resetCreditCount)").font(.headline)
                            if resetCredits.isEmpty {
                                Text(resetCreditCount == 0 ? "暂无可用重置卡" : "服务未提供到期明细").font(.caption)
                            }
                            ForEach(resetCredits) { credit in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(credit.title).font(.caption.bold())
                                    Text(credit.expiresAt.map { "到期：\($0.formatted(date: .abbreviated, time: .shortened))" } ?? "到期时间未知")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(16).frame(width: 250)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Text(windowTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if let planName {
                        Text(planName)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.2), in: Capsule())
                            .foregroundStyle(.purple.opacity(0.95))
                    }
                }

                Text("CODEX QUOTA")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(.cyan.opacity(0.5))

                Divider().overlay(.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 4) {
                    Text("距离重置")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(countdown(from: context.date))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }

                if let resetsAt {
                    Text(resetsAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.cyan.opacity(0.2), .purple.opacity(0.12), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func countdown(from now: Date) -> String {
        guard let resetsAt else { return isRefreshing ? "SYNCING…" : "— — —" }
        let seconds = max(Int(resetsAt.timeIntervalSince(now)), 0)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return String(format: "%02d天 %02d:%02d", days, hours, minutes) }
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

private struct WeeklyEnergyRing: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: progress <= 0.001)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(time * 2.0) + 1) * 0.5

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.065), lineWidth: 13)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.16, green: 0.82, blue: 1.00),
                                Color(red: 0.10, green: 0.50, blue: 1.00),
                                Color(red: 0.53, green: 0.34, blue: 1.00),
                                Color(red: 0.16, green: 0.82, blue: 1.00)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .cyan.opacity(0.22 + pulse * 0.10), radius: 8 + pulse * 3)
                    .animation(.spring(response: 0.8, dampingFraction: 0.78), value: progress)

                Circle()
                    .fill(.cyan.opacity(0.045 + pulse * 0.025))
                    .padding(13)
                    .blur(radius: 8)
            }
            .overlay {
                FlowingEnergyArc(progress: progress, time: time)
                    .frame(width: 146, height: 146)
            }
        }
    }
}

private struct FlowingEnergyArc: View {
    let progress: Double
    let time: TimeInterval

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let safeProgress = min(max(progress, 0), 1)
            guard safeProgress > 0.001 else { return }

            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            // The canvas is 14pt larger than the ring view. This radius is therefore
            // identical to the SwiftUI Circle path radius instead of its inner edge.
            let radius = min(size.width, size.height) * 0.5 - 7.0
            let startAngle = -Double.pi * 0.5
            let endAngle = startAngle + Double.pi * 2 * safeProgress
            let arcLength = endAngle - startAngle

            // Raised outer/inner rims stay centered on the colored progress tube.
            let outerRim = arc(center: center, radius: radius + 5.25, from: startAngle, to: endAngle)
            context.stroke(
                outerRim,
                with: .color(.white.opacity(0.13)),
                style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
            )

            let innerRim = arc(center: center, radius: radius - 5.35, from: startAngle, to: endAngle)
            context.stroke(
                innerRim,
                with: .color(.black.opacity(0.30)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round)
            )

            // Equal-size highlights travel around the entire active arc. There is no head or tail.
            let segmentCount = max(24, Int(84 * safeProgress))
            for index in 0..<segmentCount {
                let u0 = Double(index) / Double(segmentCount)
                let u1 = Double(index + 1) / Double(segmentCount)
                let midpoint = (u0 + u1) * 0.5
                let wave = 0.5 + 0.5 * sin(midpoint * Double.pi * 6 - time * 2.6)
                let brightness = pow(wave, 4)
                let segment = arc(
                    center: center,
                    radius: radius,
                    from: startAngle + arcLength * u0,
                    to: startAngle + arcLength * u1
                )

                var sheenGlow = context
                sheenGlow.addFilter(.blur(radius: 3.2))
                sheenGlow.stroke(
                    segment,
                    with: .color(.cyan.opacity(0.035 + brightness * 0.12)),
                    style: StrokeStyle(lineWidth: 14.0, lineCap: .butt)
                )
                context.stroke(
                    segment,
                    with: .color(.white.opacity(0.025 + brightness * 0.15)),
                    style: StrokeStyle(lineWidth: 12.2, lineCap: .butt)
                )
            }

            // Five continuous, equally weighted filaments cover the complete progress arc.
            for strand in 0..<5 {
                let seed = Double(strand) * 1.73
                let cycles = Double(7 + strand * 2)
                let speed = 3.8 + Double(strand % 3) * 0.7
                let restingOffset = (Double(strand) - 2.0) * 2.6
                let amplitude = 1.10 + Double(strand % 2) * 0.38
                var filament = Path()

                for step in 0...96 {
                    let u = Double(step) / 96.0
                    let angle = startAngle + arcLength * u
                    let braid = sin(u * Double.pi * 2 * cycles - time * speed + seed)
                    let tremor = sin(u * Double.pi * 26 - time * 7.2 + seed * 2.1) * 0.48
                    let strandRadius = radius + restingOffset + braid * amplitude + tremor
                    let filamentPoint = point(center: center, radius: strandRadius, angle: angle)
                    if step == 0 { filament.move(to: filamentPoint) } else { filament.addLine(to: filamentPoint) }
                }

                let flicker = 0.78 + 0.22 * sin(time * (5.0 + Double(strand) * 0.31) + seed)
                let tint: Color = strand == 2 ? .white : (strand.isMultiple(of: 2) ? .cyan : .purple)

                var filamentGlow = context
                filamentGlow.addFilter(.blur(radius: 2.2))
                filamentGlow.stroke(
                    filament,
                    with: .color(tint.opacity(0.28 * flicker)),
                    style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    filament,
                    with: .color(tint.opacity(0.62 * flicker)),
                    style: StrokeStyle(lineWidth: strand == 2 ? 1.28 : 0.86, lineCap: .round, lineJoin: .round)
                )
            }

            // Same-size short forks are distributed evenly; none is treated as a leading head.
            let branchCount = max(1, Int((safeProgress * 7).rounded()))
            let branchAngularSpan = min(0.052, arcLength * 0.12)
            for branchIndex in 0..<branchCount {
                let seed = Double(branchIndex) * 2.41
                let centerFraction = (Double(branchIndex) + 0.5) / Double(branchCount)
                let centerAngle = startAngle + arcLength * centerFraction
                let direction = branchIndex.isMultiple(of: 2) ? 1.0 : -1.0
                let baseOffset = direction * 3.6
                var branch = Path()

                for step in 0...5 {
                    let u = Double(step) / 5.0
                    let angle = centerAngle - branchAngularSpan * 0.5 + branchAngularSpan * u
                    let zigzag = sin(u * Double.pi * 5 + seed + time * 8.0) * 0.82
                    let branchRadius = radius + baseOffset + direction * sin(u * Double.pi) * 2.2 + zigzag
                    let branchPoint = point(center: center, radius: branchRadius, angle: angle)
                    if step == 0 { branch.move(to: branchPoint) } else { branch.addLine(to: branchPoint) }
                }

                let branchFlicker = 0.42 + 0.30 * max(sin(time * 9.0 + seed), 0)
                context.stroke(
                    branch,
                    with: .color(.white.opacity(branchFlicker)),
                    style: StrokeStyle(lineWidth: 0.82, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func arc(
        center: CGPoint,
        radius: Double,
        from start: Double,
        to end: Double
    ) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(start),
            endAngle: .radians(end),
            clockwise: false
        )
        return path
    }

    private func point(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

}

private struct DayMetricCard: View {
    let title: String
    let icon: String
    let usage: DailyUsage
    let rate: Double
    let tint: Color
    let comparisonMax: Int64

    private var estimatedCost: Double? {
        usage.tokens.map { Double($0) / 1_000_000 * rate }
    }

    private var barProgress: Double {
        guard comparisonMax > 0 else { return 0 }
        return min(Double(usage.tokens ?? 0) / Double(comparisonMax), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Spacer()
                Text(String(usage.dateKey.suffix(5)))
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(TokenFormatter.compact(usage.tokens))
                    .font(.system(size: 21, weight: .black, design: .rounded))
                Text(usage.source.rawValue)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.34))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(estimatedCost.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(2))) } ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                Text("API 等价估算")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.30))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.055))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * barProgress)
                        .shadow(color: tint.opacity(0.45), radius: 5)
                }
            }
            .frame(height: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(red: 0.025, green: 0.027, blue: 0.055)
                Circle()
                    .fill(.cyan.opacity(0.16))
                    .frame(width: 250, height: 250)
                    .blur(radius: 75)
                    .offset(x: -145 + sin(time * 0.18) * 32, y: -180 + cos(time * 0.16) * 22)
                Circle()
                    .fill(.purple.opacity(0.18))
                    .frame(width: 270, height: 270)
                    .blur(radius: 82)
                    .offset(x: 150 + cos(time * 0.14) * 30, y: 135 + sin(time * 0.19) * 28)
                LinearGradient(
                    colors: [.clear, .blue.opacity(0.055), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

private enum TokenFormatter {
    static func compact(_ value: Int64?) -> String {
        guard let tokens = value else { return "—" }
        let value = Double(tokens)
        if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(tokens)"
    }
}
