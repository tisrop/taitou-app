---
name: release-highlights
description: 为 taitou-app 准备并执行 stable 发版。用户说“打 release”“发稳定版”“release patch”“起草版本亮点”或调用 /release-highlights 时使用；先检查 Git 状态并 dry-run 获取目标版本，再起草并自动提交对应 highlights/v<版本>.md、同步并提交 CHANGELOG 和其他当前版本文档，最后必须等待用户明确确认且工作区干净后才能执行正式发版。
---

# 准备稳定版发版

严格按顺序执行。不要跳过预检，不要猜测目标版本，不要擅自清理、stash、reset 或覆盖用户改动。亮点和版本文档分别提交，每次提交都必须使用精确路径，其他文件一律不得带入。

## 1. 进入并校验仓库

仓库根目录必须是 `/Users/wanghang/IdeaProjects/taitou-app`。先进入该目录，然后执行：

```bash
git status --short
```

- 向用户展示状态结果。
- 状态非空时不要修改或清理已有改动。dry-run 仍可继续，因为它不写文件；若存在冲突标记则停止并请用户先解决。
- 记录预检时已有的改动，后续不得把它们误算作本 skill 产生的修改。

## 2. 解析 Dart 命令

优先使用 PATH 中的 `dart`。若不存在，使用本机 Flutter SDK 自带的 Dart：

```text
/Users/wanghang/development/flutter/bin/dart
```

两者都不可用时停止，报告缺少 Dart，不要尝试安装软件。

## 3. 运行稳定版 dry-run

执行：

```bash
dart run tool/release.dart --track release patch --dry-run
```

PATH 中没有 `dart` 时，使用上一步解析出的绝对路径执行同一组参数。

从脚本输出中读取并交叉核对：

- `目标版本: x.y.z`
- `Tag: vx.y.z`
- `类型: 稳定版`

目标版本必须是没有 `-beta`、`-rc` 等后缀的稳定版本。输出缺失、命令失败、目标版本不是 stable，或目标 tag 已存在时立即停止，不得创建亮点文件。

目标亮点路径固定为：

```text
/Users/wanghang/IdeaProjects/taitou-app/highlights/vx.y.z.md
```

其中 `x.y.z` 必须直接来自 dry-run 输出，不得根据 `pubspec.yaml` 或提交历史自行猜测。

## 4. 起草版本亮点

先读取 `highlights/README.md`。再确定上一个 stable tag，并检查从该 tag 到 `HEAD` 的提交：

```bash
PREV=$(git describe --tags --abbrev=0 --exclude='*-*' HEAD)
git log --no-merges --format='%h %s' "$PREV"..HEAD
```

对无法仅凭标题判断用户影响的提交，读取 commit body、diff 或相关实现确认，不得脑补。忽略纯重构、诊断设施、CI、依赖升级等用户无感内容。

按照以下要求写入 `highlights/vx.y.z.md`：

- 用户视角描述“用户得到什么”，避免实现术语。
- 无 H1/H2 标题，直接以 1～2 句开场。
- 使用带 emoji 的 `###` 分节。
- 将同主题提交聚类，避免逐条复述 commit。
- 正文约 1000～2000 个中文字符，并为 Telegram 4096 字符上限留余量。
- 若文件已存在，先读取旧稿并增量更新，不得直接覆盖已有人工内容。

写完后执行：

```bash
git diff -- highlights/vx.y.z.md
git status --short
```

确认文件内容无占位符、事实错误或纯内部实现条目后，进入自动提交步骤。

## 5. 自动提交目标亮点文件

只提交本次目标文件 `highlights/vx.y.z.md`，不得使用 `git add .`、`git add -A` 或把其他改动带入提交。执行：

```bash
git diff --check -- highlights/vx.y.z.md
git add -- highlights/vx.y.z.md
git diff --cached --check -- highlights/vx.y.z.md
git commit --only -m "docs(highlights): 起草 vx.y.z 版本亮点" -- highlights/vx.y.z.md
```

`vx.y.z` 必须替换为 dry-run 得到的真实 tag。使用 `--only` 保证此前已暂存的其他文件不会进入亮点提交。提交失败时停止，不得改用更宽泛的 `git add` 或 `git commit` 绕过错误。

提交后执行：

```bash
git show --stat --oneline HEAD
git status --short
```

核对最新提交只包含目标亮点文件。向用户汇报目标版本、文件路径、主要章节、提交哈希及当前 Git 状态。

