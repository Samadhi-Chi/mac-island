# Mac Island 迭代验证与交付记录

本轮开发始于 2026-09-26。本文记录源代码、自动化验证与真实客户端验收之间的边界；完整范围见[开发计划](mac-island-iteration-plan.md)，持续状态见 [GitHub #1](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/1)。

## 已实现的行为

- Hermes 恢复时间统一回退到开始时间；OpenCode 未知来源保留未知身份，后续真实事件接管，避免把桌面会话误当 CLI。
- 停靠与悬浮共用导航反馈，区分终端定位、请求发送、应用打开和失败。快捷操作支持打开目录、复制原生 ID、本地隐藏、返回会话和下一个待关注；新增全局快捷键默认不绑定。
- 最近会话只保存客户端、来源、原生 ID、目录和活动时间。默认 7 天/200 条，可切换 24 小时/100 条、仅本次运行或停用，也可清空；不存对话、内容派生标题、启动 URL、PID 或 TTY。
- 设置显示只读监控健康并允许重连 Island 自己的 Codex 订阅。重试有上限，旧连接响应失效，睡眠/锁屏按现有能耗策略暂停；不重启外部客户端。
- 不活跃的 CLI 会话可打开独立续接预览窗口，检查原生 ID、目录、worktree、可执行文件和版本，支持复制命令。Codex、Claude、OpenCode、Hermes 四种适配器的生产执行认证均为空，**一键启动保持禁用**。

## 自动化验证

共享入口为 `./scripts/test.sh`。最终本地运行使用 Xcode 27 / macOS 27；GitHub 使用 Xcode 26.3 / macOS 15 runner。测试使用临时夹具、模拟传输和注入的导航/Terminal 替身，不安装应用或集成。

| 阶段 | 本地结果 | 证据与范围 |
| --- | --- | --- |
| Prototype | 137 项通过 | Swift Testing；包括 Bridge、临时进程与 Socket 夹具 |
| MacIsland Release | 构建通过 | `CODE_SIGNING_ALLOWED=NO`，无签名与发布 |
| 选定产品套件 | 552 项：551 通过、1 跳过、0 失败 | 兼容性及屏幕适配修复后于 2026-09-27 重跑，`MacIslandProductTests-20260927-004154.xcresult`；无运行时警告 |
| 悬浮/设置窗口和共享路由 | 已纳入上述产品门禁 | `DetachedIslandWindowControllerTests`、`SettingsWindowControllerTests`、`IslandExpandedRouteResolverTests` |
| 真实 Cursor 数据库 | 默认跳过 | 不读取个人对话库，不把跳过计为通过 |
| 签名 UI Tests、真实客户端、真实多屏 | 未运行 | 本轮没有安装、改写用户配置或真实续接授权 |

结果包位于被忽略的 `build/TestResults/`；可用 `xcrun xcresulttool get test-results summary --path <结果包>` 检查。GitHub 每次运行输出同一门禁及测试摘要，失败时保留结果包。历史迁移记录不是本轮测试证据。

关键回归覆盖：恢复数据库 NULL/缺列/过期与身份接管；导航重复点击/旧结果/失败反馈；窗口键盘作用域；索引白名单、容量、TTL、损坏、清空后重启与未来时间偏差；断线、超时、重试、睡眠/唤醒和旧通知；续接参数引用、失效预览、变化的目录/可执行文件、坏 worktree、取消与不确定投递。

PR #15 的 CI 曾暴露旧系统上的主执行器析构崩溃。本轮读取了六个失败用例的诊断，确认涉及 `swift_task_deinitOnExecutorMainActorBackDeploy`，并对无需隔离清理的类型明确使用 `nonisolated deinit`。修复后原失败测试全部保留并通过；最近索引/列表状态采用同一兼容处理。PR #17 又覆盖到已有悬浮状态对象，其相同处理被 `compiler(>=6.3)` 条件排除了 CI 使用的 Swift 6.2；通过单个失败用例的堆栈确认后，已对刘海、悬浮交互及气泡状态统一移除该限制，本地 457 项门禁重新通过。背景可参见 [Swift #85663](https://github.com/swiftlang/swift/issues/85663)。

PR #19 首次在 GitHub 运行新增窗口套件时，两项旧测试固定要求 700 点内容高度，但 CI 桌面由 AppKit 限制为 681 点。测试现按 [AppKit 的窗口约束规则](https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:))验证默认大小，仍要求精确的可用高度、默认宽度和窗口上下边界，未固定写入 681 或跳过用例；应用窗口实现保持不变。

## 2026-10-07：会话入口和原生标题（#25）

当前列表以「当前会话」与数量为标题，「最近记录」提供单独入口和返回按钮；
不再把 `Session list` 的控件标签展示成第三个页面。两种列表的主标题只使用
客户端原生名称，目录明确放在次级信息；没有名称时显示「标题暂不可用」。
完整路径、来源和原生 ID 收入会话详情，显式客户端按钮负责打开操作。
最近记录按客户端、来源和原生 ID 排除当前显示的会话，仅过滤界面，不删除索引。

Codex 名称通过现有连接的 `thread/read`、`includeTurns: false` 读取，结果仅保留
在内存。新增回归覆盖实时改名、延迟/取消读取、每批四个并行请求、读取失败、
精确身份、历史键盘选择和行内反馈；不会用摘要、消息或目录冒充名称。
人工夹具验收还发现，展开面板的额度刷新入口可能绕过启动隔离，现与监控启动
使用同一 XCTest/UI-test/fixture gate，并保留直接调用该入口的回归测试。

最终本地共享门禁在 macOS 27.0.1 / Xcode 27.0 通过：137 项 Prototype、
无签名 Release 构建、49 个产品套件共 599 项测试（598 通过、1 项真实 Cursor
数据库测试按规则跳过、0 失败、无运行时警告）。结果包为
`MacIslandProductTests-20261007-045339.xcresult`，完整日志和结果包均只在忽略的
`build/session-list.noindex/` 内。首次门禁发现悬浮活动行与结束行高度被统一；
现使用共享的状态行高规则，保留原有几何断言，未弱化或跳过测试。

PR #26 首轮 CI 的 599 项测试中只有新增的同步反馈身份用例崩溃。
下载结果包并读取该用例的 `.ips` 后，堆栈确认 `SessionActionController`
析构进入 `swift_task_deinitOnExecutorMainActorBackDeploy`，在 macOS 15.7.9
旧运行时释放无效指针。控制器仅释放数值和引用，现明确使用
`nonisolated deinit`，沿用仓库其他 UI 协调器的兼容处理；原失败测试保留。

使用独立应用标识和两条当前、两条历史的合成夹具核对原生停靠与悬浮界面：
标题与目录分层、当前记录不重复进入历史、缺失标题文案、返回当前列表、
完整详情、复制 ID 后的行内反馈，以及切换列表后的反馈保留均可见。
最终夹具运行正常退出；没有发送消息、执行续接、安装 hooks 或更改客户端配置。
沙盒内直接启动预览的两次 AppKit 注册失败不计为界面验收，通过的是随后在
正常桌面环境运行的同一已验证构建。

设计与数据边界见[会话列表设计](design/mac-island-session-list.md)。这次合成界面
验收不能替代真实多窗口精确导航、睡眠/唤醒、功耗或 CLI 续接认证；这些待办
继续保留在下表的对应跟踪项中。安装副本的真实标题核对另存本地安装记录。

## 2026-10-07：本机集成设置配色（#27）

Hooks、自定义 Hooks 和 IDE 扩展共用中性安装徽标，勾选 / 空心圆与文字区分
已安装 / 未安装；它不表示连接健康。普通本机操作统一使用系统强调色，卸载
使用系统红色与 destructive 角色；实际警告和更新结果采用语义状态颜色。
安装判断、动作回调、加载 / 禁用状态和备份逻辑保持原有行为。具体规则见
[配色说明](design/mac-island-integration-colors.md)。

本地共享门禁在 macOS 27.0.1 / Xcode 27.0 通过：137 项 Prototype、Release
构建、599 项产品测试（598 通过、1 项真实 Cursor 数据库测试按规则跳过、
0 失败）。结果包为 `MacIslandProductTests-20261007-095622.xcresult`，日志与
产物位于忽略的 `build/`。

人工验收直接提取生产行、徽标与按钮实现，配上合成客户端资料和空动作回调，
在独立原生预览中核对浅色 / 深色、已安装 / 未安装、更新中禁用、IDE 与自定义
集成。激活窗口时普通按钮使用同一强调色、卸载为红色，失焦时按原生规则弱化；
状态文字、图标与次级文字均可见。预览的外观切换只作用于该进程，未改变系统
外观或触发真实安装、更新、卸载、回滚。两个设置入口静态确认继续共用
`SettingsWindowView`，设置窗口回归包含在共享门禁内。合成组件验收不等于两个
完整设置入口的端到端人工验收。

## GitHub 交付

每批使用独立分支与 PR；连接器提交的 Git tree 与本地验证 tree 一致。合并前核对最新 head、base、全部检查与审查线程，再按预期 head SHA squash；合并后检查主分支。没有强推、跳过失败用例或开启发布。

| PR | 交付内容 | 结果 |
| --- | --- | --- |
| [#12](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/12) | 计划、协作规范、模板与统一门禁 | 已合并；[主分支检查通过](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/36252166844) |
| [#13](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/13) | 恢复时间与会话来源身份 | 已合并；[主分支检查通过](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/36252955317) |
| [#14](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/14) | 统一动作结果与反馈 | 已合并；[主分支检查通过](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/36253369727) |
| [#15](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/15) | 快捷操作、键盘作用域及运行时兼容 | 已合并；[主分支检查通过](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/36259018907) |
| [#16](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/16) | 监控健康与重连 | 已合并；[主分支检查通过](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/36293084678) |
| [#17](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/17) | 最近会话、隐私索引和保留设置 | 已合并；[主分支检查通过](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/36294071067) |
| [#18](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/18) | 四客户端续接预览与能力证据 | 已合并；[主分支检查通过](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/36294576966)；真实续接保持禁用 |
| [#19](https://github.com/Samadhi-Chi/mac-island-private-archive/pull/19) | 窗口/路由门禁、屏幕适配测试与本记录 | 本地完整门禁通过；最终 CI 与合并结果见 PR 和总跟踪项 |

完整 PR 与合并后检查链接在总跟踪项持续更新。当前私有仓库的套餐/集成权限不允许本轮建立服务端分支保护，原生 auto-merge 也未开启；这里执行的是逐次核验流程，不能把它描述为服务器强制保护。

## 尚待真实验收

### 2026-10-01：退出时回收自有 Codex observer（#7）

旧版 `a1f6c44` 的真实隔离复现确认：正常退出 Island 后，其自建 app-server 被重新挂到 PID 1，五秒后仍监听测试端口。根因是 `applicationWillTerminate` 调用的停止逻辑只派发未等待的 Task；monitor 又在发送 SIGTERM 后立即丢弃 Process，未确认退出。

退出现在从 `applicationShouldTerminate` 返回 `.terminateLater`，先同步封锁启动/窗口的所有监控入口，再等待清理并仅回复一次；整个退出等待最多五秒。Codex 永久 shutdown 会阻止迟到的启动、重试和手动重连；可重启的普通 stop 则等待共享清理任务完成。只对保存的自有 Process 发送 SIGTERM，最多等待一秒，再按需 SIGKILL 并最多等待一秒。超时仍保留句柄，确认其随后退出后才允许重新连接；外部服务不在信号范围内。

新增回归覆盖重复退出、挂起清理超时及晚到完成、多窗口排队启动、能耗恢复取消、并发 stop、调用方取消、SIGTERM 超时升级、迟到解析/重试、普通停止后重启、清理超时后的恢复。测试只使用合成传输及本次创建的临时子进程。

最终本地共享门禁通过：137 项 Prototype、无签名 Release 构建、48 个产品套件共 585 项测试（584 通过、1 项真实 Cursor 数据库测试按规则跳过、0 失败、无运行时警告）。兼容修复后的结果包为 `MacIslandProductTests-20261001-064959.xcresult`。以上数据来自完整运行；此前链接失败、连接中断或沙盒内 socket 受限的尝试不计为通过。

PR #22 首轮 CI 在 macOS 15.7.9 / Xcode 26.3 的同步窗口测试析构时崩溃；诊断栈明确指向 `SessionMonitoringLifecycle.__deallocating_deinit` 经 `swift_task_deinitOnExecutorMainActorBackDeploy` 进入旧运行时错误。两个仅释放引用的生命周期辅助类型现显式使用 `nonisolated deinit`，继续由 `stop()` / `begin()` 承担隔离清理；保留原失败测试，并新增同步释放及弱注册存活期回归。

真实修复版的三轮验收全部通过：正常退出、连续三次退出请求、自有 observer 刚开始监听即退出。三轮应用均返回 0，正常退出请求约 0.09 秒完成；应用退出时 observer 已不存在，五秒后仍无残留，测试端口释放且隔离 hook socket 移除；没有触发脚本的残留进程强制清理。

真实验收使用本机实际 Codex 可执行文件、独立空 CODEX_HOME、临时用户目录、独立应用标识与测试端口，未启用 XCTest/fixture 启动隔离。各轮均核对正式进程集合前后不变；未启动、停止或覆盖正式安装版，未改动客户端配置或安装 hooks。隔离构建与生产源码的差异仅限测试端口和应用标识，已对源码逐文件生成哈希校验记录。原始进程身份、路径与构建产物仅保留在本地，不纳入源码仓库。

上述结果只完成本次正常退出清理验收；实际锁屏/睡眠、功耗、长期重连及真实服务的超时强杀仍未运行，继续由 #7 跟踪。超时强杀和重连边界仅由合成回归测试覆盖；本次不关闭 #7，也不安装或发布应用。

### 2026-09-27：Codex Desktop 会话为空的现场修复

跟踪 [#20](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/20)。当前桌面客户端的内置 CLI 为 `0.158.0-alpha.2.1`，使用 `Contents/Resources/codex-cli/bin/codex` 包装入口和嵌套 `CodexCLI.app`。旧监控只识别 `Contents/Resources/codex`；Finder 启动环境的 PATH 又没有独立 CLI，因此本机 Codex 在使用中，Island 仍无法建立观察连接。

修复按 `com.openai.codex` 应用身份优先查找运行中/已注册的安装，再回退到应用目录和 CLI PATH；兼容新旧布局和应用改名。新增 9 项临时应用测试。窗口测试还暴露出 `onAppear` 会绕过 AppDelegate 启动真实监控，现由 `SessionMonitor.startMonitoring` 统一阻止 XCTest、UI 测试及夹具播放启动真实接入，另增 6 项回归。

最终本地共享门禁：137 项 Prototype 通过，Release 构建通过，567 项产品测试中 566 通过、1 项真实 Cursor 数据库测试按规则跳过，无运行时警告。结果包为 `MacIslandProductTests-20260927-120442.xcresult`。首次运行发现临时目录 `/var` 与 `/private/var` 别名比较误报，已改为比较解析后的同一文件；一次已有悬浮窗口显示断言失败在后续完整运行中未复现，没有删改或跳过该用例。

现场验证仅重新打开原来运行的 `build/DerivedData/Build/Products/Debug/Mac Island.app`。清理本次测试误启动的观察服务后，新 Island 自行启动了自己的 Codex app-server，进程父子关系和本地连接均确认；12:07 连续读取到 11 条会话，本机最近会话索引中有 5 条在 30 分钟内活动。这里只记录数量，没有复制对话内容、原生 ID 或用户目录到仓库。应用程序目录中的另一份 Island 尚未替换，未改客户端设置、安装 hooks、发送消息或执行续接。

以上确认真实连接及会话接入恢复；实际面板外观待用户反馈，完整的多窗口导航、睡眠/唤醒和续接认证仍属下表待办。

安装包/命令版本检查见[客户端能力证据](client-capability-evidence.md)。以下事项保留在 GitHub 待办，不能用合成测试或“应用已打开”代替完成：

| 跟踪 | 验收内容 | 目前边界 |
| --- | --- | --- |
| [#8](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/8) | Codex、Cursor、Hermes Desktop 的真实导航 | 验证专用会话、多窗口、关闭应用、权限拒绝和目标缺失；Cursor 版本尚未取得 |
| [#7](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/7) | 真实断线、锁屏/睡眠与恢复 | 离线传输/能耗状态已测；真实系统场景未运行 |
| [#9](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/9)、[#10](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/10) | 四种 CLI 原生续接认证 | 只读版本/帮助检查及模拟执行已测；启动必须保持禁用直到专用会话验收后按精确版本开放 |
| [#11](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/11) | 停靠/悬浮、多屏、浅深色、键盘/可访问性和低功耗 | 自动化窗口/状态覆盖已测；人工外观、真实显示器及耗电测量未运行 |

后续验收应先明确应用安装、测试会话及必要权限的授权，再记录客户端版本、预期 ID/目录和实际结果。Hermes Desktop 暂无已验证的外部精确会话接口，不转为 CLI；Codex URI 接受只表示请求发送。续接无回执时不自动重复执行。发送消息、代做审批、停止任务、签名、公证和发布仍不在本轮交付范围。

## 回滚

出现回归时，以最新主分支建立修复或 revert PR，保留审查和 CI 流程，不重写共享历史。存在依赖时先回退后续 UI/续接与最近会话，再回退其依赖的监控或快捷操作。最近索引是独立元数据文件，回退代码不会删除原生客户端会话；需要清理索引时由用户在设置中明确清空。不要在回滚时附带卸载 hooks、修改客户端配置或终止客户端进程。
