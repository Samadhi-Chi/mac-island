# Mac Island V1 开发版测试记录

日期：2026-07-26  
分支：`feat/mac-island-v1`  
上游基线：`realfishsam/agent-notch` 调研后选用 Apache-2.0 `erha19/ping-island`，固定提交 `14569e211617f2f9072d9eea23934ca9caf62ca4`

## 工具链

- macOS 26.5.2（25F84）
- Xcode 26.6（17F113）
- Swift 6.3.3
- macOS SDK 26.5
- Homebrew `mas` 7.0.0；Xcode 由官方 Mac App Store 安装

## 基线

- 未改动 Prototype：136/136 通过。
- 未改动 Ping Island Xcode Debug：构建通过；上游已有 Swift actor-isolation 与弃用警告。

## 最终自动化结果

- 2026-08-09 当前唯一产品门禁 `./scripts/test.sh` 复验通过：自动切换 `samadhi` 共享开发配置，Prototype `136/136`，`MacIsland` Release 构建成功，18 个产品测试套件合计 `276 passed / 1 opt-in skipped / 0 failed`。新增回归确认运行时 Bundle ID、日志 subsystem、本地 App Group 和单实例检查随 `local.sun.*` / `local.samadhi.*` 当前配置变化，不再在源码中锁死某个开发用户。Xcode 26.6 仍报告上游 actor-isolation、未来 Swift 6 错误和少量弃用警告；工程当前是 Swift 5 语言模式，因此本轮门禁通过，但不能宣称 Swift 6 迁移就绪。
- 2026-07-28 活跃客户端用量切换回归：50/50 通过，0 skipped，0 failed；覆盖 Codex 运行优先于较新的空闲 Cursor、Cursor/Codex 同时运行时选择最近活动者、全部空闲时保留最近活跃者、Cursor 快照缺失时不错误显示 Codex，以及“跟随活跃客户端”设置迁移。结果包：`/private/tmp/mac-island-cursor-aligned-v2-live-dd-20260728/Logs/Test/Test-MacIsland-2026.07.28_15-47-56-+0800.xcresult`。
- 2026-07-28 Cursor 官方用量接入定向回归：14/14 通过，0 skipped，0 failed；覆盖官方 HTTPS 主机锁定、Authorization 仅存在于请求头、响应字段解析、总量/模型/Auto 剩余量展示、用量缓存不含 token/authorization 且文件权限为 0600。结果包：`/private/tmp/mac-island-cursor-aligned-v2-live-dd-20260728/Logs/Test/Test-MacIsland-2026.07.28_15-26-44-+0800.xcresult`。
- 同一工作树的非筛选单元测试兼容性观察为 792 passed、46 failed、1 skipped；失败集中在 V1 已禁用的第三方 Agent、岛内审批/回答、遥测、Hook 安装和旧设置契约，没有 Cursor 用量专项测试失败。结果包：`/private/tmp/mac-island-cursor-aligned-v2-live-dd-20260728/Logs/Test/Test-MacIsland-2026.07.28_15-27-19-+0800.xcresult`。
- 2026-07-28 Cursor 身份标签与图标对齐回归：`MacIslandProductPolicyTests` 与 `SessionStateTests` 定向套件通过；Cursor 的底层兼容 provider 可继续为 Claude，但列表、Hover 与完成通知统一按当前模型族显示（例如 `Grok`），模型尚未解析时显示 `Cursor`，不再把内部 provider 暴露为正文前缀。结果包：`/private/tmp/mac-island-cursor-c-tests-dd-20260728/Logs/Test/Test-MacIsland-2026.07.28_14-27-00-+0800.xcresult`；新增的“模型族 / 无模型兜底”2 个边界测试结果包：`/private/tmp/mac-island-cursor-c-tests-dd-20260728/Logs/Test/Test-MacIsland-2026.07.28_14-31-21-+0800.xcresult`。
- 2026-07-28 Cursor 动效触发修复：`MacIslandProductPolicyTests` 20/20 通过，覆盖 Codex/Cursor 仅在工作态播放动效，idle/completed/aborted/等待处理均保持静止；同时覆盖收起态运行门控、减少动态效果与静态能源策略、Cursor 1.76 秒开合周期和 0.92→1.0 缩放曲线。结果包：`/private/tmp/mac-island-cursor-c-tests-dd-20260728/Logs/Test/Test-MacIsland-2026.07.28_20-54-21-+0800.xcresult`。
- 2026-07-28 Cursor 模型身份与实时详情修复定向回归：124/124 通过，1 个显式 opt-in 真机数据库测试按设计跳过，0 failed；覆盖 Grok/Claude/Gemini/GPT 正文前缀、Cursor 完整 bubble 流中的 thinking/tool/assistant 投影、完成与中止工具状态，以及完成会话保留最近执行时间线。结果包：`/private/tmp/mac-island-cursor-rich-dd-20260728b/Logs/Test/Test-MacIsland-2026.07.28_12-03-01-+0800.xcresult`。
- 2026-07-28 收起态实时图标回归：134/134 通过，0 skipped，0 failed；图标只在 `processing / compacting` 阶段显示，空闲、结束、等待输入、等待审批和无会话时均隐藏；工作态 Codex/Cursor 继续使用 `.working` 动效策略。结果包：`/private/tmp/mac-island-collapsed-glyph-tests-20260728/Logs/Test/Test-MacIsland-2026.07.28_14-26-44-+0800.xcresult`。
- 2026-07-27 Codex 实时状态与动效修复定向回归：162/162 通过，0 skipped，0 failed；覆盖 app-server/rollout 按来源事件顺序合并、跨 turn 重复消息、custom tool 真实完成时点、不可比较时间戳下的最新回复、多行回复投影、诊断正文/工作区路径脱敏及 Codex 图标旋转/缩放/呼吸策略。结果包：`/private/tmp/mac-island-live-status-tests-v4-dd-20260727/Logs/Test/Test-MacIsland-2026.07.27_00-43-51-+0800.xcresult`。
- 2026-07-26 23:19 最新产品范围回归：233/233 通过，1 个显式 opt-in 真机读取测试按设计跳过，0 failed；结果包：`/private/tmp/mac-island-vibe-ui-tests-dd-20260726/Logs/Test/Test-MacIsland-2026.07.26_23-19-19-+0800.xcresult`。
- Mac Island 核心 Xcode 回归：185/185 通过，0 skipped，0 failed。
- 结果包：`/private/tmp/mac-island-final-core-20260726-1715.xcresult`
- 视觉收紧修订定向回归：51/51 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-visual-20260726-1733.xcresult`。
- 显示/用量/静音配置定向回归：95/95 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-config-20260726-1800.xcresult`。
- 主配额与本地详情卡定向回归：148/148 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-usage-detail-card-20260726-1812.xcresult`。
- 项目/Thread 标题与 Cursor 本地会话回归：128/128 通过，1 个显式 opt-in 真机读取测试按设计跳过，0 failed；结果包：`/private/tmp/mac-island-cursor-regression-20260726.xcresult`。
- Cursor 真机数据库只读测试另行启用后 1/1 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-live-cursor-test-20260726c.xcresult`。
- 字号、用量配色与客户端像素图标定向回归：162/162 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-static-ui-final-20260726.xcresult`。
- Codex 最终采用 C12：四个尺寸相同、带一像素阶梯角的方块按 `2×2` 排列，左上/右下深蓝、右上/左下浅蓝；工作态连续顺时针旋转，并叠加轻微缩放、整体呼吸和四格追逐亮度，空闲/完成、系统“减少动态效果”和 EnergyGovernor 静态策略下保持静止。Cursor 采用 H2 宽体右上像素鼠标。
- H2 Cursor 像素鼠标、动效帧、显示配置、用量与会话状态组合回归：164/164 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-h2-click-regression-20260726-2112.xcresult`。
- Codex C12 四方块像素图标、逐帧颜色换位/呼吸与产品策略定向回归：15/15 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-c12-motion-test-20260726.xcresult`。
- Cursor C 四面晶体、无中心光点、开合周期与 Codex/Cursor 工作态动画策略定向回归：19/19 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-cursor-c-tests-dd-20260728/Logs/Test/Test-MacIsland-2026.07.28_14-15-20-+0800.xcresult`。
- Island Hover 自动展开、会话详情默认展示与静态图标最终定向回归：209/209 通过，0 skipped，0 failed；结果包：`/private/tmp/mac-island-hover-static-final-v2-20260726.xcresult`。
- 非筛选上游 Scheme 仅作兼容性观察，不作为 Mac Island V1 门禁：757 passed、47 failed、1 skipped，且旧 `PingIslandUITests` Runner 启动失败；失败项集中在本产品明确禁用的第三方 Agent、岛内审批/回答、遥测和旧设置契约，未涉及本轮 H2 像素图标与受控点击动效逻辑。结果包：`/private/tmp/mac-island-codex-c7-full-20260726.xcresult`。
- 覆盖：产品策略、隐私快照、fixture、Vibe Hook 迁移、诊断日志脱敏、Codex app-server 只读监控、会话状态机、跳转目标与窗口几何。
- Prototype / Bridge Swift Package：136/136 通过。
- Debug 构建、深度 ad-hoc 签名和 `codesign --verify --deep --strict` 均通过。
- 本轮最终构建 App：`/private/tmp/mac-island-cursor-aligned-v2-live-dd-20260728/Build/Products/Debug/Mac Island.app`
- Bundle ID：`local.samadhi.macisland`