## 6. 同步项目版本文档

亮点提交完成后，扫描项目中与应用当前版本或本次发布直接相关的文档：

```bash
rg -n 'v?[0-9]+\.[0-9]+\.[0-9]+' README.md CHANGELOG.md docs .github lib --glob '*.md' --glob '*.dart'
```

逐条判断语义，不得全局替换版本号。只更新以下内容：

- `CHANGELOG.md`：在文件顶部现有说明之后插入本次 stable 版本章节，版本号和日期使用 dry-run 目标版本及执行当天日期；根据上一个 stable tag 到 `HEAD` 的提交分类整理，并添加 `v<上一稳定版>...v<目标版本>` compare 链接。
- README、`docs/**/*.md`、`.github/**/*.md` 中明确声称“当前版本”“最新版本”或固定指向上一版本下载地址的内容。
- 源码文档注释中把某个具体旧应用版本当作当前值的示例；优先改成 `<应用版本>` 等不需要每次发版维护的占位表达，而不是机械替换成新版本。

不得修改以下版本：

- `pubspec.yaml`：由正式发版脚本更新。
- 历史 `CHANGELOG.md` 章节和旧的 `highlights/v*.md`。
- 文档中的命令示例版本、设计方案版本、协议版本、依赖版本、Flutter/JDK/NDK/API 版本。
- `.github/release_template.md` 中的 `VERSION` 占位符。

更新后逐个检查差异，并只暂存本次实际修改的版本文档路径。提交前执行：

```bash
git diff --check -- <文档路径...>
git add -- <文档路径...>
git diff --cached --check -- <文档路径...>
git commit --only -m "docs(release): 同步 vx.y.z 版本文档" -- <文档路径...>
```

禁止使用目录级宽泛暂存。若扫描后除 `CHANGELOG.md` 外没有需要更新的当前版本引用，只更新并提交 `CHANGELOG.md`。若无法判断某处版本号是否应更新，保持不动并在汇报中列出。

提交后确认最新提交只包含经过核对的版本文档，并再次执行 `git status --short`。

## 7. 等待人工审阅和发版确认

亮点自动提交完成后必须停止，不得在同一轮执行正式发版。提醒用户审阅 `highlights/vx.y.z.md`：

- 若用户没有修改，保持已有亮点提交即可。
- 若用户修改了目标亮点或本次版本文档，在正式发版前分别创建只包含对应文件的修订提交；亮点使用 `docs(highlights): 完善 vx.y.z 版本亮点`，其他版本文档使用 `docs(release): 完善 vx.y.z 版本文档`。
- 其他非亮点改动不会自动提交，必须由用户自行处理；正式发版前整个工作区必须干净。

然后询问用户是否确认执行：

```bash
dart run tool/release.dart --track release patch
```

只有用户在后续消息中明确确认后，才进入下一步。模糊回复、仅修改文案或询问问题都不算确认。

## 8. 确认后执行正式发版

收到明确确认后，先再次执行：

```bash
git status --short
```

- 若只有目标 `highlights/vx.y.z.md` 或本次已识别的版本文档有修改，先校验并分别使用 `git commit --only` 自动创建对应修订提交。
- 若还有其他文件状态非空，停止并列出未提交文件；不得自动提交或清理。
- 若状态为空，再次运行 dry-run 并确认目标版本与用户审阅的亮点版本完全一致。
- 若版本变化，停止并说明变化，重新起草或更新亮点后再次请求确认；旧确认失效。

全部一致后，执行：

```bash
dart run tool/release.dart --track release patch
```

PATH 中没有 `dart` 时使用已解析的绝对路径。将命令输出如实反馈；失败时停止，不得手工补做 commit、tag 或 push。

## 安全约束

- 正式发版属于外部写操作，必须取得本次版本的明确确认。
- 不使用 `--skip-analyze`、`--skip-test` 或 `--yes`，除非用户明确要求。
- 不手工编辑 `pubspec.yaml`，不手工创建 tag，不手工创建 GitHub Release。
- 只自动暂存并提交本次目标 `highlights/vx.y.z.md`、`CHANGELOG.md` 和经语义核对后确实需要同步的当前版本文档；不得自动提交其他文件。
- 不自动执行 `git push`；正式发版脚本会在创建版本提交后统一推送。
- 仓库状态或目标版本发生变化后，之前的发版确认立即失效。
