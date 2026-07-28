# SQLite amalgamation (vendored)

- 版本: 3.50.2 (sqlite-amalgamation-3500200)
- 来源: https://sqlite.org/2025/sqlite-amalgamation-3500200.zip
- 归档 sha256: 387991de2834b5da2894119ff4173a9ea0779ea55ebcf53d9a40b24d1dc2484e
- 许可: Public Domain (https://sqlite.org/copyright.html)

## 为什么 vendor

`sqlite3` Dart 包(经 `sqflite_common_ffi` 引入,用于 Windows/Linux 图片缓存
索引)的 build hook 默认在**构建期**从 GitHub Releases 下载预编译的 SQLite
动态库。Flatpak CI 的 flatpak-builder 沙箱完全离线,下载必然失败。

根级 `pubspec.yaml` 通过 `hooks.user_defines.sqlite3` 指向本目录的
`sqlite3.c`,让 hook 改为**从源码编译**(native_toolchain_c,使用目标平台
工具链):所有平台统一版本与编译选项、全程离线、构建可复现,与
`third_party/nlohmann_json` 的 vendor 动机一致。

版本选择对齐 sqlite3 Dart 包(3.3.4)自身默认引用的 amalgamation 版本
(见其 `lib/src/hook/description.dart` 中 `DownloadAmalgamation` 默认 URL)。
升级 sqlite3 Dart 包时,同步检查该默认版本并更新本目录。

只需 `sqlite3.c`(amalgamation 自包含,无需 sqlite3.h);编译选项使用 hook
默认集(SQLITE_ENABLE_FTS5、SQLITE_DQS=0 等,见上述 description.dart)。
