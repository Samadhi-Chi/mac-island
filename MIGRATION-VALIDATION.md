# Mac Island 本机迁移验证

## 最新结果（2026-09-20）

- 当前源码提交 `9d5584b03904d276b99a400ee0015880347ea7c1` 的 [GitHub CI 35457362426](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/35457362426) **成功**：Xcode 26.3 / Swift 6.2.4 / macOS 15.7.9；Prototype **136/136 通过（3.435 秒）**；Release 构建通过；28 组产品测试 **365 项：364 通过、0 失败、1 预期跳过**。跳过项为不读取本机真实 Cursor 数据库的 opt-in 测试。
- 析构修复影响的 `ObservedSessionRecoveryTests` 本机补验 **3/3 通过，0 失败、0 跳过**，命令退出 0，耗时 89.82 秒。没有重复本机已通过的全部产品门禁。
- 同一源码的独立 GitHub 克隆 Release 重建 **退出 0，95.80 秒**；独立 DerivedData/ModuleCache，无本机 Local.xcconfig，工作区干净；内嵌 bridge 可执行，临时重签后的严格签名检查通过。
- 本机额外串行 Prototype 补验出现一次辅助器停滞，**未计为通过**：254.61 秒后中止本次自有测试进程，退出 1。采样显示 `islandBridgeWaitsForSplitJSONPayloadBeforeContinuing` 停在 Foundation `Process.waitUntilExit`，当时该辅助器没有存活子进程；不能据此断言产品逻辑故障。保留原本机完整 136 项通过结果及最新云端串行 136 项通过证据，Prototype 产品源码未因本轮 CI 修复改变。随后仅对同一 split JSON 测试进行一次 60 秒上限复测，**1/1 通过（测试 0.446 秒，命令 4.95 秒）**，没有修改测试辅助器，也未重跑全部 136 项。

最新证据：`github-ci.json`、`github-ci-deinit.log`、`github-ci-deinit-test-summary.json`、`recovery-unit-retest.log.json`、`recovery-unit-retest-summary.json`、`fresh-clone-deinit-verification.json`。补验中止证据：`prototype-serial-retest.log.json`、`prototype-serial-sample.txt`、`prototype-serial-interruption.json`；后续单项通过证据为 `prototype-split-json-retest.log` 及相邻 `.log.json`，均位于下述外置日志目录。

## GitHub CI 失败与修复记录（历史）

Run `35453462937`（源码等价提交 `4dc43cd`）的正式结论是 `cancelled`，GitHub annotation 明确记录超过 45 分钟执行时限，不能记作通过。日志显示 Prototype 的 136 项测试并行启动，仅 67 项完成，之后 44 分钟没有进展；Release 编译及 28 组产品测试尚未开始。记录：外置日志目录的 `github-ci-35453462937.json`、`github-ci-job.json`、`github-ci-annotations.json` 与 `github-ci.log`。