说明：未把上游全部产品测试宣称为通过。一次全上游测试尝试中，审批、远程、多 Agent、用量、更新等被 V1 明确关闭的功能仍有旧断言失败；本记录以产品范围内核心套件和完整 Bridge 套件为交付门禁。

## 真机运行与性能

公开版本已移除历史真实会话截图、账户用量及本机标识。以下仅记录当时的验证范围，不代表当前版本验收。

- Debug App 多次退出/重启成功，普通启动后保持运行。
- 收起态为顶部中央紧凑刘海；最新视觉修订将面板内容宽度收紧为 600pt，最大内容高度仍为 560pt。客户端像素图标不再作为常驻品牌标记，只在真实处理/压缩任务运行时出现并播放动效；空闲时前导槽位同步收回。旧记录中的 640pt 已被此项取代。
- 内容字体默认提升到 12pt，完成卡片固定为 90pt；V2 只迁移字体值，保留用户的声音、面板尺寸、用量和其他配置。
- 鼠标进入 Island 约 130ms 后展开、离开约 200ms 后收起；Hover 不抢系统焦点。每行默认显示最近指令与当前输出/状态的紧凑两行摘要，停留某个会话约 90ms 后仅向下展开该会话的一张 156pt 详情卡，离开约 180ms 后关闭。详情卡保留多行段落和列表，并显示最新 commentary、正在运行的工具或最终回复。旧记录中的“立即展开且所有详情永久展开”已被此项取代。
- 剩余用量以 macOS 电量色为基准：`>= 50%` 绿色、`20%...49%` 黄色、`< 20%` 红色；顶部摘要、详情百分比和电池填充共用同一阈值与色板。
- 顶部和收起态的用量摘要不再同时并排展示 Codex 与 Cursor：`processing / compacting` 会话优先，多个运行会话按 `lastActivity` 选择，全部空闲时保留最近活跃的支持客户端；当前客户端快照未就绪时隐藏用量而不冒充另一家。设置中的默认项改为“跟随活跃客户端”，内置屏不再因双服务商用量横跨摄像头区域。
- Codex 使用四个独立、等大的深蓝/浅蓝交错 C12 阶梯角像素方块；工作态以 3.6 秒为一轮持续旋转，缩放范围 0.94～1.04，并叠加 0.88～1.0 的呼吸透明度和四格追逐亮度。Cursor 使用四档银灰切面构成的 C 四面像素晶体，以 1.76 秒为一轮开合并叠加 0.92→1.0 连续缩放，中心仅保留黑色留缝、不显示光点；Codex/Cursor 在展开列表、Hover 和收起态均只在真实工作态播放，任务停止后立即保持静态。Cursor 的 19×19 逻辑画布现以 `.topLeading` 作为固定坐标原点，闭合态占用 1...17、张开态占用 0...18，消除了 SwiftUI 按 1pt 内在尺寸先居中后再 offset 导致的整体右下偏移；列表中的 Codex/Cursor 均放入相同的 30pt 头像槽。两种图标均已移除组件底板、列表头像框和悬浮头像框，只保留中心图形与动画；未复制第三方图标素材。
- 展开态视觉检查：不展示通用 `Codex session` 文案；主会话显示项目、状态、时间、服务商、模型、客户端及 90pt 本地详情卡。
- Cursor 监控同时保留 Hook 入口和 `state.vscdb` 只读入口；后者每 500ms 按数据库指纹增量刷新，将 `composerHeaders` / `composerData` 元数据与 `cursorDiskKV` 的本地 bubble 流只读关联，投影最近用户指令、thinking、工具名/参数/状态和助手输出，并允许同一工作区存在多个独立 Thread。模型正文前缀来自当前模型家族，例如顶部 `Grok-4.5` 时正文显示 `Grok`，不再写死为 `Claude`。
- 用量优先读取只读 `account/rateLimits/read` 的主 `codex` bucket，显示 7 天剩余量及重置倒计时；模型专项 bucket 不再冒充主配额，且不读取 API 凭据。
- 声音总开关、音量和所有事件声音默认分别为关闭、0 和关闭；界面显示静音图标。
- 最终 v3 真机复核：旧 Debug 进程已正常退出，`/private/tmp/mac-island-live-status-final-v3-dd-20260727/Build/Products/Debug/Mac Island.app` 以 PID 43207 启动；辅助功能树包含 `Codex pixel status icon` 与真实 7 天剩余量。相隔 900ms 的两帧对 48×40 图标区域比较，5760 个原始字节中 1912 个发生变化（`animationObserved=true`），确认旋转/缩放/呼吸动效在真实窗口持续运行。
- 使用包含 `SECRET_SHOULD_NOT_APPEAR` 与 `PRIVATE_OUTPUT_SHOULD_NOT_APPEAR` 的合成权限事件验证，Bridge 不输出 stdout/stderr；产品快照与辅助功能树均不包含两段内容。
- 在线 `PermissionRequest` 30 次：p50 8.37ms，p95 13.61ms，max 274.21ms；p95 低于 150ms。
- 应用关闭时状态事件：10.49ms 返回，exit 0，stdout/stderr 均为空。
- 本地目录、运行目录与 Socket 权限分别为 0700、0700、0600。
- App 进程只观察到 `127.0.0.1:<ephemeral> -> 127.0.0.1:41241`，未观察到外部网络连接。
- Codex 精确跳转 `codex://threads/<id>` 与 Cursor 工作区/应用降级路径由自动化测试覆盖；未点击真实用户会话，避免打断当前工作。
- Notification Center 合成问题已定位并修复：旧版 Mac Island 曾保留 `screen.width × 750pt`、`.mainMenu + 3` 的透明高层窗口，点击菜单栏日期与时间后会让通知中心背景在该区域近乎全黑。当前普通运行版的 WindowServer 实测为顶部中央 `696 × 624pt`、layer 25（`.statusBar`）局部窗口，PID 级窗口检查确认不再持有整屏透明表面；仍需用户执行一次真实“点击日期与时间”目视验收。
- Computer Use 对当前普通运行版的只读复核显示收起态为局部中央胶囊，实时主配额为 `Codex · 7d · 37% 剩余`，按 20%～49% 规则呈黄色；没有回退到伪造的 `100%`。
- 当前 Debug App：`/private/tmp/mac-island-cursor-aligned-v2-live-dd-20260728/Build/Products/Debug/Mac Island.app`；最终源代码重建、深度临时签名校验和无 fixture 普通启动均已验证，当前进程 PID 1708。Computer Use 同屏确认合成工作态 Cursor 与两条已完成真实 Cursor 行均在连续帧间发生明显开合/缩放变化；两个图标裁剪区的帧差 PSNR 分别为 17.42dB 与 17.40dB。验收后已经退出 fixture 并恢复正常启动参数。

