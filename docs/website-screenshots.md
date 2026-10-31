# Website screenshot provenance / 网页截图来源

Captured on 2026-10-31 from the running native Mac Island SwiftUI application,
version 0.29.2 (73), on macOS. These are real window captures, not generated,
redrawn or HTML-rendered application interfaces.

2026-10-31 截取实际运行的 Mac Island 原生窗口，版本 0.29.2（73）。
网页仅裁切、排版原始像素；没有生成、重绘或用 HTML 模拟应用界面。

## Capture setup / 拍摄环境

- Release executable SHA-256:
  `79c5c3609aaaea1213df74de9c0f96abdfa83e8dfa7f11ea1ce7b81a6d902ce1`.
- Sources: [English fixture](../Fixtures/website-en.json) and
  [Chinese fixture](../Fixtures/website-zh.json). Both contain invented sessions
  under `/Projects/Example`, not a real user's conversations or projects.
- The fixture launch disables live client reads, persistent preferences,
  integrations and background services. Language and surface are supplied through
  `MAC_ISLAND_FIXTURE_LANGUAGE` and `MAC_ISLAND_FIXTURE_SURFACE`.
- A separate, uninstalled preview copy uses bundle identifier
  `local.samadhi.macisland.websitepreview` and display name `Mac Island Preview`.
  Only those preview bundle identity fields differ; the executable is unchanged.
- Window images were captured through the native application interface. PNG
  export preserves their pixels, with the crops below and no content replacement.
  The floating captures retain the actual pointer over the mascot.
- Private raw captures and their checksum manifest stay in ignored
  `build/WebsiteCapture.noindex/`; only the six reviewed PNG files are published.

## Published crops / 发布裁切

Coordinates are source pixels: left, top, right, bottom (exclusive).
坐标为原图像素的左、上、右、下边界，右和下边界不包含在裁切结果中。

| File in `site/assets/screenshots/` | Raw size | Crop | Published size |
| --- | --- | --- | --- |
| `current-en.png` | 1392 × 1248 | 48, 0, 1344, 500 | 1296 × 500 |
| `current-zh.png` | 1392 × 1248 | 48, 0, 1344, 500 | 1296 × 500 |
| `floating-en.png` | 1112 × 432 | Full image | 1112 × 432 |
| `floating-zh.png` | 1112 × 432 | Full image | 1112 × 432 |
| `privacy-en.png` | 1920 × 1400 | 548, 375, 1876, 1144 | 1328 × 769 |
| `privacy-zh.png` | 1920 × 1400 | 548, 430, 1876, 1144 | 1328 × 714 |

The captures demonstrate presentation and language selection. They do not
certify a real client's integration, permissions or signed-binary compatibility.
截图用于展示界面和语言选择，不代替真实客户端、权限或签名安装包验收。