原型测试包含在协作式执行线程中阻塞的套接字监听、读取和子进程等待；小核数 runner 同时启动这些夹具时存在执行线程耗尽风险。本次最低门禁调整是在共享脚本的 Prototype `swift test` 命令加 `--no-parallel`，保留全部 136 项及后续全部产品测试，不延长执行时限、不修改产品逻辑。串行选项见 [Apple Swift Testing 文档](https://developer.apple.com/documentation/Testing/Parallelization)。最新云端完整串行结果及本地补验中止边界见上方最新结果。

串行门禁提交 `fdbf615` 的 run `35456259012` 中，Prototype **136/136 通过，耗时 4.550 秒**，没有再次卡住。后续 Release 编译在 `MacIslandConversationDetail.swift:148` 失败：runner 默认 Xcode 16.4 不支持工程使用的默认 MainActor 隔离设置。本次将 CI 的 `DEVELOPER_DIR` 显式固定到已安装的 Xcode 26.3，并输出工具链版本；没有修改已在本机通过的产品隔离逻辑。[该次 GitHub 官方镜像清单](https://github.com/actions/runner-images/blob/macos-15-arm64/20260907.0337/images/macos/macos-15-arm64-Readme.md#xcode) 同时列出默认 16.4 和可用 26.3。后续固定工具链的完整结果见上方最新结果。日志为 `github-ci-serial.log`，结构化结果为 `github-ci-serial.json`。

固定 Xcode 的提交 `eddfa71` / run `35456506941` 确认使用 Xcode 26.3、Swift 6.2.4：Prototype **136/136 通过（4.129 秒）**，Release 与产品测试编译通过。xcresult 实际统计 **365 项：361 通过、1 预期跳过、3 崩溃**；3 项均属于 `ObservedSessionRecoveryTests`。三份崩溃报告均指向 `ObservedReadOnlySQLiteDatabase.__deallocating_deinit → swift_task_deinitOnExecutorMainActorBackDeploy → TaskLocal::StopLookupScope` 的释放错误。针对这个私有包装类增加空 `nonisolated deinit`，避免无业务工作的析构进入旧 macOS 回退路径，保留其余 MainActor 隔离及 SQLite 只读打开方式。唯一两个成功创建调用点 `loadOpenCode` / `loadHermes` 均有 `defer { database.close() }`；打开失败路径也立即关闭非空句柄，不将关闭资源推迟到析构。修复提交 `9d5584b` 的本机 3 项、云端完整门禁和独立 clone Release 重建现已全部通过，见上方最新结果。证据：`github-ci-xcode26-test-summary.json`、`github-ci-xcode26-crash-summary.json`、`CI-Xcode26-failures/`。

日期：2026-09-19。正式路径：`/Users/example/Developer/GitHub/Samadhi-Chi/mac-island`。以下只记录本次验证，旧 Desktop 来源未修改。

## 首次本机门禁与启动（历史基线 b0e547e）

- 初次三轮 Prototype 测试均通过：每轮 136 项、0 失败。外置 scratch 下的 bridge 定位已实际执行。
- 初次正式 release 编译在嵌入 bridge 阶段失败：Swift 6.4 把产物放在 `out/Products/Release`，旧脚本只匹配小写 `release` 目录。已改为使用同一构建参数下的 `swift build --show-bin-path`，避免依赖工具链内部目录布局。
- 第二轮门禁的正式 release 已通过，确认 bridge 路径修复有效。产品测试在编译阶段失败，尚未执行测试：三个异步 `Sendable` 协议被新工具链推断为 `MainActor`，跨模块的 actor 测试替身无法遵循它们。已给 `SessionRuntime`、`RuntimeCoordinating`、`TelemetrySink` 显式标记 `nonisolated`，保留各实现 actor 的隔离及所有测试；这采用 Swift 6.1 已实现的 [SE-0449](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0449-nonisolated-for-global-actor-cutoff.md)。
- 协议修复后的统一门禁通过：退出码 0，耗时 285.30 秒；Prototype 136 项通过，Release 编译通过，28 组产品测试共 365 项，364 通过、0 失败、1 跳过。唯一跳过项为明确不读取本机真实 Cursor 数据库的 opt-in 验证。
- 正式 App 按现有 unsigned 包装策略临时重签，严格签名检查通过。使用 fixture 和 `PING_ISLAND_UI_TEST_MODE=1` 启动，原生设置窗口与侧边栏正常显示，“仅在主动交互时展开”保持锁定开启。未启动真实监控、安装 hooks、启用登录项或授予权限。点击“退出应用”正常退出，进程已消失。
- 本次构建、自动测试、基本设置窗口启动/退出均通过。真实客户端集成、实时会话监控、完整 Island 交互与发布签名不属于本次启动验收范围。

## 本次重建

- 保留上游 Git 历史及原工作区改动；正式开发分支规范为 `main`，旧主分支保留为 `upstream-baseline-main`。只读 `upstream` 与个人私有 `origin` 分离，未重写历史。
- 移除旧 `/Users/Shared/Dev` 账户激活依赖；统一开发入口为 `scripts/test.sh`。缓存、DerivedData、测试结果和依赖目录支持 `BUILD_ROOT`，并发默认 2，XCTest 串行运行。
- 本机忽略配置 `Config/Local.xcconfig` 使用 `local.junkdog` bundle 前缀和空签名团队；仓库保留无账户信息的示例与通用默认配置。真机和发布签名未配置。
- Prototype 测试显式取得 bridge 目录；发布 helper 也使用 SwiftPM 返回的真实目录。门禁保留原 28 组产品测试，关闭读取真实 Cursor 数据库的 opt-in 测试。
- CI 调用同一门禁，仅授予源码读取权限。旧自动打包发布流程改名为 `release-packages.yml.disabled`，不会因首次 main push 执行发布。
- 旧 release zip、profiling 数据及旧本机配置按 [ARCHIVE.md](ARCHIVE.md) 归档并验证 SHA-256；README 图片、第三方许可与源码保留。

## 证据与边界

- 日志目录：`/Volumes/backup/Development/Logs/Dev-Migration-2026-09-19/mac-island/`
- 初次门禁：`product-gate.log`；bridge 修复后：`product-gate-swift64.log`；协议修复后：`product-gate-actor-protocols.log`。相邻 `.log.json` 记录命令、时间和退出码。
- 缓存与结果：`/Volumes/backup/Development/BuildData/Dev-Migration/mac-island/`，每次产品测试的 `.xcresult` 保留在 `TestResults/`。
- 初次完整产品门禁结果：`TestResults/MacIslandProductTests-20260919-235115.xcresult`；临时签名日志 `local-signature.log`；启动记录 `startup.json`。
- 所有 Swift/Xcode 构建与测试经本机共享构建锁运行；只读解析现有结果不占构建锁。未安装 hooks、注入客户端配置、启动真实会话监控或执行发布。
- 工程当前沿用 Swift 5 语言模式；新工具链会报告现有 actor 隔离警告，切换 Swift 6 语言模式仍需单独处理。

## GitHub 独立克隆重建（历史与最新源码）

2026-09-20 从私有 GitHub 仓库取得的独立克隆完成 Release 重建，退出码 0，耗时 176.49 秒。实际构建源码提交为 `b0e547e16db674c4deba8e0e645328d881b017de`；上述本机完整产品门禁也基于该源码。之后的 `4dc43cd30028b08e1ffbc3d180cd358aa2a38d2a` 仅修改本验收文档，未改变受测源码；本节补录同样不包含代码变更。

克隆路径为 `/Volumes/backup/Development/Validation/Dev-Migration-2026-09-19/mac-island`，使用独立 `FreshClone/DerivedData` 与 `FreshClone/ModuleCache`，只共享已下载的依赖缓存，没有复用正式副本的编译产物。克隆中没有本机 `Config/Local.xcconfig`，仅用仓库内通用默认配置即构建成功；Git 工作区保持干净。App 内 `PingIslandBridge` 完整且可执行，临时重签后的严格签名检查通过。未重复已经通过的全部测试或基本启动。

证据为日志目录中的 `fresh-clone-release.log`、相邻 `.log.json`、`fresh-clone-signature.log` 和 `fresh-clone-verification.json`。远程 CI 与后续仅文档提交状态由总体迁移记录追踪。

2026-09-20 析构修复后，独立克隆更新到 `9d5584b03904d276b99a400ee0015880347ea7c1` 再次完成 Release 重建，95.80 秒、退出 0。仍使用上述独立缓存与通用仓库配置；严格临时签名验证、bridge 可执行性、无 Local.xcconfig 和干净工作区检查均通过。证据为 `fresh-clone-deinit-release.log`、相邻 `.log.json`、`fresh-clone-deinit-signature.log`、`fresh-clone-deinit-verification.json`。后续仅修改本验收文档的提交不改变这些受测源码。
