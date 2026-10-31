# A3 AppIcon 正式替换记录

日期：2026-08-11  
项目：Mac Island  
选择：A3 · Tall Capsule / Coral Echo

## 替换内容

- 以 `03A-tall-coral-echo.png`（1024×1024、sRGB）作为唯一母版。
- 生成并替换 `PingIsland/Assets.xcassets/AppIcon.appiconset` 中全部 10 个 macOS 图标槽位，覆盖 16×16 至 1024×1024。
- 在 `PingIsland.xcodeproj/project.pbxproj` 的四个 App 构建配置中绑定 `AppIcon`，确保直接发行与 App Store 两条配置都会编译正式图标。

## 本地 Release 成品

- App：`build/icon-a3-release/DerivedData/Build/Products/Release/Mac Island.app`
- ZIP：`releases/local-a3/MacIsland-0.26.0-67-A3-adhoc.zip`
- DMG：`releases/local-a3/MacIsland-0.26.0-67-A3-adhoc.dmg`
- 版本：`0.26.0 (67)`
- Bundle ID：`local.samadhi.macisland`
- 架构：Apple Silicon (`arm64`)
- 签名：本地 ad-hoc；未做 Developer ID 签名或 Apple 公证

## 验证结果

- `./scripts/test.sh` 产品门禁通过。
- Xcode 产品测试：276 通过、1 跳过、0 失败。
- Release 构建成功；成品包含 `AppIcon.icns` 与 `Assets.car`。
- 编译后的资源包含 10 个 `AppIcon` 尺寸，最小 16×16、最大 1024×1024。
- App 深度签名验证、ZIP 完整性测试、DMG 校验及只读挂载反查均通过。

## 校验值

- ZIP SHA-256：`848f22d101357822b3dd283607a83d4771c3f16df05b6ff9b694de29cb92590a`
- DMG SHA-256：`230fe548289b7a463d3cd057aa66edc9690da9f8a492d01265003bacdf47e227`

## 回滚

- 本次替换前的图标集临时备份位于 `/private/tmp/mac-island-appicon-before-A3.ZmE43K/AppIcon.appiconset`。
- 长期回滚应以版本控制中的上一版 `AppIcon.appiconset` 为准；临时目录不作为长期归档。
