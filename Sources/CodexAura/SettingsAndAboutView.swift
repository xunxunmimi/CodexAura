// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import SwiftUI

struct SettingsAndAboutView: View {
    @EnvironmentObject private var store: UsageStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex Aura · 设置与关于").font(.headline)
            Toggle("本地日志补充统计", isOn: Binding(get: { store.localTokenLogsEnabled }, set: { store.setLocalTokenLogsEnabled($0) }))
            Text("默认关闭。启用后流式读取所选 Codex 目录的会话文件，只解析 Token 事件；目录可能含多个账号。缺失的账号统计才使用此估算，不上传日志。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Tibo 雷达（实验功能）", isOn: Binding(get: { store.radarEnabled }, set: { store.setRadarEnabled($0) }))
            Text("默认关闭。启用后每 30 分钟访问 X 公开网页；这是关键词分数，不是重置概率或承诺。X 可收到 IP 等网络信息。").font(.caption).foregroundStyle(.secondary)
            Toggle("公开帖子的中文翻译", isOn: Binding(get: { store.translationEnabled }, set: { store.setTranslationEnabled($0) }))
                .disabled(!store.radarEnabled)
            Text("默认关闭。启用后将公开帖子文本发送给 Google 网页翻译端点。关闭会取消雷达请求；无法收回第三方已收到的数据。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Made by CC · @xunxunmimi").font(.subheadline.bold())
            Text("Copyright © 2026 CC\nPolyForm Noncommercial 1.0.0\n源码公开，非商业用途限制；商用请另行联系。\n独立第三方项目，非 OpenAI 官方工具。").font(.caption)
            HStack {
                Link("作者", destination: URL(string: "https://github.com/xunxunmimi")!)
                Link("许可证原文", destination: URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!)
            }.font(.caption)
        }
        .padding(18)
        .frame(width: 350)
    }
}
