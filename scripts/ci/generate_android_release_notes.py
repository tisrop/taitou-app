#!/usr/bin/env python3
"""为 Android GitHub Release 生成结构化发布说明。

stable 版本优先读取 highlights/<tag>.md，并附带按 conventional commit 分类的
完整变更、贡献者和 compare 链接。发布范围始终通过完整的本地 Git tag/history
确定；GitHub API 只用于补充贡献者 login，避免 API tag 列表异常时生成不完整正文。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

_SEMVER_RE = re.compile(
    r"^v?(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z.-]+))?$"
)
_CONVENTIONAL_RE = re.compile(
    r"^(?P<type>[a-zA-Z]+)(?:\((?P<scope>[^)]+)\))?(?P<breaking>!)?:\s*(?P<title>.+)$"
)
_COAUTHOR_RE = re.compile(
    r"^Co-authored-by:\s*(?P<name>.+?)\s*<(?P<email>[^>]+)>\s*$",
    re.IGNORECASE | re.MULTILINE,
)
_GITHUB_EMAIL_RE = re.compile(
    r"^(?:\d+\+)?(?P<login>[^@]+)@users\.noreply\.github\.com$",
    re.IGNORECASE,
)
_BOT_NAMES = {
    "github-actions[bot]",
    "github-actions",
    "dependabot[bot]",
    "dependabot",
    "release script",
}
_SKIP_SUBJECTS = (
    re.compile(r"^chore(?:\(changelog\))?:\s*(?:regenerate|update)", re.IGNORECASE),
    re.compile(r"^chore:\s*bump version", re.IGNORECASE),
    re.compile(r"^merge (?:pull request|branch|remote-tracking)", re.IGNORECASE),
)


@dataclass(frozen=True)
class Version:
    major: int
    minor: int
    patch: int
    prerelease: str | None = None

    @property
    def stable(self) -> bool:
        return self.prerelease is None

    def sort_key(self) -> tuple[int, int, int, int, tuple[tuple[int, object], ...]]:
        # stable 高于同核心版本的 prerelease。
        prerelease_key: tuple[tuple[int, object], ...] = ()
        if self.prerelease is not None:
            prerelease_key = tuple(
                (0, int(part)) if part.isdigit() else (1, part.lower())
                for part in self.prerelease.split(".")
            )
        return (
            self.major,
            self.minor,
            self.patch,
            1 if self.stable else 0,
            prerelease_key,
        )


@dataclass(frozen=True)
class Commit:
    sha: str
    subject: str
    body: str = ""
    author_name: str = ""
    author_email: str = ""
    author_login: str | None = None


@dataclass(frozen=True)
class Contributor:
    label: str
    login: str | None = None


_GROUPS = (
    ("feat", "🌟 新增"),
    ("fix", "🐛 修复"),
    ("perf", "⚡ 优化"),
    ("refactor", "♻️ 重构"),
    ("docs", "📝 文档"),
    ("other", "🔧 维护"),
)


def parse_version(tag: str) -> Version | None:
    match = _SEMVER_RE.fullmatch(tag.strip())
    if match is None:
        return None
    return Version(
        int(match.group("major")),
        int(match.group("minor")),
        int(match.group("patch")),
        match.group("prerelease"),
    )


def choose_previous_tag(current_tag: str, tags: Iterable[str]) -> str | None:
    current = parse_version(current_tag)
    if current is None:
        return None

    candidates: list[tuple[Version, str]] = []
    for tag in tags:
        if tag == current_tag:
            continue
        version = parse_version(tag)
        if version is None or version.sort_key() >= current.sort_key():
            continue
        # stable 版本汇总上一个 stable 版本之后的所有 beta/rc 改动。
        if current.stable and not version.stable:
            continue
        candidates.append((version, tag))

    if not candidates:
        return None
    return max(candidates, key=lambda item: item[0].sort_key())[1]


def _github_json(repository: str, path: str, token: str) -> object:
    url = f"https://api.github.com/repos/{repository}/{path.lstrip('/')}"
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "taitou-release-notes",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def _github_tags(repository: str, token: str) -> list[str]:
    tags: list[str] = []
    for page in range(1, 6):
        payload = _github_json(repository, f"tags?per_page=100&page={page}", token)
        if not isinstance(payload, list):
            break
        tags.extend(str(item["name"]) for item in payload if isinstance(item, dict) and "name" in item)
        if len(payload) < 100:
            break
    return tags


def _commit_from_github_item(item: object) -> Commit | None:
    if not isinstance(item, dict):
        return None
    commit_data = item.get("commit") if isinstance(item.get("commit"), dict) else {}
    message = str(commit_data.get("message", ""))
    subject, _, body = message.partition("\n")
    author_data = commit_data.get("author") if isinstance(commit_data.get("author"), dict) else {}
    github_author = item.get("author") if isinstance(item.get("author"), dict) else {}
    return Commit(
        sha=str(item.get("sha", "")),
        subject=subject.strip(),
        body=body.strip(),
        author_name=str(author_data.get("name", "")),
        author_email=str(author_data.get("email", "")),
        author_login=str(github_author.get("login")) if github_author.get("login") else None,
    )


def _github_commits(repository: str, previous_tag: str, tag: str, token: str) -> list[Commit]:
    commits: list[Commit] = []
    comparison = f"{urllib.parse.quote(previous_tag, safe='')}...{urllib.parse.quote(tag, safe='')}"
    for page in range(1, 11):
        payload = _github_json(
            repository,
            f"compare/{comparison}?per_page=100&page={page}",
            token,
        )
        if not isinstance(payload, dict):
            break
        items = payload.get("commits")
        if not isinstance(items, list):
            break
        for item in items:
            commit = _commit_from_github_item(item)
            if commit is not None:
                commits.append(commit)
        if len(items) < 100:
            break
    return commits


def _github_commits_for_ref(repository: str, ref: str, token: str) -> list[Commit]:
    commits: list[Commit] = []
    for page in range(1, 11):
        payload = _github_json(
            repository,
            f"commits?sha={urllib.parse.quote(ref, safe='')}&per_page=100&page={page}",
            token,
        )
        if not isinstance(payload, list):
            break
        for item in payload:
            commit = _commit_from_github_item(item)
            if commit is not None:
                commits.append(commit)
        if len(payload) < 100:
            break
    return commits


def _git_lines(arguments: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", *arguments],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _tag_commit(tag: str) -> str:
    lines = _git_lines(["rev-list", "-n", "1", tag])
    if not lines:
        raise RuntimeError(f"无法解析 tag：{tag}")
    return lines[0]


def _local_tags(tag: str) -> list[str]:
    tag_commit = _tag_commit(tag)
    tags = _git_lines(["tag", "--merged", tag_commit, "--list", "v*"])
    return [candidate for candidate in tags if candidate != tag]


def _local_commits(previous_tag: str | None, tag: str) -> list[Commit]:
    revision_range = f"{previous_tag}..{tag}" if previous_tag else tag
    result = subprocess.run(
        [
            "git",
            "log",
            "--format=%H%x1f%an%x1f%ae%x1f%s%x1f%b%x1e",
            revision_range,
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    commits: list[Commit] = []
    for record in result.stdout.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        fields = record.split("\x1f", 4)
        if len(fields) != 5:
            continue
        commits.append(
            Commit(
                sha=fields[0].strip(),
                author_name=fields[1].strip(),
                author_email=fields[2].strip(),
                subject=fields[3].strip(),
                body=fields[4].strip(),
            )
        )
    return commits


def _merge_github_authors(local_commits: Iterable[Commit], github_commits: Iterable[Commit]) -> list[Commit]:
    github_by_sha = {commit.sha: commit for commit in github_commits if commit.sha}
    merged: list[Commit] = []
    for commit in local_commits:
        github_commit = github_by_sha.get(commit.sha)
        merged.append(
            Commit(
                sha=commit.sha,
                subject=commit.subject,
                body=commit.body,
                author_name=commit.author_name,
                author_email=commit.author_email,
                author_login=github_commit.author_login if github_commit else commit.author_login,
            )
        )
    return merged


def resolve_release_data(
    *,
    tag: str,
    repository: str,
    token: str = "",
    allow_first_release: bool = False,
) -> tuple[str | None, str | None, list[Commit]]:
    local_tags = _local_tags(tag)
    previous_tag = choose_previous_tag(tag, local_tags)
    previous_ref = previous_tag

    print(
        f"本地 Git 找到 {len(local_tags)} 个已合并版本 tag；"
        f"发布范围：{previous_tag or '首次发布'}..{tag}"
    )

    if previous_tag is None or previous_ref is None:
        if not allow_first_release:
            raise RuntimeError(
                f"无法确定 {tag} 的上一版本 tag。请确认 checkout 获取了完整 tags，"
                "或仅在真正的首次发布时传入 --allow-first-release。"
            )
        commits = _local_commits(None, _tag_commit(tag))
        print(f"首次发布模式：通过本地 Git 读取到 {len(commits)} 个 commit")
        if token:
            try:
                github_commits = _github_commits_for_ref(repository, tag, token)
                commits = _merge_github_authors(commits, github_commits)
                matched_logins = sum(1 for commit in commits if commit.author_login)
                print(
                    f"通过 GitHub API 补充作者信息：返回 {len(github_commits)} 个 commit，"
                    f"匹配到 {matched_logins} 个 login"
                )
            except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as error:
                print(f"GitHub API 作者信息读取失败，继续使用本地 Git 作者：{error}")
        if not commits:
            raise RuntimeError(f"首次发布 {tag} 中没有 commit，拒绝生成不完整 Release Notes")
        return None, None, commits

    commits = _local_commits(previous_ref, _tag_commit(tag))
    print(f"通过本地 Git 读取到 {len(commits)} 个 commit")

    if token:
        try:
            github_commits = _github_commits(repository, previous_ref, tag, token)
            commits = _merge_github_authors(commits, github_commits)
            matched_logins = sum(1 for commit in commits if commit.author_login)
            print(
                f"通过 GitHub API 补充作者信息：返回 {len(github_commits)} 个 commit，"
                f"匹配到 {matched_logins} 个 login"
            )
        except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as error:
            print(f"GitHub API 作者信息读取失败，继续使用本地 Git 作者：{error}")

    if not commits:
        raise RuntimeError(f"发布范围 {previous_tag}..{tag} 中没有 commit，拒绝生成不完整 Release Notes")
    return previous_tag, previous_ref, commits


def _skip_commit(commit: Commit) -> bool:
    return not commit.subject or any(pattern.search(commit.subject) for pattern in _SKIP_SUBJECTS)


def _group_commit(commit: Commit) -> tuple[str, str]:
    match = _CONVENTIONAL_RE.match(commit.subject)
    if match is None:
        return "other", commit.subject

    commit_type = match.group("type").lower()
    group = commit_type if commit_type in {"feat", "fix", "perf", "refactor", "docs"} else "other"
    title = match.group("title").strip()
    scope = match.group("scope")
    if scope:
        title = f"**{scope}：**{title}"
    if match.group("breaking"):
        title = f"**破坏性变更：**{title}"
    return group, title


def _login_from_email(email: str) -> str | None:
    match = _GITHUB_EMAIL_RE.fullmatch(email.strip())
    return match.group("login") if match else None


def _is_bot(value: str) -> bool:
    normalized = value.strip().lower()
    return normalized in _BOT_NAMES or normalized.endswith("[bot]")


def collect_contributors(commits: Iterable[Commit]) -> list[Contributor]:
    contributors: list[Contributor] = []
    seen: set[str] = set()

    def add(name: str, email: str = "", login: str | None = None) -> None:
        resolved_login = login or _login_from_email(email)
        label = f"@{resolved_login}" if resolved_login else name.strip()
        if not label or _is_bot(label.lstrip("@")):
            return
        key = (resolved_login or label).lower()
        if key in seen:
            return
        seen.add(key)
        contributors.append(Contributor(label=label, login=resolved_login))

    for commit in commits:
        add(commit.author_name, commit.author_email, commit.author_login)
        for match in _COAUTHOR_RE.finditer(commit.body):
            add(match.group("name"), match.group("email"))
    return contributors


def _split_highlight_intro(highlights: str) -> tuple[str, str]:
    paragraphs = re.split(r"\n\s*\n", highlights.strip(), maxsplit=1)
    intro = paragraphs[0].strip() if paragraphs else ""
    rest = paragraphs[1].strip() if len(paragraphs) > 1 else ""
    return intro, rest


def render_notes(
    *,
    tag: str,
    repository: str,
    previous_tag: str | None,
    commits: Iterable[Commit],
    highlights: str = "",
    compare_from: str | None = None,
) -> str:
    visible_commits = [commit for commit in commits if not _skip_commit(commit)]
    groups: dict[str, list[tuple[Commit, str]]] = {key: [] for key, _ in _GROUPS}
    for commit in visible_commits:
        group, title = _group_commit(commit)
        groups[group].append((commit, title))

    lines = [f"# 抬头 {tag}", ""]
    intro, highlight_body = _split_highlight_intro(highlights)
    if intro:
        lines.extend([f"> **版本亮点：** {intro}", ""])
    if highlight_body:
        lines.extend([highlight_body, ""])

    has_details = any(groups[key] for key, _ in _GROUPS)
    if has_details:
        if highlights.strip():
            lines.extend(["<details>", "<summary>📋 完整变更明细（点击展开）</summary>", ""])
        else:
            lines.extend(["## 更新内容", ""])
        for key, heading in _GROUPS:
            if not groups[key]:
                continue
            lines.extend([f"### {heading}", ""])
            for commit, title in groups[key]:
                sha = commit.sha[:7]
                suffix = f" ([`{sha}`](https://github.com/{repository}/commit/{commit.sha}))" if sha else ""
                lines.append(f"- {title}{suffix}")
            lines.append("")
        if highlights.strip():
            lines.extend(["</details>", ""])

    contributors = collect_contributors(visible_commits)
    if contributors:
        lines.extend(["## Contributors", "", "感谢以下贡献者参与本次版本：", ""])
        for contributor in contributors:
            if contributor.login:
                lines.append(f"- [@{contributor.login}](https://github.com/{contributor.login})")
            else:
                lines.append(f"- {contributor.label}")
        lines.append("")

    if previous_tag:
        compare_base = compare_from or previous_tag
        lines.extend(
            [
                "---",
                "",
                f"**Full Changelog**: https://github.com/{repository}/compare/{compare_base}...{tag}",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "tisrop/taitou-app"))
    parser.add_argument("--output", default="release_notes.md")
    parser.add_argument(
        "--allow-first-release",
        action="store_true",
        help="允许没有上一版本 tag；仅用于仓库真正的首次发布",
    )
    args = parser.parse_args()

    previous_tag, previous_ref, commits = resolve_release_data(
        tag=args.tag,
        repository=args.repository,
        token=os.environ.get("GITHUB_TOKEN", "").strip(),
        allow_first_release=args.allow_first_release,
    )

    highlights_path = Path("highlights") / f"{args.tag}.md"
    highlights = highlights_path.read_text(encoding="utf-8").strip() if highlights_path.exists() else ""
    notes = render_notes(
        tag=args.tag,
        repository=args.repository,
        previous_tag=previous_tag,
        commits=commits,
        highlights=highlights,
        compare_from=previous_ref,
    )
    Path(args.output).write_text(notes, encoding="utf-8")
    contributor_count = len(collect_contributors(commits))
    if previous_tag and contributor_count == 0:
        raise RuntimeError("未识别到任何 contributor，拒绝更新为缺少 Contributors 的 Release Notes")
    print(
        f"已生成 {args.output}：{len(commits)} 个 commit，"
        f"{contributor_count} 位 contributors，"
        f"亮点={'有' if highlights else '无'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
