# Mac Island 公开前检查 — 2026-10-31

**简体中文** · [English](public-readiness-2026-10-31.en.md)

## 迁移前复核记录

本文保留干净源码仓库建立前的检查时点。旧 SHA、PR #39、Issue #40 均属于
私有归档，不能用其检查替代新仓库 CI。迁移规则见[源码历史](source-history.md)，
当前结果见[GitHub 检查](https://github.com/Samadhi-Chi/mac-island/actions/workflows/pr-checks.yml)
及[Pages 部署](https://github.com/Samadhi-Chi/mac-island/actions/workflows/pages.yml)。

单次源码安全审查已完成，发现的问题已进入本轮修复；**现有仓库仍保持私有，尚未部署 Pages**。
完整 Git 历史中存在真实会话图片。当前版本删除图片不能清除旧版本，因此历史披露方式、
最终提交的 CI、历史隔离和公开配置核验仍是发布门槛。维护者已批准保留私有归档、
以审查后的源码新建同名独立仓库的方案；不重写共享历史。

审查基线为 `ae412ab9aa04fc48d956f41cc15df6689fcfcc8f`，分支为
`codex/mac-island-release-readiness`。修复仍在工作区，不能把基线检查当作最终提交检查。
默认分支为 `97db382ea72bcd42b1c329f97de4a160f21d9eb2`，交付沿用草稿 PR #39，
公开准备由 Issue #40 跟踪。本文不声明正式安装包已通过发行验收。

## 源码、依赖与历史审查

按维护者选择，停止未返回结果的多轮深度扫描，完成一次完整 Standard 审查。
已封存扫描 `118c1c2a-079c-4417-b86f-c4d8963f80d2` 覆盖基线全部 660 个跟踪文件，
报告 17 项有效发现：4 项中风险、13 项低风险。原报告保留，不把修复状态改写成
“扫描发现零问题”。详细证据、复现与修复记录留在仓库外的私有审查资料中。

本轮修复包括只读监控的审批边界、独立 stdio 连接和子进程退出、文件身份与读取上限、
生成脚本参数、日志内容和保留策略、数值边界、会话身份匹配、测试隔离与网络读取策略。
修复前和修复后各进行一次独立审阅；后者指出的额度别名/旧缓存和旧日志保留问题已修正，
对应回归通过。真实客户端和旧系统验收不由这些夹具替代。

| 检查范围 | 本次结果与限制 |
| --- | --- |
| 当前源码 | Gitleaks 8.30.1 扫描待提交源码导出；未发现匹配凭据。最终资产齐备后还需更新准确候选清单 |
| Git 历史 | 46 个可达引用、582 个提交、3,788 个唯一 blob；其中 3,330 个文本 blob 约 105.5 MB。提交差异及全部文本 blob 扫描未发现匹配凭据 |
| 历史压缩包 | 检查 ZIP/7z 清单及提取文本，未执行其中的文件，未发现匹配凭据 |
| 历史图片 | 全部图片版本的去重预览已复核；GIF 抽查首/中/末帧，并非逐帧审查。5 份真实或未经公开审阅的界面图片已从当前候选删除，旧 blob 仍可达，阻断公开 |
| GitHub 文字与日志 | 检查 21 个 Issue、19 个 PR 正文及取得的评论集合；扫描约 0.92 MB 元数据和 51 次 Actions 运行的约 14.36 MB 日志，未发现匹配凭据；自动扫描不等于逐句人工隐私判断 |
| GitHub 附件 | 8 份旧 xcresult 诊断附件已校验、私有备份并删除；远端复查为 0 个附件。未来 CI 仅导出固定数字字段，不上传 xcresult、崩溃诊断或截图 |
| 依赖 | Sparkle 从 2.9.1 升至 2.10.1，固定 revision 和二进制校验和；对照官方公告，更新完整随包许可。应用仍不启用自动更新 |
| 素材 | 保留上游 LICENSE/NOTICE 和字体许可。13 份未完成逐文件溯源且产品不使用的旧 WAV 已移出当前候选；源码及产物检查阻止重新夹带。历史素材另属历史披露范围 |

依赖依据：[Sparkle 官方公告](https://github.com/sparkle-project/Sparkle/security/advisories)、
[准确包版本声明](https://github.com/sparkle-project/Sparkle/blob/ab7d71291238df6e0492143b120c9b696a35f603/Package.swift)。
凭据规则没有命中，不代表图片无隐私内容、许可完整或系统不存在其他漏洞。

## 工程与验证记录

本机为 Apple Silicon / Xcode 27.1；CI 使用 macOS 15 / Xcode 26.3。
集中验证后仅在修复或新改动时重跑受影响检查。没有把分开执行的检查写成一次完整
`./scripts/test.sh` 成功；最终提交的 CI 尚待 GitHub Desktop 推送后运行。
原 PR 的旧系统设置对象析构修复继续保留，最终仍需 CI 的实际系统验证。

| 检查 | 实际结果 |
| --- | --- |
| Swift 格式 | 全部 342 个 Swift 文件统一规范并通过严格 lint；检查列表必须与实际 Swift 文件一一对应 |
| Release 与编译警告 | 修复后及音效移除后的 Release 构建均通过，无源码编译警告；新输出目录的产物许可核验通过，确认不含旧 WAV，专门的 1 项产物回归通过 |
| 语言与设置 | 修复显式语言仍选用系统语言资源的问题；语言、屏幕隐私和设置共 49 项通过，最新 Release 构建及许可检查通过，无源码编译警告 |
| 产品测试 | 首次 704 项：691 通过、12 失败、1 项既定 live Cursor 跳过。修复临时目录规范路径及断言后，受影响 6 组、63 项全部通过；不隐去首次失败 |
| Prototype | 首次 139 项中 1 项旧断言失败；修正后相关 2 项通过。后续旧日志保留修复的 11 项通过，含新增回归 |
| 发行工具 | 15 项夹具通过；源码和实际构建产物的完整许可一致性核验通过 |
| 真实 Codex CLI 隔离契约 | 临时 HOME/CODEX_HOME、无网络及真实账号数据，私有 stdio 的 initialize、initialized、空 thread/list 和子进程退出通过；不等于真实登录会话验收 |
| 生成辅助脚本 | 两份 IDE setup 的正常反馈、恶意参数和符号链接夹具通过；两份 statusline 的输出、权限和符号链接检查通过。未安装或调用真实 IDE，未覆盖无关聊天策略替换 |
| CI 汇总脱敏 | 对实际 xcresult 导出验证，仅含 schema、是否取得汇总和四项数字，无测试名称、错误、路径或诊断内容 |
| 首轮最终候选 CI | `037c4e9` 的 141 项 Prototype 通过；产品 710 项中 708 通过、1 失败、1 跳过。生命周期夹具依赖系统 Python 的路径已改为 POSIX 夹具，并修复 Xcode 26.3 的枚举协议隔离警告；受影响生命周期测试本机通过，等待新 head CI。附件配额未刷新，数字汇总改写到 Job Summary，不再上传测试附件 |
| 网站 | 12 页静态结构、全部本地链接及资源检查通过；真实浏览器检查 1280px 桌面及 390px 窄屏、语言切换、指南和键盘跳转通过，无横向溢出，六张截图正常加载。线上项目子路径 404 待部署后核验 |
| 正式发行 | 本轮未安装、签名、公证、发布安装包，未完成最低 macOS、Intel、睡眠恢复、多屏及最终签名版 Muse/Grok 实测 |

详细本机日志在忽略目录 `build/PublicationChecks/`，产品结果在 `build/TestResults/`。
日志和结果包不是网站内容，不能提交或上传为公开附件。

## 已验证的交付补充

修复后的最终 PR head `79a52bd` 已通过归档仓库的完整检查
[41198267999](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/41198267999)。
GitHub Desktop 随后将相同源码树 squash 并推送为 `10d925f`；对应的
[main 检查 41198728266](https://github.com/Samadhi-Chi/mac-island-private-archive/actions/runs/41198728266)
也通过：141 项 Prototype、15 项发行工具夹具、709 项产品测试通过，1 项既定
live Cursor 测试跳过。Release、许可、严格格式和网站检查通过，无源码编译警告。
以上私有归档检查是迁移来源证据；独立新仓库另有自己的 CI。
上文“待验证”描述的是较早的审查快照，不代表本补充记录的状态。

## 中英文页面与真实图片

README、离线帮助和隐私信息提供中英文；网站中文在 `site/`，英文在 `site/en/`，
每页都有对应语言入口。首页、指南、隐私、支持、许可和 404 共 12 页。
网站不使用第三方脚本、字体、分析服务、Cookie 或虚构下载链接。

配图必须截取真正运行的 Mac Island 原生窗口，使用英文/中文合成会话夹具，关闭真实
客户端读取和持久化偏好。已完成 6 张原生窗口截图，逐一核对不含真实用户名、项目或
对话；仅裁切和排版，没有重绘 UI。构建、夹具、语言与裁切范围见
[截图来源记录](website-screenshots.md)。

## 发布前剩余门槛

1. 通过 GitHub Desktop 提交、推送已审查改动，验证 PR 最终 head 和合并后 main 检查。
2. 执行已批准的私有归档与干净同名仓库方案；原仓库保留全部历史和 PR，新仓库
   只导入审查后的源码，重新编号 Issue/PR，并独立验证 CI。旧图片、音效档案和
   运行产物不进入公开历史。详细清单保持私有，不公开旧敏感 blob 的定位信息。
3. 为实际公开仓库配置并验证私密漏洞报告、分支保护、可用的密钥扫描及依赖提醒。
   未验证能力不写成已启用；若私密报告只能在公开后开启，须在同一发布操作中验证。
4. 披露门槛解决后公开仓库，启用 Pages 的 GitHub Actions 来源并只部署 `site/`，
   核实 HTTPS、项目子路径、所有页面和缺失路径的 404。

GitHub 历史清理还涉及 PR 引用和缓存，强推不是完整清除证明，参见
[敏感数据清理说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)。
公开会使 Actions 历史和日志可见，参见[可见性说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)。

本记录时网站尚未上线，项目地址为 `https://samadhi-chi.github.io/mac-island/`。
步骤见 [GitHub Pages](github-pages.md)，正式安装包条件见[发行准备](mac-island-release-readiness.md)。
