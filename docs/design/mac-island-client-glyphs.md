# Mac Island 客户端像素图标

日期：2026-10-08

实现：`PingIsland/UI/Components/MacIslandClientGlyphView.swift`；Muse/Grok Bot 的共享帧：`PingIsland/UI/Components/MacIslandPersonalAgentPixelArt.swift`

## 最终选型

### Claude Code：B

- 十二条交错的珊瑚色像素边线，保留 Claude 原始标识的放射感。
- 不旋转；工作中以 2.9 秒周期缓慢向中心收缩，再由中心柔和释放。
- 收缩阶段降低边线高度和透明度，释放阶段只放大中心像素块。

### OpenCode：E

- 黑、白、灰三阶像素组成 `【 】` 结构。
- 工作中以 1.65 秒周期仅沿水平方向向内、向外移动。
- 不缩放、不旋转、不闪烁，避免与既有 Codex/Cursor 动效重复。

### Hermes：A

- 紫色短发头像与耳机分层绘制，耳机不与主体粘连。
- 面部只保留两枚小型浅紫像素眼；没有嘴巴、瞳孔或高光。
- 眼睛以 4.6 秒周期进行两次短促眨眼，闭眼时轻微横向展开。
- 耳机以 1.8 秒周期独立上下浮动，主体保持稳定。

### Muse：蓝色手写 M

![Muse 动画](../images/client-glyphs/mac-island-muse-pixel.gif)

- 16 × 16 像素网格，以有间隔的斜笔画保留蓝色手写 M 的识别特征。
- 固定轮廓与两阶蓝色，3.2 秒周期的浅蓝光带从左向右穿过；循环两端回到静止蓝色。
- 不整体缩放、旋转或闪烁。蓝色仅表示客户端身份，不表示运行或安装状态。

### Grok Bot：灰色斜切头像

![Grok Bot 动画](../images/client-glyphs/mac-island-grok-bot-pixel.gif)

- 16 × 16 网格绘制灰色圆形像素头像和两条深色斜切线，使用少量固定灰阶。
- 4.2 秒周期中斜切线各向左右移动一个像素，再回到中心；头像轮廓始终不动。
- 没有嘴巴、瞳孔、发光或组件底板；斜切线移动是交互反馈，不代表任务开始或结束。

两款都使用透明背景的原始像素几何，没有打包第三方应用图标。Bot 会话卡使用 24 pt 标识，集成设置复用相同静止图形；不为尚未认证的 Dot 来源创造标识。

## 运行规则

- 编程客户端只有会话处于 `working` 时播放动画；完成、空闲、错误和需处理状态均显示静止帧。
- Muse/Grok Bot 尚无可靠运行状态：仅鼠标悬停 Bot 卡片时播放，离开或卡片消失后恢复静止，不修改会话状态或计数。设置中的图标保持静止。
- 系统启用“减少动态效果”或能耗策略进入静态帧模式时停止动画。
- Personal Agent 全动态档最高 16 fps，降频档最高 8 fps；没有持续的后台图标动画。
- 图标直接绘制，不使用外框、组件底板或第三方原始素材。

文档 GIF 为便于看设计而自动循环；应用中的播放条件以上述规则为准。

## 预览导出

在 macOS 上运行 `./scripts/render-personal-agent-glyphs.sh`。原生渲染器直接调用生产像素帧，不启动 Mac Island 或任何客户端观察；默认更新 `docs/images/client-glyphs/` 的透明 PNG 与 GIF，可传入其他输出目录。单帧中间产物与编译缓存留在被忽略的 `build/personal-agent-glyphs.noindex/`，无需额外图像库。

## 验证

确定性测试位于 `PingIslandTests/MacIslandProductPolicyTests.swift`，覆盖：

- Claude 的十二条边线、收缩与中心释放关键帧。
- OpenCode 的黑白灰括号结构及纯水平位移。
- Hermes 的两枚简洁眼睛、无嘴结构、双眨眼和耳机独立浮动。
- 编程客户端仅在工作中动画；Muse/Grok Bot 悬停策略独立于运行状态，且尊重“减少动态效果”与静态能耗档。
- 两款 Personal Agent 的固定轮廓、周期回环、有效颜色、异常时间静止帧，以及 Grok 一个像素的斜切位移。

实际门禁与原生界面核对记录见 [Personal Agent 验证记录](../personal-agent-validation.md)。
