# Codex Aura

[English](README.en.md)

**Codex 余量，一眼看清。** 由 **CC · [@xunxunmimi](https://github.com/xunxunmimi)** 维护的原生 macOS 菜单栏面板，用小小的能量环显示额度，并提供今日、昨日 Token 参考统计。

## 下载与安装

更新时间：**2026-10-07（北京时间）**。最新版本：**0.4.1 实验性预发布**。

| 安装包 | 更新时间 | 架构 / 系统 | 下载状态 |
| --- | --- | --- | --- |
| `Codex Aura 0.4.1 Universal.dmg.zip` | 2026-10-07 | Apple 芯片 arm64 + Intel x86_64；macOS 14+；Intel / macOS 14 实机未验收 | [最新实验版下载](https://github.com/xunxunmimi/CodexAura/releases/download/v0.4.1-experimental/Codex.Aura.0.4.1.Universal.dmg.zip) |
| `Codex Aura 0.4.0 arm64.dmg.zip` | 2026-10-05 | Apple 芯片 arm64；仅在 macOS 26 做过隔离启动验证 | [历史实验版下载](https://github.com/xunxunmimi/CodexAura/releases/download/v0.4.0-experimental/Codex.Aura.0.4.0.arm64.dmg.zip) |

ZIP 解压后得到 `.dmg` 安装镜像。二进制仅放在 [实验性 Release](https://github.com/xunxunmimi/CodexAura/releases/tag/v0.4.1-experimental)，请核对对应 [SHA-256 校验文件](https://github.com/xunxunmimi/CodexAura/releases/download/v0.4.1-experimental/SHA256SUMS-0.4.1.txt)。最新包包含两种架构；Intel 运行未验收。它采用 **ad-hoc 临时签名，未公证**，浏览器下载后的 Gatekeeper 体验尚未验收。

1. 单独安装兼容的 Codex，并在 Codex 中以 ChatGPT 账号登录。本工具不内置 Codex、不索取登录凭据。
2. 下载 `.dmg.zip` 和对应 `SHA256SUMS-0.4.1.txt`，核对 SHA-256，再解压 ZIP。
3. 双击解压得到的 `.dmg`，把 `Codex Aura.app` 拖到镜像中的 Applications。
4. 从 Applications 启动；在菜单栏或刘海旁点击能量环。正常模式无 Dock 主窗口；菜单栏入口不可用时提供可拖动备用窗口。
5. 在“CC · 设置与关于”查看隐私开关：日志统计、X 雷达、Google 翻译默认关闭。开启前请阅读下方隐私说明。

若系统阻止打开，仅在确认来源、哈希和设备政策后参考 [Apple 官方说明](https://support.apple.com/en-us/102445) 的“隐私与安全 → 仍要打开”。遇到恶意或损坏提示请停止，不忽略警告、不关闭系统保护，也不移除下载隔离属性。

需要自行编译时，直接看本页的 [源码编译运行教程](#从源码构建)。Code → Download ZIP 得到源码快照；想安装应用请选择 Releases 中的 `.dmg.zip`。[GitHub 官方说明](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives)

本项目采用 **PolyForm Noncommercial 1.0.0**：源码公开，按许可证允许非商业用途；商业用途需另行授权。它不是 OSI 意义的标准开源项目。详见 [LICENSE](LICENSE)、[NOTICE](NOTICE) 与 [第三方声明](THIRD_PARTY_NOTICES.md)。

> **0.4.1 实验性预发布。** 基于远端 0.4.0 逐项合入本地修复，保留隐私开关、数据来源、账号隔离历史及脱敏错误。没有完成真实账号、Intel、macOS 14 实机、多屏或浏览器下载后的安装验收。旧 0.3.x 包不属于本版。

本工具独立开发，与 OpenAI、ChatGPT、Codex、X 和 Google 无官方隶属、赞助或背书关系。相关名称和商标属于各自权利人。

## 0.4.1 更新记录（2026-10-07）

- 修复刘海屏上独立图标不参与系统排列的问题，增加可达入口降级。
- 兼容新版 ChatGPT 内置 Codex 路径和用户 Applications 目录。
- 合入低额度提醒、重置卡到期查看、多个额度窗口切换。
- 雷达仅判断最新帖；兼容新的帖子正文结构；翻译失败明确提示，不在中文标签下冒充译文。
- 保留 0.4.0 的隐私默认值、许可、账号隔离历史和安全发布脚本，不整体覆盖远端。

## 功能

- 菜单栏能量环、实际额度窗口标签与重置倒计时；只有服务返回 7 天窗口才称“每周额度”。
- 今日、昨日 Token 统计，显示数据来源；缺失数据用“—”表示，不把未知当零。
- 可切换参考单价的美元估算，它不是实际账单或官方报价。
- 优先使用系统菜单栏图标，与其他图标一起排列，按住 ⌘ 拖动并记忆位置；不可见时尝试备用图标 / 可拖动窗口。
- 同时返回多个窗口时可切换主显示；每周或 5 小时额度到 1% 及以下时，每个周期提醒一次。
- 服务返回重置卡数量时显示按钮，点击查看到期明细。
- “CC · 设置与关于”提供署名与隐私开关。
- 原有 Tibo 雷达与翻译保留为实验功能，**默认关闭**；开启后只显示关键词分数，不称真实重置概率。

## 要求与支持范围

| 项目 | 要求 / 状态 |
| --- | --- |
| 系统 | macOS 14 或更新版本 |
| Codex | 单独安装兼容的 Codex 程序，通过 ChatGPT 账号登录并具有可用额度数据 |
| 账号 | API Key 登录不能替代订阅额度账号；服务支持与账号权限以 Codex 实际返回为准 |
| 架构 | 最新下载包为 Universal 2；两种架构构建 / 合并检查，Intel 实机未验收 |
| 界面 | 当前主要为中文，附英文文档 |
| 网络 | Codex 子进程可能连接 Codex 服务；X / Google 外联默认关闭 |
| 签名 | 构建脚本使用 ad-hoc 临时签名，没有 Developer ID 签名或公证步骤 |
| 构建工具 | Swift tools 5.10+、Xcode 或兼容 Command Line Tools/macOS SDK、Python 3.8+；最低可用 Xcode 版本未建立 |

2026-10-07：合并版本通过 18 项离线 XCTest（完整 Xcode 工具链），Universal 两种架构 Release 构建、路径扫描、签名完整性、DMG 校验及 ZIP 完整性通过。默认 Command Line Tools 缺少 XCTest，测试需使用完整 Xcode；构建出现 SDK 调试模块路径 linker 提示，未影响签名及产物检查。未启动真实 Codex 或访问真实账号。

历史验证：2026-10-04 已用 Swift 6.2 完成 Apple 芯片上的 Debug 编译及 14 项离线 XCTest；测试使用合成账户/会话和模拟子进程，未启动真实 App 或 Codex，也未访问真实账户。编译器未报告源码警告；受隔离环境限制，SwiftPM 提示用户缓存不可写。已另完成本机 arm64 Release 打包；SDK 调试模块路径映射产生 linker 提示，产物路径扫描及签名完整性通过，完整分发体验仍未验收。尚未建立真实 Codex 版本兼容矩阵。Intel 交叉编译即使通过，也不能替代 Intel 运行验证。

## 日常使用

点击能量环打开面板，展开今日 / 昨日统计可查看数据来源；刷新按钮同步用量，电源按钮退出。日志补充、雷达、翻译三项开关在“CC · 设置与关于”；折叠卡片不会关闭功能。

Developer ID 与 [Apple 公证](https://developer.apple.com/developer-id/) 是另外的分发流程，当前没有实施。本版不附带移除下载隔离属性的安装助手。

## 从源码构建

### 1. 准备工具和 Codex

- 使用 macOS 14+；先确认你的 CPU 是 Apple 芯片还是 Intel。0.4.1 Universal 包包含 Intel 架构，但 Intel 实机未验收。
- 安装 Apple 的 Xcode，或提供兼容 Swift/macOS SDK 的 Command Line Tools。没有工具时可在终端执行 `xcode-select --install` 并按系统提示安装。只有 Command Line Tools 的机器尚未验收；实际验证使用 Xcode SDK 26.0、Swift 6.2。
- 项目声明 Swift tools 5.10；需 Python 3.8+。没有外部 SwiftPM 依赖，也不需要安装第三方 Python 包。
- 单独安装并登录兼容 Codex，参见 [OpenAI 官方 CLI 文档](https://learn.chatgpt.com/docs/codex/cli)。在 Codex 自己的界面完成登录，不把密码、账号配置或 Token 放进项目。

检查本机工具；这些命令不启动 Codex：

```bash
xcode-select -p
xcrun --show-sdk-version
swift --version
python3 --version
uname -m
```

若有多个 Xcode，需要选择其他工具链，可仅给本次命令设置 `DEVELOPER_DIR`，无需改全局配置。最低可用 Xcode/Codex 版本矩阵尚未建立。

### 2. 获取源码并进入根目录

仓库公开后可 Code → Download ZIP 并解压，或：

```bash
git clone https://github.com/xunxunmimi/CodexAura.git
cd CodexAura
```

ZIP 的顶层文件夹可能叫 `CodexAura-main`。在终端输入 `cd `，将解压目录拖进终端后按回车即可。根目录应有 `Package.swift`、`Sources`、`scripts`、`LICENSE`；不要进入 Sources 子目录构建。

### 3. 测试并生成原生 App

确认磁盘有至少 3 GiB 可用，建议留更多余量；脚本的最低门槛不是容量保证。仅做源码测试不会启动真实 Codex：

```bash
swift test --jobs 2
./scripts/build_app.sh
```

第二条命令生成 **当前 Mac 架构**的 `dist/Codex Aura.app`，包含图标与 LICENSE/NOTICE，完成路径扫描、临时签名及完整性校验。`swift build` 单独输出的可执行文件不是完整 App 包。

### 4. 安装与启动自己构建的 App

```bash
open "dist/Codex Aura.app"
```

也可以先在 Finder 把 App 拖入 Applications 后打开。随后看菜单栏 / 刘海旁的能量环，刷新按钮同步用量，电源按钮退出。默认不读本地会话，也不访问 X / Google；App 启动会调用独立安装的 Codex 服务，请在需要运行时再打开。

若找不到 Codex，请看本页 [Codex 程序与目录](#codex-程序与目录)，用 `CODEXAURA_CODEX_PATH` 显式指向可信可执行程序；Finder 不一定继承终端的环境变量。

### 5. 可选：制作 DMG 及其 ZIP

普通布局不控制 Finder、无需其自动化授权。本机原生包：

```bash
./scripts/build_release_dmg.sh ./dist native plain
```

在本机 arm64 构建时输出 `dist/Codex Aura 0.4.1 arm64.dmg`、`dist/Codex Aura 0.4.1 arm64.dmg.zip` 和 `dist/SHA256SUMS-0.4.1.txt`。ZIP 根目录仅包含对应 DMG。Intel 本机原生构建的文件名使用 `x86_64`；它尚未在本项目验证。

有足够空间且需两种架构时：

```bash
./scripts/build_release_dmg.sh ./dist universal plain
```

双架构模式最低要求 4 GiB，输出文件名带 `Universal`；本版 Universal 构建与合并已检查，Intel 运行未验收。脚本分别编译、合并、扫描、临时签名和验证，并产生校验和。它不会启动 App、登录账户或提交公证。

省略参数时为 `./dist`、`universal`、`finder`；`finder` 布局用 AppleScript 控制 Finder，可能需要构建时自动化权限，可选择 `plain` 避免。同名 App/包会被替换，请只用专用输出目录。

核对 ZIP 的哈希时可执行：

```bash
shasum -a 256 "dist/Codex Aura 0.4.1 arm64.dmg.zip"
```

源码使用默认 stdio 方式启动 `codex app-server`，请求公开文档中的只读方法，未开启 experimental API。接口可能随本机 Codex 版本不同而返回不可用；[官方 app-server 文档](https://learn.chatgpt.com/docs/app-server) 不等于每个安装版本都已测试。

## Codex 程序与目录

优先使用显式 `CODEXAURA_CODEX_PATH`，否则依次检查 Codex App、ChatGPT App 内置路径、Homebrew 常用路径、`~/.local/bin/codex`，最后检查进程 PATH 中的绝对目录。仅安装 ChatGPT App 不保证存在兼容程序。

数据目录只选一个：进程继承的非空 `CODEX_HOME`，否则 `~/.codex`；同一个目录用于 Codex 子进程与可选日志统计，不再同时扫描默认目录。Finder 通常不会继承终端环境。需要自定义路径时，可从终端直接启动 App 内可执行程序并提供你的配置，例如：

```bash
CODEXAURA_CODEX_PATH=/absolute/path/to/codex \
  "/Applications/Codex Aura.app/Contents/MacOS/CodexAura"
```

请只指向可信的 Codex 程序。应用不会替你登录、修改 Codex 配置或申请账号权限。

## 隐私

| 功能 | 本地读取 / 保存 | 网络行为 |
| --- | --- | --- |
| 额度及日统计 | app-server 返回的窗口、Token 日桶；`account/read` 的账号 ID 或邮箱仅用于内存中的缓存标识计算 | Codex 子进程按自己的认证、配置及服务行为联网 |
| 账号历史 | UserDefaults 最多保存该标识下 14 个日桶；键为所选目录与账号标识的 SHA-256，不保存邮箱或账号 ID 原文 | 不发送给作者、X 或 Google |
| 日志补充（默认关） | 流式读取所选目录 sessions 的最近修改 JSONL，只反序列化 Token 事件；每行、文件数、总读取量有上限 | 不上传日志或对话 |
| 雷达（默认关） | 公开 X 网页和帖文 | X 可收到 IP、请求时间、User-Agent；独立 ephemeral 会话禁用 Cookie 存储和 URL 缓存 |
| 翻译（默认关） | 公开帖子文本 | 发送给 Google `translate_a/single` 网页端点；不是本项目承诺支持的 Cloud Translation API |

App 自身没有直接读取 `auth.json`、钥匙串或浏览器 Cookie 的代码，没有作者数据收集服务器、广告或遥测 SDK。**Codex 子进程仍可能读取自己的凭据和配置、刷新认证及记录日志**，所以整个程序链不能被描述为完全离线或不涉及凭据。

会话文件可能含对话、代码或路径。流式提取 Token 仍需读过相关文件字节；默认不开启，可通过设置关闭。目录可能包含多个账号历史，因此本地估算明确标注“可能含多个账号”，不与账号服务总量相加取最大值。

用量每 5 分钟刷新；启用的雷达定时条件为 30 分钟，打开面板/手动同步用量不强制绕过此间隔；更改雷达或翻译设置可重新请求；切换日志统计时，会立即重取被取消的未完成雷达请求，已完成请求保留正常间隔。关闭开关会取消进行中的雷达请求，并阻止它继续请求帖子/翻译；取消无法收回第三方已经收到的数据，过期设置下的结果不会显示。

UserDefaults 还保存开关、参考单价、图标位置及面板展示状态。旧版未隔离的 Token 缓存不读取、不迁入新缓存。删除 App 后这些设置可能仍保留；卸载本工具不应删除 Codex 的 `.codex`、账号或会话。

未实现相机、麦克风、屏幕录制或辅助功能权限请求，也没有证据表明需要全磁盘访问。不要为排障盲目扩大权限。

## 准确性与限制

- 额度和每日统计分别降级；每日接口不支持时仍能显示成功读取的额度。服务端原始错误/标准错误不直接展示，界面只给出请求名称及错误码等脱敏摘要。
- 窗口按时长标注，不代表应用支持账户所有不同计量桶。当前优先 `codex` 桶，默认显示最长窗口，可切换服务实际返回的其他窗口。
- 日统计优先服务端返回的有效日桶（明确零保留为零）；缺失时使用同目录、同账号已观测历史；用户启用后才可用本地估算。无法获取账号标识时不加载/保存账号历史。
- Token 统计并非完整账单；日志会有缺失、重复、格式变更、跨账号或读取限额。重复累计事件不重复计入；没有可用数据时显示“—”。
- USD 为 `Token ÷ 1,000,000 × 选定单价`，不区分模型、输入/输出/缓存 Token，不代表订阅实付或官方现价。
- 雷达依赖 X 网页结构和使用条件，翻译依赖第三方网页端点，可能失效；无实时数据时明确提示，未内置任何旧帖子作为“缓存”。建议保持关闭。重新公开启用前需核对第三方条款与内容使用权。
- 超时及 pipe 输出有边界，失败后不会继续显示旧成功额度为当前数据；个别 Codex 版本/网络/系统策略仍可能不兼容。
- 真实账号、Intel 实机、刘海及多屏 UI、浏览器下载后的 Gatekeeper 安装体验尚未完成验收。没有签名/公证或“下载即用”承诺。

## 常见问题

| 问题 | 处理 |
| --- | --- |
| `swift` / SDK 不可用 | 完成 Apple 开发工具安装，检查 `xcode-select -p` 与 SDK；多个 Xcode 可为本次命令指定 DEVELOPER_DIR。 |
| 打包提示空间不足 | 停止构建并自行确认空间；原生至少 3 GiB、Universal 至少 4 GiB，勿删除 Codex 账号或会话来腾空间。 |
| 脚本不可执行 | 在确认来源后，用 `zsh scripts/build_app.sh` 或 `zsh scripts/build_release_dmg.sh ./dist native plain` 执行。 |
| 没有 Dock 窗口 | 本工具在菜单栏 / 刘海旁；点击能量环打开面板。 |
| 找不到 Codex / 额度是 — | 检查可信程序位置、ChatGPT 登录状态、账号资格与版本；未知数据不是满额度，不要求扩大系统权限。 |
| 今日 / 昨日 Token 是 — | 每日接口、已观测历史可能不可用；日志估算需用户显式开启，且不是完整账单。 |
| Intel 无法运行 arm64 包 | 当前没有已验收的 Intel 安装包；不能靠重新解压或改变签名解决架构不符。 |
| Gatekeeper 提示 | 核对来源/哈希并看 Apple 官方说明；受管理设备可能禁止打开，恶意/损坏提示应停止。 |

## 反馈与贡献

仓库公开后欢迎提 Issue 或 Pull Request。附 macOS、CPU 架构、Codex 版本、复现步骤和脱敏截图即可。不要上传凭据、`auth.json`、会话原文、完整日志、Cookie、账号 ID、邮箱或公司项目路径。参见 [贡献说明](CONTRIBUTING.md) 和 [安全反馈说明](SECURITY.md)。

源码 / 资产署名与 Required Notice 需随再分发保留；软件许可不覆盖第三方服务、内容或商标。商业用途请通过作者公开联系方式发起授权讨论，实际允许范围以 LICENSE 为准。此许可说明不是法律意见。可见 CC 署名用于识别作者，不是防复制技术。

## 喜欢的话，留一颗 Star ⭐

如果 Codex Aura 帮你少切一次窗口、少猜一次余量，欢迎给项目点一颗 Star。反馈、建议和小小的 Star，都能帮助这个工具继续变好。谢谢你支持！
