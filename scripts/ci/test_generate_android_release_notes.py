#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

_MODULE_PATH = Path(__file__).with_name("generate_android_release_notes.py")
_SPEC = importlib.util.spec_from_file_location("generate_android_release_notes", _MODULE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
_MODULE = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _MODULE
_SPEC.loader.exec_module(_MODULE)

Commit = _MODULE.Commit
choose_previous_tag = _MODULE.choose_previous_tag
collect_contributors = _MODULE.collect_contributors
merge_github_authors = _MODULE._merge_github_authors
render_notes = _MODULE.render_notes
resolve_release_data = _MODULE.resolve_release_data


class GenerateAndroidReleaseNotesTest(unittest.TestCase):
    def test_stable_release_compares_with_previous_stable(self) -> None:
        self.assertEqual(
            choose_previous_tag(
                "v0.2.26",
                ["v0.2.26", "v0.2.26-beta.1", "v0.2.25", "v0.2.24"],
            ),
            "v0.2.25",
        )

    def test_contributors_are_deduplicated_and_bots_are_removed(self) -> None:
        contributors = collect_contributors(
            [
                Commit("1", "feat: one", author_name="Wang Hang", author_login="tisrop"),
                Commit("2", "fix: two", author_name="Wang Hang", author_login="tisrop"),
                Commit("3", "ci: three", author_name="github-actions[bot]", author_login="github-actions[bot]"),
                Commit(
                    "4",
                    "feat: four",
                    body="Co-authored-by: Alice <123+alice@users.noreply.github.com>",
                    author_name="Bob",
                    author_email="bob@example.com",
                ),
            ]
        )
        self.assertEqual([item.label for item in contributors], ["@tisrop", "Bob", "@alice"])

    def test_github_login_is_merged_without_replacing_local_commit_content(self) -> None:
        local = Commit(
            "abc",
            "fix: local subject",
            body="local body",
            author_name="Wang Hang",
            author_email="wang@example.com",
        )
        github = Commit("abc", "remote subject", author_login="tisrop")

        merged = merge_github_authors([local], [github])

        self.assertEqual(merged[0].subject, "fix: local subject")
        self.assertEqual(merged[0].body, "local body")
        self.assertEqual(merged[0].author_login, "tisrop")

    def test_local_commits_keep_empty_body_records(self) -> None:
        completed = mock.Mock(
            stdout="abc\x1fWang Hang\x1ftisrop@example.com\x1ffix: empty body\x1f\x1e"
        )
        with mock.patch.object(_MODULE.subprocess, "run", return_value=completed):
            commits = _MODULE._local_commits(None, "v1.2.3")

        self.assertEqual(len(commits), 1)
        self.assertEqual(commits[0].subject, "fix: empty body")
        self.assertEqual(commits[0].body, "")

    def test_annotated_current_tag_is_excluded_by_name(self) -> None:
        with mock.patch.object(_MODULE, "_tag_commit", return_value="deadbeef"):
            with mock.patch.object(
                _MODULE,
                "_git_lines",
                return_value=["v0.2.25", "v0.2.26"],
            ) as git_lines:
                self.assertEqual(_MODULE._local_tags("v0.2.26"), ["v0.2.25"])

        git_lines.assert_called_once_with(
            ["tag", "--merged", "deadbeef", "--list", "v*"]
        )

    def test_explicit_first_release_allows_missing_previous_tag(self) -> None:
        with mock.patch.object(_MODULE, "_local_tags", return_value=[]):
            with mock.patch.object(
                _MODULE,
                "_local_commits",
                return_value=[
                    Commit(
                        "abc",
                        "fix: first release",
                        author_name="Wang Hang",
                        author_login="tisrop",
                    )
                ],
            ):
                previous_tag, previous_ref, commits = resolve_release_data(
                    tag="v0.2.25",
                    repository="tisrop/taitou-app",
                    allow_first_release=True,
                )

        self.assertIsNone(previous_tag)
        self.assertIsNone(previous_ref)
        self.assertEqual([commit.sha for commit in commits], ["abc"])

    def test_missing_previous_tag_fails_instead_of_generating_incomplete_notes(self) -> None:
        with mock.patch.object(_MODULE, "_local_tags", return_value=["v9.9.9"]):
            with self.assertRaisesRegex(RuntimeError, "无法确定 v9.9.9 的上一版本 tag"):
                resolve_release_data(
                    tag="v9.9.9",
                    repository="tisrop/taitou-app",
                )

    def test_render_contains_highlights_groups_contributors_and_compare(self) -> None:
        notes = render_notes(
            tag="v1.2.3",
            repository="tisrop/taitou-app",
            previous_tag="v1.2.2",
            compare_from="deadbeef",
            highlights="本次重点修复登录体验。\n\n### 🔐 登录\n\n- 登录更稳定。",
            commits=[
                Commit(
                    "abcdef123456",
                    "fix(auth): 修复登录失败",
                    author_name="Wang Hang",
                    author_login="tisrop",
                ),
                Commit("123456789abc", "chore: bump version to 1.2.3", author_name="Wang Hang"),
            ],
        )
        self.assertIn("> **版本亮点：** 本次重点修复登录体验。", notes)
        self.assertIn("<summary>📋 完整变更明细（点击展开）</summary>", notes)
        self.assertIn("### 🐛 修复", notes)
        self.assertIn("**auth：**修复登录失败", notes)
        self.assertIn("## Contributors", notes)
        self.assertIn("[@tisrop](https://github.com/tisrop)", notes)
        self.assertIn("compare/deadbeef...v1.2.3", notes)
        self.assertNotIn("bump version", notes)


if __name__ == "__main__":
    unittest.main()
