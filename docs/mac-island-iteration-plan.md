# Mac Island 开发与迭代计划

决策日期：2026-09-26。总跟踪：[GitHub #1](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/1)。
这是开发计划，完成情况以关联 Issue、PR 和[本轮验证与交付记录](mac-island-iteration-validation.md)为准。源代码和离线自动化已覆盖下列功能；真实客户端导航、系统场景及 CLI 执行认证单独保留待办，未验收版本只提供续接预览/复制。

2026-10-07 新增 [Personal Agent 接入开发计划](personal-agent-integration-plan.md)。Muse / Grok Bot 已有可选的实验性当前界面观察，2026-10-08 按 [#31](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/31) 改为每个可识别 Bot 一张会话卡，活动在卡片内折叠。持续任务状态、稳定身份和 Dot 独立来源仍由 [#29](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/29) 跟踪；不改变既有本地只读产品边界。

## 产品目标与已确认选择

把 Island 发展为可靠的本机会话入口：看见状态、回到目标、找回最近会话、修复自身监控连接，并在预览后调用客户端原生续接。

- 本轮不做发送消息、代做审批、停止任务或自动重启外部客户端。
- 保持静音、本机处理、无遥测、无自动更新、无 SSH 启动及无自动安装 hooks。
- 优先客户端顺序是 Codex、Cursor、Hermes；Hermes 优先桌面版。
- 最近会话默认保存 7 天、最多 200 条；设置中提供 24 小时/100 条、仅本次运行和清空。
- 续接先预览客户端、会话 ID、目录和命令，再由用户明确启动。
- 按独立 PR 交付；最新提交通过检查并完成差异复核后自动 squash 合并。
- 编译、测试和源代码交付不包含真实应用安装、启用 hooks、改写用户配置、签名、公证或发布。

## 基线与交付流程

开始时本地和远端 `main` 同为 `f5119e19527cdb4f572aab82b1f4770bb4d54557`，工作区干净。
历史验证记录不作为本轮测试结果。使用当前实际 Git 根目录，不沿用历史文档中的个人路径。

1. 每批从最新主分支建立 `codex/mac-island-<topic>` 分支，使用小范围、可解释的提交。
2. 实现和针对性测试后建立 Draft PR，关联子任务，写清行为、结果、限制和回滚。
3. 完整门禁通过、最终差异复核、审查意见处理完毕后标记 Ready。依赖改变或分支更新须重新验证。
4. 合并前检查实际 head SHA、base、检查结论和审查状态；用预期 head SHA 执行 squash，避免误合并新提交。
5. 检查合并后主分支 CI，再进入依赖该批次的工作。出现回归时停止依赖交付，使用 revert PR 保留历史。

遵守已有的更严格仓库规则。若权限和套餐支持，可要求 PR、`validate` 成功、分支最新，禁止强推和删除；单维护者不新增必须由另一人审批的阻塞规则。当前原生 auto-merge 关闭，规则集查询返回私有仓库套餐限制，管理级 branch protection 查询返回集成权限限制；`branches/main` 返回 `protected: false`。本轮用逐次检查执行合并，不声称已设置服务端保护，不购买套餐或改变可见性。

GitHub 操作优先使用已认证的连接器。本机 Git 若无凭据，不读取或输出凭据、不改用户级登录配置。提交的文件树必须与本地验证内容一致，PR 在当前任务附加，不能用逐文件提交代替可审查的完整批次。

## 十批交付

| 批次 | 跟踪 | 内容 | 关键验收 |
| --- | --- | --- | --- |
| 01 | [#2](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/2) | 协作规范、模板、计划、验证摘要与门禁清单 | 链接/脚本检查、共享门禁与 CI；保留禁用发布策略 |
| 02 | [#3](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/3) | Hermes 时间、OpenCode 恢复来源与身份 | NULL、缺列、过期、父子过滤、去重、事件接管 |
| 03 | [#4](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/4) | 类型化操作结果与一致反馈 | 精确定位/应用打开/请求发送/失败不混淆；鼠标和键盘一致 |
| 04 | [#5](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/5) | 返回目标、下一个需关注、打开项目、复制 ID、本地隐藏与快捷键 | 默认键位不变；新增未绑定；冲突可见；新事件恢复隐藏会话 |
| 05 | [#6](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/6) | 最近会话入口、索引与保留设置 | TTL、容量、损坏恢复、策略切换、隐私序列化 |
| 06 | [#7](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/7) | 只读健康快照、手动重连与有限重试 | 单一重试、休眠/锁屏暂停、取消、旧响应和能耗 |
| 07 | [#8](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/8) | Codex、Cursor、Hermes Desktop 首轮验收 | 版本矩阵、真实导航和准确降级；不把 URI 接受当作会话已显示 |
| 08 | [#9](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/9) | 预览后续接基础、Codex/Claude CLI | 目录、版本、参数转义、重复点击、无回执 |
| 09 | [#10](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/10) | OpenCode/Hermes CLI 续接 | 原生 ID、官方命令、来源隔离、版本验收 |
| 10 | [#11](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/11) | 生命周期、交互、隐私和文档收尾 | 完整门禁、真实场景记录、限制和交付清单 |

批次号码不是 PR 号码。各批同时更新受影响文档；重大能力变更更新 AGENTS.md。通常只维护一个主要开发分支，避免依赖交叉。

## 实现约定

### 恢复与身份

Hermes SQL 在选择、筛选和排序中统一使用 `COALESCE(last_activity_at, started_at)`，防止已选中的记录被读成 1970 年。恢复读取保持只读和元数据范围，缺少必要列时跳过，不扫描消息正文。

会话身份由客户端、原生会话 ID 与来源构成。OpenCode 的 CLI/Desktop 不能根据桌面进程是否运行统一推断。来源未知时显式保留未知状态，不允许可执行续接；真实事件到达后合并元数据，避免重复卡片。实时状态优先于旧恢复快照。

### 快捷操作与反馈

停靠和悬浮复用同一操作能力、请求和结果模型，区分精确会话定位、仅应用打开、请求已发送、不可用及原因。macOS 接受 URI 不证明目标会话实际出现。失败保留上下文并显示可理解的原因，避免无声关闭。

第 03 批实现使用 `SessionActionController` 统一列表点击/Enter、悬停与聊天入口，反馈由 `IslandOpenedContentView` 展示。点击保留面板内容，用户可关闭反馈；同一会话的在途导航不会重复启动，较旧请求不能覆盖最新操作或已关闭的反馈。`SessionLauncher` 保留 Bool 兼容方法供非产品调用，产品 UI 使用类型化结果。Terminal/iTerm 脚本确认目标时可报告终端定位；IDE URI、Codex URI、tmux 命令和 Ghostty 工作区回退只报告请求或应用级结果。该批自动化验证使用注入替身，不构成真实客户端导航验收。

本地隐藏只影响 Island 列表；不归档客户端、不删除数据库、不停止任务。后续新活动使会话重新可见。已有 Option+J/L 与用户自定义设置保持；新增“直接返回目标”和“下一个需关注”默认无快捷键，通过设置绑定。沿用现有上下键/Enter、稳定会话选择和全局快捷键去重逻辑，显示注册失败。第 04 批通过会话行菜单、悬停菜单与详情快捷操作提供目录打开、原生 ID 复制和本地隐藏；隐藏保留 SessionStore 状态，仅在新活动后复显。“下一个待关注”在 Island 中循环查看详情，“返回会话窗口”调用共享导航并显示实际结果。

### 最近会话

建立独立版本化、白名单字段的索引，原子写入。仅保留路由所需客户端、原生 ID、来源、目录、时间等元数据，不序列化整个 SessionState，不存对话、工具内容或内容派生标题。现有关联缓存缺少时间，不据此伪造历史保留期限。

保留策略由设置控制：7 天/200 条、24 小时/100 条、仅本次运行、不记录。进入不持久化模式时清除新索引文件；清空只处理 Island 索引，不影响原生客户端历史。损坏文件按空索引恢复。主列表 30 分钟自动隐藏与最近列表保留是独立规则。

只使用已有可信观察和文档允许的元数据来源；不为补历史扫描正文。未知来源仅提供信息，直到后续权威事件识别来源。

第 05 批接入 `RecentSessionIndex`、`SessionMonitor` 观察/维护与通用设置，列表支持当前/最近切换，当前为空时仍可从停靠或悬浮进入最近列表。记录只显示目录、客户端、原生 ID 和时间；鼠标与上下键/Enter 使用共享导航反馈，目录打开和 ID 复制复用快捷菜单。清空记录保存时间截止点以阻止旧数据重填，停用后重新启用从新活动开始；未知来源不会调起客户端。首版只收录已有观察与恢复元数据，不扫描客户端对话正文补全历史。

索引测试覆盖容量、过期、损坏、字段白名单、清空后重启、停用/仅本次运行、来源去重、未来时间与路径校验；清空/停用的截止点包含已接受的轻微时钟偏差，Cursor 本地来源规范为桌面会话。悬浮预览中明确进入最近列表会固定该列表，当前任务结束不会将其收起。实际客户端和外观交互验收仍以最终验收记录为准。

### 监控健康与重连

健康快照包含状态、最近成功读取、最近事件与错误；没有新事件不等于断开。健康查询不安装 launcher、不改配置，安装/修复仍通过明确操作执行。

手动重连只重新建立 Island 拥有的监听、订阅和只读读取器。真实连接故障使用单个指数退避任务，间隔上限 60 秒，不能因多次点击创建多个循环。遵循 EnergyGovernor，休眠/锁屏期间暂停，唤醒后重新校验。取消/代次防止旧响应覆盖新状态。不得终止外部客户端进程或顺手重装 hooks。

### 桌面客户端与续接

- **Codex Desktop**：官方线程 URI，区分请求接受和真实定位结果。
- **Cursor**：已验证的项目窗口或终端定位；没有接口证据时不承诺指定 composer 精确打开。
- **Hermes Desktop**：应用唤起、最近元数据恢复和 ID 展示为首要路径。当前安装包未注册 URL scheme；这只说明本机该版本的能力边界，不能推断未来版本。不自动把桌面记录转为 CLI；未验证官方接口前不启用精确桌面续接。
- **CLI**：独立用户操作服务，观察层继续只读，旧 writable runtime 不开启。点击时重新校验客户端、原生 ID、可执行文件/版本、目录与 worktree。已知存在的会话优先导航；新续接先预览，再在 Terminal.app 新窗口执行，可单独复制命令。命令采用结构化参数和严格引用，不附加 prompt、审批绕过参数或历史输入，不跨客户端转换。单会话单次在途请求；没有回执时如实显示已请求，不报已恢复。

官方命令参考：Codex `codex resume <id>`、Claude `claude --resume <id>`、OpenCode `opencode --session <id>`、Hermes `hermes --resume <id>`。实现前核对实际版本能力；没有验收证据的适配器只提供信息/复制，不默认执行。

## 验证与交付证据

共享门禁是 `scripts/test.sh`：串行 Prototype、Release 和选定产品套件；live Cursor 测试保持显式开启。逐步将快捷键、焦点、能耗、共享路由和受影响的悬浮产品测试纳入门禁，不把旧上游非产品行为的整套测试误当成当前规范。

覆盖恢复边界、选择与动作失败、缓存 TTL/容量/损坏、敏感字段不落盘、重连取消/休眠、续接参数和缺失目录等实际行为。交互验收包括停靠/悬浮、多屏、浅深色、键盘和可访问性；会话事件仍然不自动展开详情。

真实客户端用专门测试会话，记录客户端版本和结果。构建、单元测试和合成夹具分别报告。环境或授权边界阻止真实检查时记录未运行，不把模拟通过写成真实验收。功能适配器未验收时默认关闭执行能力。

最终交付包含关联 PR/Issue、主分支 CI、兼容性矩阵、测试记录、已知接口限制和回滚方法。开发期间的参考文档：

- [Codex commands](https://learn.chatgpt.com/docs/reference/commands)
- [Codex developer commands](https://learn.chatgpt.com/docs/developer-commands)
- [Claude CLI](https://code.claude.com/docs/en/cli-reference)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
- [Hermes sessions](https://hermes-agent.nousresearch.com/docs/user-guide/sessions)
- [Hermes Desktop](https://hermes-agent.nousresearch.com/docs/user-guide/desktop)

外部接口会变化；链接是能力核对入口，不等于每个当前安装版本已被验证。

## 第 06 批实现说明

集成设置新增监控连接区域，显示 Codex 连接状态、最近成功读取和最近事件、固定类别错误与重试间隔。无新事件不产生故障；健康信息只在内存中保存，错误不会复制原始响应正文。手动重连只替换 Island 的订阅。Bridge 检测不再安装 launcher，修复仍由现有显式安装/重装操作执行。

Codex 的连接尝试去重，断线/请求超时采用单个重试任务，间隔为 1、2、4、8、16、32、60 秒并封顶。真正的数据读取成功后才重置退避，单独握手成功不会掩盖连续的会话列表超时。每个连接带有代次，替换、停止、休眠/锁屏使旧请求与接收循环失效；请求最多等待 10 秒。失败时立即释放旧连接尝试，避免尚未返回的历史文件读取吞掉下一次重试；旧连接持有的审批请求也会清除，由新连接的状态重新判断是否需要关注。EnergyGovernor 恢复后建立新连接并重新读取会话列表，正常轮询继续使用现有能耗策略。只在停止监控时清理 Island 自己启动的 app-server 子进程；手动重连与暂停不终止外部客户端或自有服务。

验证覆盖单次连接、重复失败、退避上限、取消与旧响应、睡眠/唤醒、静默健康，以及健康检查不创建或改写 launcher 的临时夹具。另用内存 WebSocket 驱动真实监控 actor，覆盖初次历史读取未返回时断线重试、会话查询暂停后收到旧 guardian 通知、重连清除旧审批，以及握手成功但列表连续超时；测试显式禁止启动 app-server。真实断网、系统锁屏和应用界面验收仍须单独记录；离线自动化不代表真实客户端验收。
