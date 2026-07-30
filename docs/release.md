# Android 发版说明

本仓库只发布 Android APK。稳定版和预发布版都通过版本 tag 触发 `.github/workflows/android-release.yaml`。

## 发版前检查

```bash
just release-check
```

默认会执行项目预处理、静态分析和工作区测试。需要临时跳过时可使用：

```bash
just release-check -- --skip-analyze
just release-check -- --skip-test
```

## 创建版本

稳定版：

```bash
just release -- patch
# 也可使用 minor、major 或明确版本号
```

预发布版：

```bash
just prerelease -- patch --preid beta
```

发版工具会更新 `pubspec.yaml` 版本、创建提交和 tag，并按交互确认结果推送。稳定版可在 `highlights/v<版本>.md` 中维护用户视角的版本亮点。

## 本地构建 APK

按 ABI 分包，适合正式分发：

```bash
./scripts/build-android.sh
```

构建单个全 ABI APK：

```bash
./scripts/build-android.sh --universal
```

构建 debug APK：

```bash
./scripts/build-android.sh --debug
```

构建 AAB：

```bash
./scripts/build-android.sh --aab
```

产物目录：

- APK：`build/app/outputs/flutter-apk/`
- AAB：`build/app/outputs/bundle/release/`

## GitHub Actions 签名

`Android Release` 工作流需要配置：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_PROPERTIES`（推荐，内容与本地 `android/key.properties` 一致）

兼容旧配置时，也可以分别设置：

- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

生成 keystore 的 base64：

```bash
base64 -i android/app/taitou-release.jks | pbcopy
```

复制属性文件：

```bash
cat android/key.properties | pbcopy
```

工作流会在构建前校验 keystore、alias、storePassword 和 keyPassword，并在构建后用 `apksigner` 确认产物没有使用 Android debug 证书。

## CI 构建

release workflow 会并行构建 `armeabi-v7a`、`arm64-v8a` 和 `x86_64` 三个签名 APK；只有三个 ABI 全部通过签名校验，发布 job 才会聚合产物并更新 GitHub Release。

需要用最新 workflow 重新构建已有版本时，手动运行 `Android Release`，将 `release_tag` 填为目标 tag。工作流会从当前 `main` 构建并替换该 tag 的 Release 资产，不会移动或重写 tag。