## 隐私与只读边界

- 用户明确选择在个人本机屏幕上展示更多执行细节：`项目 · Thread` 标题、最近用户指令和当前回复/状态默认可见，Hover/选择时展开更完整的本地详情；屏幕上的 `Private` 遮挡与标签已关闭。
- 屏幕展示策略不改变数据边界：会话详情只来自本地内存快照，Thread 名与正文不写入用量缓存、关联缓存、诊断日志、遥测或 Bridge 日志。
- Cursor 数据库以 SQLite read-only 模式打开，不修改 Cursor 数据；运行日志只记录刷新条数，不记录 Thread 名或对话正文。
- Codex `thread/read` 在用户选择展示本地执行详情后允许 `includeTurns=true`；turn 仅进入内存中的 `SessionState`，不写入关联缓存、用量缓存、诊断包、Bridge 日志或遥测。
- 本地会话关联缓存位于 `MacIsland` Application Support 命名空间，且不保存 session name。
- Hook 在状态层前丢弃 message、tool input 和可回答 intervention；只保留路由、工具名和生命周期状态。
- `PermissionRequest` 只产生需处理状态，Socket 不等待岛内决定。
- Codex 变更型 API 在网络访问前即被 monitor-only 守卫拒绝。
- Codex 用量优先从本地 app-server 的只读 `account/rateLimits/read` 获取主 bucket，本地 `rate_limits` 事件仅作兜底；投影后的缓存目录/文件权限为 0700/0600，不缓存 prompt、回复、token 明细、limit id 或来源文件路径。
- Cursor 授权令牌仅在一次官方用量请求期间驻留内存，不写入缓存、日志或诊断包；URLSession 使用 ephemeral 配置，关闭 Cookie 和 URL Cache，目标 scheme/host 固定为 `https` / `api2.cursor.sh`。`~/.mac-island/cache/cursor-usage.json` 仅保存服务商套餐、周期、支出和百分比快照，真机权限为 0600。
- 更新检查、遥测、其他 API 凭据读取、SSH、声音商店和自动 Hook 安装均未启动。

## Vibe 共存状态

- 未修改、安装或卸载当前 Vibe Hook。
- 用户明确要求后已通过正常的 `Command-Q` 退出 `/Applications/Vibe Island.app`；Vibe Hook 与配置未修改。Vibe 进程保持退出，最终 v3 Debug 构建已重新启动。
- 迁移器只在显式执行时备份配置并移除 Vibe 自有 Bridge 命令；预览、重复执行、坏 JSON 与回滚均有测试。
- 本轮未执行 shadow 切换，也未复制 Vibe 二进制、素材、字符串、签名或许可证逻辑。

## 尚未完成的真机矩阵

以下项目不能由当前单屏短时会话完整证明，仍作为下一轮真机验收项：

- 睡眠/唤醒后的长时恢复。
- 真实全屏应用、多 Space 切换。
- 无刘海外接屏与多显示器迁移。
- Cursor 扩展对具体窗口/集成终端的精确跳转。
- 长时 CPU、内存和 Instruments 网络记录。
- Vibe shadow 并存、配置切换和一键回滚的真实用户环境演练。

DMG、Developer ID、Universal Release、公证、公开品牌名与发布流程均不属于本阶段完成条件。
