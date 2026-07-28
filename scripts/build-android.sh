#!/usr/bin/env bash
# 抬头 Android 打包脚本。
#
#   ./scripts/build-android.sh                # release APK（按 ABI 分包）
#   ./scripts/build-android.sh --debug        # debug APK
#   ./scripts/build-android.sh --aab          # Play 商店用的 AAB
#   ./scripts/build-android.sh --universal    # 单个全 ABI APK（体积大，便于分发）
#
# 环境要求见 README：Flutter 3.44+、JDK 17、Android SDK 36、NDK 27 与 28、Rust
# Android 靶子。release 签名读 android/key.properties，缺失时 Gradle 会回退到
# debug 签名并在日志里打印，不会静默出一个假的 release 包。
set -euo pipefail

cd "$(dirname "$0")/.."

MODE=release
ARTIFACT=apk
SPLIT=--split-per-abi

for arg in "$@"; do
    case "$arg" in
        --debug)     MODE=debug; SPLIT="" ;;
        --aab)       ARTIFACT=appbundle; SPLIT="" ;;
        --universal) SPLIT="" ;;
        *) echo "未知参数: $arg" >&2; exit 2 ;;
    esac
done

if [ ! -f core/doh_proxy/Cargo.toml ] || [ ! -f packages/fluxdo_render/pubspec.yaml ]; then
    echo "submodule 没拉全，先执行： git submodule update --init --recursive" >&2
    exit 1
fi

if [ "$MODE" = release ] && [ ! -f android/key.properties ]; then
    echo "警告：android/key.properties 不存在，release 包会用 debug 签名。" >&2
    echo "      正式分发前请按 README 配好签名。" >&2
fi

echo "==> 同步依赖与生成物"
flutter pub get
dart run tool/project_prep.dart app

echo "==> flutter build $ARTIFACT --$MODE $SPLIT"
# shellcheck disable=SC2086
flutter build "$ARTIFACT" "--$MODE" $SPLIT

echo
echo "==> 产物"
if [ "$ARTIFACT" = appbundle ]; then
    ls -lh build/app/outputs/bundle/"${MODE}"/*.aab
else
    ls -lh build/app/outputs/flutter-apk/*.apk
fi
