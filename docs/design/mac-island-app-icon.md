# Mac Island 应用图标

选定方案：**Clean Notch / 净形岛（方案 A）**，2026-10-02。对应 [Issue #23](https://github.com/Samadhi-Chi/mac-island-private-archive/issues/23)。

![Mac Island Clean Notch](../images/mac-island-app-icon.png)

## 设计与正式资源

- 深墨色圆角底板、银白刘海轮廓、珊瑚至紫色的短状态条。
- 保留已选概念稿的结构与配色，移除图标底板外的浅灰展示背景；外边角透明，内部主体完整保留。
- 正式源图：`docs/images/mac-island-app-icon.png`。所有 AppIcon 尺寸均由这张 PNG 导出。
- 应用资源：`PingIsland/Assets.xcassets/AppIcon.appiconset/`，保留现有 `Contents.json` 的 10 个 macOS 1x/2x 槽位，覆盖 16–1024 像素。

在仓库根目录重新生成：

```sh
./scripts/render-app-icons.sh
```

脚本也支持 `--source <image-path>` 和 `--output-dir <path>`。源图保留完整透明画布；不要把展示背景烘焙到导出资源中，也不要改变现有文件名与资产目录的对应关系。仓库中旧的 `ping-island-icon.svg` 属于保留的上游资料，不再是 Mac Island 的默认导出源。

资源验收应核对每个槽位的尺寸、RGBA 通道、全透明外角和主体完整性，并运行 `./scripts/test.sh`。安装验收需另外核对实际 `.app` 内的 `AppIcon.icns` 和 `Assets.car`，构建成功不代表已替换安装副本。

## 生成来源

概念稿及透明背景处理使用内置 imagegen；尺寸导出使用仓库既有的 `sips` 流程。正式资源已经保存在仓库，不依赖会话生成目录。

最终透明背景处理提示词：

```text
Production alpha-matte correction ONLY for the attached Mac Island icon. The artwork is already approved: preserve exactly the existing dark navy rounded square, silver U-notched island, magenta-coral-violet capsule, all positions, colors and proportions. The current PNG has a defective alpha matte: the middle of the opaque tile has alpha 251–254 instead of 255, and there are scattered faint pixels outside the tile. Correct this: all interior pixels of the dark tile and silver/pink symbols must be truly FULLY OPAQUE with alpha 255, not translucent glass. All empty outer margin pixels must be alpha 0, with no stray pixels, shadow or mist anywhere. Only the narrow antialiased perimeter edge of the dark rounded square may have intermediate alpha. Keep a clean uniform transparent margin about 7% of canvas on each side. Please render the icon as opaque clean flat vector-like artwork with perfectly clean alpha segmentation; no paper texture, noise, speckles, glows or new details. This is an export cleanup, not a design variation.
```
