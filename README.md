# 抬头

> [开源心声社区](https://openxinsheng.com/) 的第三方 Android 客户端

抬头是为 [开源心声社区](https://openxinsheng.com/)（openxinsheng.com）打造的 Android 客户端，基于 Flutter 开发。

**本项目仅维护 Android 平台，构建产物为 APK 或 AAB。**

## 这个项目是什么

本项目当前面向 [开源心声社区](https://openxinsheng.com/)（openxinsheng.com）维护，
后续代码与配置由本项目手工维护。
Dart 包名与 MethodChannel 名等历史内部标识暂不作为兼容性迁移范围。

### 项目说明

| 改动 | 位置 |
| --- | --- |
| 站点域名切到 openxinsheng.com | `lib/constants.dart` 的 `baseUrl`；`baseHost` / `isSiteHost()` 供各处复用 |
| 站点链接安全策略 | `lib/config/sites/openxinsheng.dart` |
| 关闭 hcaptcha 原生登录 | `AppConstants.enableNativeCaptchaLogin`（见下节） |
| 应用身份 | applicationId `com.openxinsheng.taitou`、自定义 scheme `taitou://`、App Links 域名 |
| 品牌资源 | 「抬」字标图标与 `assets/logo*.svg` |
| 国内 Maven 镜像 | `android/settings.gradle.kts`、`android/build.gradle.kts` |

### 登录方式

站点实测配置（取自预载设置）：`enable_local_logins: true`、`hcaptcha_site_key: ""`、
`recaptcha_site_key: ""`、`enable_discourse_connect: false`。即**本地密码登录可用，
且站点没有任何验证码插件**。

三条路径并存：

- **应用内用户名/密码登录**（主路径）—— 表单提交后在 mini WebView 里用 JS 同源
  fetch 跑 `GET /session/csrf` → `POST /session.json`，不加载 Discourse Ember bundle。
  2FA 走 TOTP 弹窗。
- **浏览器授权登录** —— Discourse 官方 user-api-key 流程，DiscourseHub 同款，
  回调走 `discourse://auth_redirect`。站点开了 Google / Microsoft 365 SSO，走这条最省事。
- **网页登录** —— 内置 WebView，覆盖 OAuth / Passkey / 注册 / 2FA 备用码等场景。

登录策略按站点能力配置，不把验证码和 Cloudflare 状态写死：

| 常量 | 本站取值 | 作用 |
| --- | --- | --- |
| `AppConstants.enableNativePasswordLogin` | `true` | 是否显示密码表单 |
| `AppConstants.hcaptchaSiteKey` | `''` | **空 = 无验证码**，登录流程整段跳过 hcaptcha |
| `AppConstants.requireCfClearanceBeforeLogin` | 由上一项推导 | 有验证码的站点才需要 CF 前置 |

站点若以后启用 hcaptcha，只需把 sitekey 填进 `hcaptchaSiteKey`，其余代码不用动。

## 已知限制

- **站点插件差异**：openxinsheng 装了 `discourse-reactions`（多表情回应）和
  `discourse-gamification`（积分排行），当前实现按标准点赞逻辑提供基础能力，
  没有这两者的界面。App 里 reactions 会退化成普通点赞，排行榜没有入口。
  要支持得单独开发。
- **崩溃上报默认关闭**（`AppConstants.enableCrashReporting`）：仓库里的
  `google-services.json` 是占位配置，没有真实 Firebase 项目，
  开着只会向用户弹一个不属实的数据收集告知。Ï˜
- **SVG 头像**：本站 51 个活跃用户里 42 个（82%）用的是 `api.dicebear.com`
  的 **SVG** 默认头像，而不是 Discourse 站内 PNG。当前实现只有 widget 版
  `SmartAvatar` 做了 SVG 兜底，列表页用的自绘卡 `PaintedTopicCard` 那条
  解码路径没有，SVG 进位图解码器抛异常后被空 catch 吞掉，表现为头像永久空白。
  已在 `TopicCardImages._load` 里补上 `SvgUtils.rasterize`（jovial_svg
  光栅化成 96px `ui.Image`）。后续若新增只能画位图的头像路径，记得走同一个函数。
- **应用名是中文**，凡是要把它写进 HTTP 头的地方都必须过
  `AppConstants.sanitizeHeaderValue`（RFC 7230 要求头值为可见 ASCII）。
  已知的一处是 `Sec-CH-UA`；新增类似逻辑时注意这点。

## 特性

核心特性：

- Material Design 3 UI，动态取色、深色模式
- 完整论坛功能：浏览话题、发帖回复、搜索、通知、私信
- 内容管理：书签、浏览历史、关注列表、徽章
- Markdown 编辑器，图片上传与查看，投票
- 支持 HTTP/SOCKS5 上游代理和多网络引擎切换
- MessageBus 实时消息推送

## 快速开始

### 前置要求

- Flutter SDK 3.44+（Dart ^3.10.4）
- JDK 17（AGP 要求；JDK 21+ 会构建失败）
- Android SDK：platform 36、build-tools 36.0.0、NDK 28.2.13676358

### 构建

```bash
git clone <本仓库地址> taitou-app
cd taitou-app

flutter pub get
dart run tool/project_prep.dart app   # 生成 l10n

flutter build apk --release
```

### 签名

release 签名读 `android/key.properties`（已在 `.gitignore` 中，不入库）：

```properties
storeFile=app/taitou-release.jks
storePassword=<口令>
keyAlias=taitou
keyPassword=<口令>
```

配置缺失时 release 会回退到 debug 签名，Gradle 会在构建日志里打印当前使用的签名。

## 开发

- [开发环境与日常命令](docs/development.md)
- [Android 发版说明](docs/release.md)

## 项目结构

```
taitou-app/
├── lib/
│   ├── config/sites/        # 站点自定义配置（openxinsheng.dart）
│   ├── constants.dart       # 站点域名、功能开关
│   ├── models/              # 数据模型
│   ├── pages/               # 页面
│   ├── providers/           # Riverpod 状态管理
│   ├── services/
│   │   ├── discourse/       # Discourse API 封装
│   │   └── network/         # 网络层（代理、网络引擎、cookie）
│   └── widgets/
├── packages/                # 本地依赖包
└── android/
```

## 开源协议

本项目采用 [GPL-3.0](LICENSE) 发布。
这意味着分发本 App 时必须一并提供完整源码。

## 致谢

- [FluxDO](https://github.com/Lingyan000/fluxdo) 及其作者 [@Lingyan000](https://github.com/Lingyan000) —— 本项目的全部工程基础来自这里
- [开源心声社区](https://openxinsheng.com/)

**注意**：本项目为非官方客户端，与开源心声社区官方无直接关联。
