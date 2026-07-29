# Changelog

本文件记录「抬头」独立维护后的版本变更。

## [0.2.25] - 2026-07-28

### 新功能

- 默认接入 openxinsheng.com，并统一站内链接、Deep Link 与分享地址识别规则。
- 完成「抬头 / Taitou」品牌适配，更新应用名称、图标、Logo、启动动画与相关文案。
- Android 包名调整为 `com.openxinsheng.taitou`，支持作为独立应用安装。
- 登录流程适配未启用验证码插件的站点，并根据站点能力显示可用入口。
- 修复 DiceBear 等 SVG 头像在话题卡片和降级场景中显示空白的问题。

### 工程与发布

- 项目改为独立维护，后续更新不再通过外部 Git 链路追踪。
- 删除桌面端及其他非 Android 平台代码，仅保留 Android 平台支持。
- 将渲染组件纳入主仓库管理，避免构建依赖不可用的子模块提交。
- Android 发布流水线并行构建 `armeabi-v7a`、`arm64-v8a` 和 `x86_64` 三个独立 APK。
- 修复单 ABI 构建同时配置 `ndk.abiFilters` 与 APK splits 导致的 Gradle 冲突。
- 发布说明支持重写 Git 历史后的首次发布场景。
- 应用与发布版本统一为 `0.2.25`。

**Release**: https://github.com/tisrop/taitou-app/releases/tag/v0.2.25
