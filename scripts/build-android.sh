#!/usr/bin/env bash
# 抬头 Android 打包脚本。
#
#   ./scripts/build-android.sh                # release APK（按 ABI 分包）
#   ./scripts/build-android.sh --debug        # debug APK
#   ./scripts/build-android.sh --aab          # Play 商店用的 AAB
#   ./scripts/build-android.sh --arm          # 仅构建 armeabi-v7a APK
#   ./scripts/build-android.sh --arm64        # 仅构建 arm64-v8a APK
#   ./scripts/build-android.sh --x64          # 仅构建 x86_64 APK
#   ./scripts/build-android.sh --universal    # 单个全 ABI APK（体积大，便于分发）
#
# 环境要求见 README：Flutter 3.44+、JDK 17、Android SDK 36、NDK 28。
# release 签名读 android/key.properties，缺失时 Gradle 会回退到
# debug 签名并在日志里打印，不会静默出一个假的 release 包。
set -euo pipefail

cd "$(dirname "$0")/.."

MODE=release
ARTIFACT=apk
SPLIT=--split-per-abi
# 默认只编三个发布用 ABI。
TARGET_PLATFORM=android-arm,android-arm64,android-x64

for arg in "$@"; do
    case "$arg" in
        --debug)     MODE=debug; SPLIT=""; TARGET_PLATFORM= ;;
        --aab)       ARTIFACT=appbundle; SPLIT=""; TARGET_PLATFORM= ;;
        --arm)       TARGET_PLATFORM=android-arm ;;
        --arm64)     TARGET_PLATFORM=android-arm64 ;;
        --x64)       TARGET_PLATFORM=android-x64 ;;
        --universal) SPLIT=""; TARGET_PLATFORM=android-arm,android-arm64,android-x64 ;;
        *) echo "未知参数: $arg" >&2; exit 2 ;;
    esac
done

if [ ! -f packages/fluxdo_render/pubspec.yaml ]; then
    echo "本地 package 不完整：缺少 packages/fluxdo_render。" >&2
    exit 1
fi

if [ "$MODE" = release ] && [ ! -f android/key.properties ]; then
    echo "警告：android/key.properties 不存在，release 包会用 debug 签名。" >&2
    echo "      正式分发前请按 README 配好签名。" >&2
fi

# flutterw 会先执行 project_prep，ensurePubGet 已保证 package config 最新；
# 构建阶段不再让 Flutter 重复解析一次依赖。
BUILD_ARGS=(build "$ARTIFACT" "--$MODE" --no-pub)
if [ -n "$SPLIT" ]; then
    BUILD_ARGS+=("$SPLIT")
fi
if [ -n "$TARGET_PLATFORM" ]; then
    BUILD_ARGS+=(--target-platform "$TARGET_PLATFORM")
fi

echo "==> dart run tool/flutterw.dart ${BUILD_ARGS[*]}"
# flutterw 统一完成 pub get、l10n 和 Flutter 构建，避免重复预处理。
dart run tool/flutterw.dart "${BUILD_ARGS[@]}"

echo
echo "==> 产物"
if [ "$ARTIFACT" = appbundle ]; then
    ls -lh build/app/outputs/bundle/"${MODE}"/*.aab
else
    ls -lh build/app/outputs/flutter-apk/*.apk
fi
