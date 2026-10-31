# Mac Island

[English](README.md) · **简体中文**

<img src="docs/images/mac-island-app-icon.png" width="96" height="96" alt="Mac Island Clean Notch 图标">

在 Mac 的屏幕顶部或悬浮窗口中查看多个编程助手的任务状态，并返回原客户端继续工作。Mac Island 保持静音，任务变化不会自动展开详情；悬停或点击后才显示你选择的内容。

**当前仍是开发版本，尚无正式签名安装包。** 正式签名、公证与真实环境验收仍有待完成，参见[发行准备记录](docs/mac-island-release-readiness.md)。本仓库没有可直接用于 Mac Island 的公开安装包下载入口；上游 Ping Island 的安装包不是本产品。

[网站 · 简体中文](https://samadhi-chi.github.io/mac-island/index.html) ·
[Website · English](https://samadhi-chi.github.io/mac-island/en/index.html) ·
[网站源码](site/index.html)

本仓库从审查后的源码快照开始，早期开发历史保留在私有归档中。参见
[源码历史说明](docs/source-history.md)及[公开前检查记录](docs/public-readiness-2026-10-31.md)。
源码公开、网页部署和正式安装包发行分别验收。

## 可以做什么

- 观察 Codex、Cursor、Claude Code、OpenCode、Hermes 和 DeepSeek Harness 的受支持本机来源。
- 查看当前会话、原生标题、任务状态及可选的本机进度详情。
- 通过明确的打开按钮返回客户端；反馈区分已定位终端、已发送请求、仅打开应用和失败。
- 查看当前列表以外的最近路由记录，按需清空或关闭保留。
- 在顶部 Island 与可移动的悬浮 Island 之间切换。

Mac Island 不代做审批、不回答问题、不发送消息，也不启动代理任务。当前不启用遥测、自动更新或远程 SSH 服务。CLI 续接目前提供预览和命令复制，尚未认证一键执行；详见[续接边界](docs/session-continuation.md)。

## 开始使用

首次启动通过三步介绍展示位置、客户端连接和已有连接状态。可以跳过，也可以从设置重新体验。引导不会安装 Hooks 或申请系统权限；需要相应集成时，由你在集成设置中明确操作。

“查看监控演示”在独立窗口展示运行、需要关注和完成三个阶段。演示使用明确标记的模拟数据，不读取真实会话、不启动客户端任务、不进入最近记录，也不改变真实 Island 的当前内容。

列表默认显示“当前会话”，右侧“最近记录”进入历史。标题使用客户端原生名称，无法读取时明确提示，不拿项目目录或对话内容代替。单击行用于选择，“在客户端打开”等按钮和 Enter 才执行导航。系统接受打开请求不等于已经确认正确会话显示。

## 控制屏幕内容

| 选择 | Island 中显示什么 |
| --- | --- |
| 只显示状态 | 客户端和通用状态，隐藏原生标题、Bot 名称、正文、路径与会话 ID |
| 显示标题 | 增加原生会话标题或 Bot 名称，不显示正文、活动标签、路径或会话 ID |
| 显示详情 | 显示可读的本机进度与详情；完整路径和原生 ID 位于明确打开的详情中 |

新安装默认“显示标题”；已有版本迁移时保留原来的详情显示方式。会议、录屏或投屏前，可点击“临时隐藏内容”，临时切到只显示状态；“恢复显示”返回你原来的选择。遮挡同时应用于两种 Island 展示形态，不遮挡其他应用，也不停止底层观察。

## Muse、Grok Bot 与 Dot

Muse 4.1 / 6.0 和 Grok Bot 0.68.1 是默认关闭的**实验性当前界面观察**。需要分别启用来源，并主动授予 macOS 辅助功能权限。每个当前可识别的 Bot 上下文显示一张卡；Muse 6.0 当前只读取名称，Muse 4.1 的 Activity 收在 Bot 卡片内，不拆成多个会话。

它们不保证发现全部后台 Bot、提供准确运行状态或恢复聊天。未知状态不计入运行数量，观察结果不进入最近记录；权限不足、版本不支持或界面不可读时会显示原因。Dot 当前只有应用入口，普通 Codex 会话仍按 Codex 显示。详见[实验来源说明](docs/personal-agent-observation.md)。

## 隐私、诊断与支持

对话和原生标题仅在内存中展示。最近记录默认保留本机路由元数据 7 天、最多 200 条，可改为 24 小时/100 条、仅本次运行或不记录。清空最近记录不会删除客户端历史，也不会清空独立的关联或额度缓存。

应用内提供离线使用说明、隐私说明和完整第三方许可。主动导出的诊断只包含版本、固定连接状态和故障分类，不复制客户端配置、日志、项目路径、会话标题、对话或凭据；文件留在本机，由你决定是否分享。

看不到会话时，先确认只运行一份 Mac Island，再查看集成设置中的连接状态和最近成功读取。Codex 重连只重连 Island 自己的观察连接，不重启外部客户端。完整步骤见[离线帮助](PingIsland/Resources/Legal/MacIsland-Help-zh-Hans.md)和[隐私说明](docs/privacy-policy.md)。普通问题请使用[支持指南](site/support.html)，安全问题遵循 [SECURITY.md](SECURITY.md)，不要公开真实对话或未经检查的诊断包。

## 开发与验证

这是基于 Apache 2.0 [Ping Island](https://github.com/erha19/ping-island) 的独立项目，保留 LICENSE 与 NOTICE。开发者可克隆后运行统一门禁：

```sh
git clone https://github.com/Samadhi-Chi/mac-island.git
cd mac-island
./scripts/test.sh
```

使用 Xcode 26+、Swift 6.2+ 工具链，打开 `PingIsland.xcodeproj` 并选择 `MacIsland`；CI 使用 Xcode 26.3。部署目标是 macOS 14+，不代表本轮已完成最低系统与 Intel 实机验收。

统一门禁检查全仓 Swift 格式、静态页面和发行工具夹具，运行 Prototype、Release 构建、随包许可检查和脚本列出的产品测试；本轮开发完成后集中执行，最新状态记录在[发行准备记录](docs/mac-island-release-readiness.md)。`BUILD_ROOT` 指定缓存/产物目录，`BUILD_JOBS` 默认 2，结果保存在 `$BUILD_ROOT/TestResults/`。完整上游套件包含本产品禁用能力，不替代产品门禁。

使用 `MAC_ISLAND_FIXTURE_PATH=Fixtures/mac-island-lifecycle.json` 与 `PING_ISLAND_UI_TEST_MODE=1` 可隔离真实监控进行界面验收。默认构建不包含开发者 Team；本机签名配置使用被忽略的 `Config/Local.xcconfig`，不要提交凭据、签名身份或用户配置。

开发遵循 [CONTRIBUTING.md](CONTRIBUTING.md) 的 Issue、分支、PR 和最终提交检查流程。本轮只准备可审查的发行能力；构建和测试不会自动安装、签名、公证或发布。App Store 仍在评估，没有切换产品路线。

## 来源与许可

[LICENSE.md](LICENSE.md) · [NOTICE](NOTICE) · [随包第三方许可清单](docs/third-party-notices.md) · [图标设计](docs/design/mac-island-app-icon.md)

上游功能、Homebrew、发布和营销说明保留在历史 [English README](docs/history/upstream-readme.md) 与[中文 README](docs/history/upstream-readme.zh-CN.md) 中，仅作参考。当前产品约束以 `PingIsland/Core/MacIslandProductPolicy.swift` 为准；开发导航见 [AGENTS.md](AGENTS.md)。
