# Mac Island 发行准备

本记录对应 2026-10-15 的发行准备工作。当前开发检查与受影响回归已完成，尚未公开发行；构建、合成测试和隔离界面检查不表示已通过正式签名、公证或真实安装验收。证据和未完成条件见下文。

## 范围与渠道

本轮完成可分发版本的准备和公众使用体验，不加入收费、许可证激活或订阅。应用继续保持本机、静音、只读观察；不代做审批、发送消息、启动代理任务，不启用遥测、自动更新或 SSH 服务。

已准备独立下载所需的候选打包方向。这里的“官网分发”指用户从受控下载页取得经过 Developer ID 签名和 Apple 公证的安装包，不要求先开发复杂网站，也不意味着已配置域名。公开下载、隐私页和支持方式仍待确定，应用内帮助与许可可以离线使用。

用户已询问 Mac App Store 路线；本轮没有切换到商店发行，也没有提交审核。现有 `PingIslandAppStore` 目标及 `mac-app-store-submission.md` 保留了上游身份和历史记录，不能作为 Mac Island 已获审核批准的证据。

| 能力 | 独立下载方向 | Mac App Store 需要处理的事项 |
| --- | --- | --- |
| 顶部/悬浮 Island、像素图标、屏幕隐私、离线帮助 | 保留 | 界面本身没有已识别的核心阻碍 |
| Muse/Grok 跨应用辅助功能读取 | 继续作为显式启用的实验功能 | 当前跨应用 AX 读取方式与 App Sandbox 不兼容，需要替代来源或移除这部分能力 |
| Cursor、Codex rollout、OpenCode/Hermes 本机文件与数据库 | 保留现有只读来源 | 当前直接访问 home 下的路径；需按来源设计用户选定目录、安全作用域书签、拒绝与授权失效处理，不能一概判定不可行 |
| Codex 自动连接 | 保留自己持有的只读观察子进程 | 外部 `codex app-server` 的可执行文件访问、沙盒继承、数据目录和本地监听均需实测；当前商店权限只声明 network client，不能保证原样连接 |
| Hooks / Bridge / 插件安装 | 操作保持显式、带备份 | 已有目录授权代码，但当前要求整个 home；向应用外写入脚本、JS/Python 插件供另一客户端运行，仍有沙盒适配和审核风险，目录授权不等于可获批准 |
| 打开客户端和官方会话链接 | 保留 | 通常可使用公开应用打开方式；接受链接仍不代表正确会话已显示 |
| 精确恢复最小化窗口、切换 IDE 窗口或终端标签 | 按现有能力和授权执行 | AX 窗口控制受限，商店分支已有禁用路径；终端 AppleScript 需逐目标核实自动化权限和沙盒配置，可能降级为只打开应用 |
| 更新与购买 | 当前均未启用 | 商店更新、付费协议和商店购买规则需独立设计；开发者会员不等于已完成这些事项 |

商店要求的依据为 [Apple App Sandbox 文档](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)、[沙盒文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)及[审核规则 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)，于 2026-10-15 核对。以上是当前源码与规则的对应评估，未运行完整沙盒功能验收，也不是 Apple 审核结论。CLI 续接执行目前本就未认证，不能将其描述为切换商店渠道才失去的能力。

## 本轮实现

### 首次使用和演示

- 首次引导独立于自动集成安装，分为展示位置、连接客户端、查看已有连接状态三步。可以跳过和重新体验。
- 新安装标记在 Settings 默认值迁移之前准备；已有安装不因升级被强制重新引导。
- 状态页读取既有连接及安装状态，不安装配置、不申请权限、不启动客户端任务。
- 监控演示使用独立模型和窗口，展示运行、需关注、完成，以及顶部/悬浮形态；不向 SessionStore 或最近索引写入模拟会话，不提供虚假的 Island 内审批流程。

相关入口：`Models/MacIslandOnboarding.swift`、`UI/Views/MacIslandOnboardingView.swift`、`Services/Hooks/HookWalkthroughDemoRunner.swift`。

### 屏幕隐私

`ScreenPrivacyStore` 提供共享、可观察的三级显示策略：只显示状态、显示标题、显示详情。新安装默认为标题；已有产品预设的安装保留原详情方式，用户后续选择不被迁移覆盖。

这里的升级迁移针对同一应用偏好域。正式发行应优先保持已安装版本的稳定 Bundle ID，`local.*` 前缀本身不要求更换身份；若主动切换身份，必须单独处理偏好与系统权限迁移，并完成真实升级验收。

