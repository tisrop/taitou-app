# Android 开发说明

本仓库只维护 Android 平台。应用构建产物为 APK 或 AAB，不提供其他平台工程和构建入口。

## 环境要求

- Flutter SDK 3.44+（Dart ^3.10.4）
- JDK 17
- Android SDK platform 36、build-tools 36.0.0
- Android NDK 28.2.13676358
- Rust 与 `cargo-ndk`

安装 Rust Android target：

```bash
rustup target add \
  aarch64-linux-android \
  armv7-linux-androideabi \
  x86_64-linux-android \
  i686-linux-android
cargo install cargo-ndk
```

## 常用命令

```bash
flutter pub get
just sync
just run -- -d android
just build -- apk --debug
just build -- apk --release --split-per-abi
just build -- appbundle --release
just test
just analyze -- --no-fatal-infos --no-fatal-warnings
```

也可以直接使用仓库包装脚本：

```bash
dart run tool/flutterw.dart run -d android
dart run tool/flutterw.dart build apk --release --split-per-abi
dart run tool/project_tasks.dart native:prepare android --release
dart run tool/project_tasks.dart release:prepare
```

`tool/flutterw.dart` 只接受 Android 的 `apk`、`appbundle` 和 `aar` 构建目标。运行或驱动测试时，原生产物准备逻辑也只处理 Android 设备。

## 自动预处理

- `just run`、`just build`、`just drive`：同步依赖、生成 l10n 和证书，并按 Android ABI 准备 Rust DoH 库。
- `just test`：执行测试所需的依赖和 l10n 预处理。
- `just sync`：显式同步项目状态。
- `just doctor`：检查 Flutter、Dart、Cargo、Android SDK/NDK、JDK、证书和签名状态。

## Android 签名

本地签名配置放在 `android/key.properties`，keystore 放在 `android/app/` 下；两者都不提交到 Git。

配置完整时，`debug`、`profile`、`release` 使用本地签名。配置缺失时，debug 使用默认 debug signing，profile/release 会回退到 debug signing，正式分发前必须检查签名证书。

CI 签名配置见 [发版说明](release.md)。
