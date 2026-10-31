# Personal Agent 验证记录

2026-10-08；实现范围见 [观察说明](personal-agent-observation.md)，来源能力跟踪 [#29](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/29)，Bot 会话卡跟踪 [#31](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/31)。

## 首版自动化与隔离预览（PR #30）

本轮在开发完成后集中运行一次完整门禁，未在实现过程中反复跑测试。最初的受限沙箱调用在 SwiftPM manifest 阶段被系统拒绝，没有执行测试；正常构建环境中的门禁通过：

- 2026-10-07：`./scripts/test.sh`，137 项 Prototype 测试通过；Release 构建通过；620 项产品测试中 619 通过、1 项真实 Cursor 数据库测试按离线门禁约定跳过，0 失败。
- 结果：`build/session-list.noindex/TestResults/MacIslandProductTests-20261007-121535.xcresult`。
- 界面核对后统一设置卡片外观，修正父级覆盖子控件辅助功能标识，明确新增回调的 MainActor 隔离。2026-10-08 仅重新构建并复查 PersonalAgentObservation、PersonalAgentMonitor、IslandExpandedRouteResolver、SettingsWindowController 四个受影响套件：36 项全部通过，不重复 Prototype 或完整产品测试。
- 针对性结果：`build/session-list.noindex/TestResults/PersonalAgentFollowup-20261008.xcresult`。

本机工具链为 Xcode 27.0。新增生产观察代码的并发警告已修正；既有 Swift 5 兼容性警告仍可见，测试使用的受控可变捕获也有工具链警告。构建/测试的退出码与 xcresult 均成功，不能把日志中的 exit-code-0 诊断标题误判为测试失败。GitHub Xcode 26.3 的 [PR #30 门禁](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/37762816307)和[合并后 main 门禁](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/37763469452)均已成功。

隔离预览使用独立 bundle 身份和手写夹具，不替换正式 app、不启动实际 Personal Agent 读取，不授予辅助功能权限。已核对 native SettingsWindowController 与 SwiftUI Settings scene 两种入口、中英文、深色外观的共享卡片、默认关闭与 Dot 未支持说明，以及各启用/打开/权限按钮独立的辅助功能标识。预览已退出。

首版隔离预览期间，停靠/悬浮共享路由由自动化验证。Computer Use 的应用清单没有返回隔离 accessory app 的 Island 窗口，因此当时未完成两种 Island 列表的人工截图/键盘验证；也未完成浅色实际截图核对。后续正式安装副本的停靠列表实测见下方；悬浮截图/键盘完整验收仍开放。

当时未完成真实 AX 读取，观察默认关闭；后续在用户明确授权后安装并实测，记录如下。明确任务状态、多窗口、断网、锁屏/睡眠及 24 小时能耗对照仍未验证。Dot 独立任务来源未获得，不将普通 Codex 会话算为 Dot 验收。没有创建来源测试任务、发送消息或处理审批。#29 不因首版实验性界面观察合并而关闭。

## 2026-10-08 正式安装副本授权实测（原活动行布局）

用户授权更新 `/Applications/Mac Island.app`，并亲自在系统认证窗口解锁。macOS 设置中的旧权限条目虽显示开启，实际读取仍未被授权；通过系统界面移除旧条目并重新添加该正式副本后，当前副本读取正常。没有改写权限数据库、放宽签名要求或修改其他应用权限。

- Muse 的 7 条活动组合标签与原应用逐条一致；Grok Bot 的 1 条原生 Bot 名称一致。名称和正文只在内存核对，未写入仓库。
- Muse Activity → Approvals 后重新检查，7 条活动清空；回到 Activity 后恢复 7 条。分别暂停/恢复两个来源，只影响对应来源。
- 来源应用打开操作成功，反馈明确为打开应用，未宣称定位具体任务。Personal Agent 未进入最近记录。
- 来源应用运行、Island 设置在前台时两者均可读取；最小化短暂检查中 Grok Bot 曾读取失败后恢复。该记录不认证持续后台/最小化能力。
- 正式停靠列表已进行截图核对。原布局把 Muse 的每条活动显示为独立行，用户因此提出 #31 的 Bot 会话卡需求。

本机不含名称/正文的证据位于被忽略的 `build/personal-agent-acceptance.noindex/acceptance.json`；更长的真实验收及 Dot 来源继续由 #29 跟踪。

## 2026-10-08 Bot 会话卡自动化与预览（#31）

开发完成后集中运行 `./scripts/test.sh`：137 项 Prototype 测试通过，Release 构建通过；626 项产品测试中 625 通过、1 项真实 Cursor 数据库测试按离线约定跳过，0 失败。结果位于 `build/session-list.noindex/TestResults/MacIslandProductTests-20261008-091904.xcresult`。

新增回归覆盖七条活动只生成一张 Bot 卡、重复活动保留、源顺序不变、空 Activity / 切换侧栏仍保留可识别 Bot、缺失名称不借用活动/普通文本、精确身份区域匹配，以及同名不同窗口/面板保持独立。夹具计数也按 Bot 计算。

隔离预览使用独立 bundle 身份和通用夹具，真实读取禁用且没有授予权限。停靠列表实际显示两个 Bot 会话；Muse 卡片内的三条合成活动可展开、收起，重复项仍在卡片内，展开前后会话数均为二。已核对截图与独立活动按钮标识；预览正常退出并注销其应用登记。悬浮界面与键盘完整验收仍开放，不以共享视图或路由测试代替真实证据。

[PR #32 门禁](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/37788371646)与[合并后 main 门禁](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/37789156861)均成功。正式安装副本实际显示一张 Muse 卡、一张 Grok Bot 卡；当时 Muse 有八条原生活动，展开后八条组合标签逐条一致，展开前后的当前会话数均为三（另有一条普通 Codex 会话）。更新后通过系统界面重新登记同一个安装副本的既有权限，实际读取恢复；其他应用权限未修改。

这次真实核对发现 Muse 的名称仍缺失。初次平铺头部兼容虽通过三个受影响套件的 32 项合成测试，真实名称仍未匹配，不能视为完成。随后临时诊断只记录限定头部的控件角色与已知固定控件标签，没有记录名称、活动或对话内容；确认编辑控件由单子节点容器包裹，名称与 Connected 是另一容器中的两个直接静态文本。最终读取兼容这两个一层容器及平铺头部，仅允许最多两个身份文本叶节点，先验证全部角色再读取值；拒绝输入、私有区域、更深容器、额外文本和未知标记。诊断代码已移除，未扩大整段普通文本读取。

最终 Release 重新构建成功；只复查 PersonalAgentObservation、PersonalAgentMonitor、MacIslandFixturePlayer 三个受影响套件，34 项通过，0 失败、0 跳过、无运行时警告；结果为 `build/session-list.noindex/TestResults/BotNameNativeHeader-20261008.xcresult`。正式副本的最终名称核对、安装来源和合并检查证据记在 [#31](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/31)，真实名称和活动内容不进入仓库。

## 2026-10-08 Muse / Grok Bot 像素标识（#34）

设计与播放规则见 [客户端图标说明](design/mac-island-client-glyphs.md)。开发后集中运行一次 `./scripts/test.sh`：137 项 Prototype 通过、Release 构建通过；632 项产品测试中 631 通过、1 项真实 Cursor 数据库测试按离线约定跳过，0 失败、无运行时警告。结果为 `build/session-list.noindex/TestResults/MacIslandProductTests-20261008-221508.xcresult`。

原生设置预览发现 Muse 的细笔画在 24 pt 偏碎，因此仅调整像素几何为双像素笔画。最终 Release 再构建通过，只复查两个图标用例：悬停/运行状态分离、减少动态效果与静态能耗档、异常时间、固定轮廓、周期回环、Grok 斜切位移，2 项通过、0 失败、无运行时警告；未重复无关测试。结果为 `build/personal-agent-glyphs.noindex/FinalGlyphShape.xcresult`。

原生导出直接使用生产帧；透明 PNG/GIF 中，Muse 32 帧 / 3.2 秒，Grok Bot 42 帧 / 4.2 秒。逐帧解码确认透明轮廓不变且循环总时长正确。最终造型已核对 24、32、48 pt 与浅深背景；独立身份的合成预览核对了设置中的两个 24 pt 标识、对齐与辅助功能标签。预览已正常退出，构建副本改为非 `.app` 扩展名，避免增加重复启动图标。

本轮没有替换正式安装副本，也没有改变来源读取或授予新权限。图标已接入停靠/悬浮共享 Bot 卡片；Computer Use 的可访问窗口中只有预览设置窗口，未完成人工悬停和两种 Island 的截图核对，不把策略测试或导出动画当作这部分实测。既有编程客户端动画与真实来源持续观察仍沿用原有验收边界。

## 2026-10-10 Muse 6.0 与来源状态修复（#36）

问题复现时正式副本仍为 #33 的名称修复构建，未包含 #35 的像素标识。Muse 安装包已升级至 6.0；原 4.1 身份头部消失，当前聊天布局改用镜像头像入口。只读生产读取器复现：旧契约拒绝 Muse 6.0；Grok Bot 0.68.1 返回一张带原生名称的卡片，不能将 Grok 的现象误记成读取器故障。安装包原地更新还可能使已缓存的 Bundle 版本继续停留在旧值。

新版 Muse 的契约通过限定结构诊断、原生界面与安装包的公开控件实现核对：原生 Chat/Search/Settings 导航与相邻消息入口/两个同名头像按钮构成一张 Bot 卡。6.0 不读静态文本、标题值、消息入口后代或新版 Activity。版本检查在监控器、读取器及适配器均生效，4.1 和 6.0 不互相回退。已启用但不可读的来源显示明确状态，不伪造会话身份或计数。

实现完成后统一运行一次 `./scripts/test.sh`：137 项 Prototype 通过，Release 构建通过；639 项产品测试中 638 通过、1 项真实 Cursor 数据库测试按离线约定跳过，0 失败。结果为 `build/session-list.noindex/TestResults/MacIslandProductTests-20261010-031705.xcresult`。新增回归覆盖镜像控件去重、不同窗口保持独立、Side chats/输入/普通文本拒绝、未知版本与另一版契约拒绝、装饰不推断状态，以及读取缺失时保留来源状态而不增加会话数。

同一生产模型与读取器的只读实测返回：Muse 6.0 为一张卡片、名称可读；Grok Bot 0.68.1 为一张卡片、名称可读。只输出版本、结果、数量和布尔值，不把真实名称、活动或正文写入诊断或 Git。该读取器核对不替代正式安装副本验收；安装、权限与 GitHub 检查的最终结果由 [#36](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/36) 记录。后台、最小化、跨睡眠、完整多窗口和 24 小时观察能力仍未认证。