临时隐藏切到只显示状态，仅存内存；恢复时返回用户当前选定的级别。限制模式不构建原始聊天、悬停和通知详情子树；两种 Island、当前/子任务/最近行、Bot 名称和活动、闭合文本、已打开的元数据与续接窗口遵守同一限制。标题模式只接受原生标题，不从正文、提示词或目录推导标题。此设置不改变原客户端，也不停止底层监控。

相关入口：`Models/ScreenContentVisibility.swift`、`UI/Components/ScreenPrivacyViews.swift`、`UI/Views/IslandExpandedRoute.swift`。

### 诊断、帮助和许可

主动诊断导出通过 `MacIslandDiagnosticsReport` 的类型白名单生成：应用/macOS 版本、Codex 固定连接状态及故障分类、实验来源启用状态/固定状态/纯数字版本。`DiagnosticsExporter.exportArchive` 的产品分支在旧收集器之前返回，不复制客户端配置、日志、索引、路径、会话或凭据。生成的包留在本机，由用户决定是否分享；旧诊断文件不会因此被自动删除。

“关于”提供离线使用帮助、隐私说明和第三方许可。随包包含完整 Apache LICENSE、NOTICE、字体许可及锁定 Sparkle 依赖的许可与外部声明；不是仅提供一个网页链接。资源和清单的核对方式见[许可说明](third-party-notices.md)。公开链接未配置时保持缺省，不使用假地址或上游产品支持入口。

相关入口：`Services/Diagnostics/MacIslandDiagnosticsReport.swift`、`Models/MacIslandDocumentation.swift`、`Resources/Legal/`。本轮不改变 Sparkle 服务禁用状态。

## 候选包准备

`scripts/prepare-mac-island-release.py` 是本轮的新候选准备入口。将 `Config/Distribution.example.json` 复制为被忽略的本机配置，填写自己的生产 Bundle ID、Team、Developer ID 证书显示名、Keychain 公证配置名称、版本/构建号和真实的支持及隐私 HTTPS 地址。网站首页可暂不配置；不要在 JSON 中写密码、私钥或 API 凭据。

首次公开发行的只读预检：

```sh
python3 scripts/prepare-mac-island-release.py \
  --config Config/Distribution.local.json --first-public-release
```

后续发行使用 `--previous-manifest <上次分发的 manifest.json>` 替换 `--first-public-release`。二者必须且只能选一项。前一版的产品身份、版本与构建号须匹配保存的收据，构建号必须递增。

预检核实严格配置字段、非占位的 HTTPS 地址、生产身份、本机可用 Developer ID、版本、干净源码、许可清单和产品约束。不构建、不签名、不上传；网页实际可达性与公证凭据可用性留在显式执行阶段检查。配置缺项时必须停止，不能把占位信息的产物标为可发行。

具备发行身份和授权后，在同一命令上增加 `--execute`，可用 `--output <新的候选目录>` 指定产物位置。执行会构建 universal Release，写入候选版本、公开链接与来源信息，依次签名嵌入代码和应用，检查 Developer ID/Team、hardened runtime、时间戳和架构，再执行应用公证、票据与 Gatekeeper 核验，并生成 ZIP/签名公证 DMG 和 SHA-256 清单。失败会保留 `INCOMPLETE.txt`，不得分发。

公证会上传候选内容到 Apple；该流程不创建公开 GitHub Release、不发布下载、不安装或启动本机应用。运行时链接与发行配置必须是真实配置，不提交签名身份或凭据。公证与签名结果仍须由本次实际执行证据确认，脚本实现本身不等于候选包已获 Apple 接受。

普通 `./scripts/test.sh` 仍用于开发验证，不触发签名、公证或发布。保留的 `package-release.sh`、`create-release.sh` 和禁用的上游发布工作流不是当前产品的发行入口。

## 统一验证记录

按本轮要求，开发完成后集中执行一次适用检查；修复失败或出现新改动时，才补跑受影响检查。现有历史测试记录不代替当前候选结果。

| 检查 | 当前状态 | 记录要求 |
| --- | --- | --- |
| Prototype、Release 构建、产品测试门禁 | **开发检查完成，CI 待 PR 最终头** | 137 项 Prototype 通过，Release 构建通过；产品 687 项首轮 685 通过、1 跳过、1 新夹具失败，修正后受影响的 63 项窗口测试通过。不是一次全部通过的 687 项运行，详见下文 |
| 首次使用、升级、跳过和重新体验 | **自动测试与引导预览通过；真实升级待验收** | 12 项引导测试覆盖隔离默认值和迁移；手动核验重开三步引导，预览状态页不读取真实连接 |
| 三级隐私、临时隐藏、两种展示形态 | **自动测试通过；完整实机场景待验收** | 8 项隐私测试及共享路由、窗口测试；设置中的临时隐藏/恢复已检查。尚未宣称完成多屏、投屏及全部真实客户端组合 |
| 演示隔离和诊断白名单回归 | **自动测试和演示预览通过** | 演示独立模型测试、手动查看顶部/悬浮及三个阶段；2 项诊断测试检查允许字段与实际合成 ZIP 内容，不导出真实客户端配置 |
| 源码和 Release 应用中的离线文档/完整许可 | **通过** | 源码、构建资源及实际 Sparkle artifact 许可逐字核验；4 项文档测试；离线帮助界面检查。正式签名安装包仍待生成 |
| 候选脚本离线预检和失败分支 | **15 项合成测试通过** | 覆盖配置、版本、身份占位、路径与最终产物检查等边界；不等于已经执行真实签名、公证或挂载最终发行 DMG |
| Developer ID 签名、嵌入代码验证、Apple 公证与票据 | **Pending** | 本轮尚无已验证可用的发行签名身份，也未完成真实签名公证 |
| 下载隔离属性、Gatekeeper 首次启动及升级安装 | **Pending** | 使用实际候选包；特别核实开发身份到生产身份的偏好与权限迁移，构建或启动开发版不算通过 |
| macOS 14 和 Intel 真实设备 | **Pending** | 部署目标/架构声明不等于实机证据 |
| 24 小时运行、睡眠恢复、耗电及多屏 | **Pending** | 记录设备、时段、场景及实际结果 |
| Muse/Grok 权限迁移与真实界面显示 | **Pending** | 以目标版本和最终安装签名重新核实；辅助程序读取成功不代替安装版验收 |

本机工具链为 macOS 27.0.1 / Xcode 27，Apple Silicon。开发检查位于分支 `codex/mac-island-release-readiness`，CI 使用 Xcode 26.3；最终提交和 CI 结果以关联 PR 为准。

本机日志保留于忽略目录 `build/release-readiness.noindex/`：`product-gate.log` 为集中门禁，`resource-rebuild.log` 为界面文案修正后的 Release/许可复核。首轮结果为 `build/session-list.noindex/TestResults/MacIslandProductTests-20261015-151102.xcresult`。新布局测试把刚创建的 idle 会话计入十分钟内完成预览，修正夹具为十五分钟前活动后通过；生产布局逻辑未因此改动。

第一次窗口补查与桌面手动操作重叠，原有悬停可见性测试失败（62 通过 / 1 失败）。停止界面操作后，该套件 63 项全部通过，证据为 `build/session-list.noindex/TestResults/ReleaseReadinessWindowQuiet-20261015.xcresult`，未放宽断言。全量门禁中跳过的是明确禁用的真实 Cursor 数据库检查。没有为获得绿色结果反复运行全量测试。

手动预览使用临时独立应用身份与测试环境变量，未替换 `/Applications` 中的安装。核验了引导、演示、设置隐藏/恢复及离线帮助；旧预览实例曾因界面工具重新激活而启动普通只读观察，已正常退出，随后在明确显示“Preview mode: no live connections read”的实例完成引导验收。未安装 Hooks、发送消息、执行审批或授予新权限。英文设置中仍有历史未翻译标签，完整中英文字面验收列为正式发行前收尾事项。

## 公开发行前的剩余条件

1. 统一门禁及实际候选包核验完成，最终 PR 头和合并后主分支检查通过。
2. 确定正式应用身份、版本/构建号与签名凭据，完成 Developer ID、公证及安装/升级验证；身份资料只保留在本机受控配置。
3. 提供真实的公开下载/隐私说明与支持方式。域名、邮箱、账号和页面不能由占位信息替代；本轮未发布任何页面。
4. 完成上表真实场景，或明确收窄首发系统、架构和客户端兼容范围。实验来源不能宣传为完整后台代理监控或已认证任务恢复。
5. 收费、购买试用、许可证、退款和商店提交保留为后续独立阶段。

GitHub 用于 Issue、分支、PR、代码审查和验证记录。按 [CONTRIBUTING.md](../CONTRIBUTING.md) 使用 GitHub Desktop 维护本地 Git 工作流；源码合并与产品公开发行保持独立。
