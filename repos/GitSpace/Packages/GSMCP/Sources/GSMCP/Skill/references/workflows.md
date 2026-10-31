# git-spece 工作流手册

通用约定：
- 所有工具都需要 `repo` 参数 = 仓库根绝对路径（`list_repos` 可查 GitSpace 纳管清单）。
- 动手写之前先 `git_status`；冲突状态（unmerged 非空）时不要叠加新的写操作。
- ⚠ 工具缺 `"confirm": true` 会被拒，错误信息自带影响范围说明——把它原文转述给使用者。

## 1. 二分查找定位坏提交（bisect）

场景：某个版本出了 bug，但不知道哪个提交引入的。

1. `git_status`：确认工作区干净（脏区会被拒；有改动先 `git_stash_push` 或提交）。
2. `git_bisect_start`（需 confirm）：传已知坏提交 `bad` 与好提交 `good` 的 SHA（从 `git_commits` 取）。
3. 返回的 bisect log 显示当前检出的中间提交，在该提交下验证问题（跑测试/查代码），然后：
   - 问题存在 → `git_bisect_bad`；问题不存在 → `git_bisect_good`；无法判断 → `git_bisect_skip`
4. 每次标记返回最新 bisect log；出现「first bad commit」结论行即定位完成。
5. `git_bisect_reset`：结束二分，回到开始前的 HEAD。
6. 全程可用 `git_bisect_log`（读）查看进度。
7. 注意：bisect 期间不要叠加其他写操作；定位完成后必须 reset。

## 2. 提交链路（status → stage → commit → push）

1. `git_status`：看暂存/未暂存/未跟踪清单与 ahead/behind。
2. `git_worktree_diff` / `git_staged_diff`：确认改动内容。
3. `git_stage`：暂存要提交的文件（paths 数组）。
4. `git_commit`：写清提交信息；空信息或暂存区为空会被引擎拒绝。
5. `git_push`（需 confirm）：仅推已配上游的当前分支；永不 force，被拒不自动合并。
6. 发版需要 tag：`git_create_tag` 后 `git_push_tag`（需 confirm）。

## 3. 历史追溯组合

- 「这个 bug 哪来的」：`git_blame`（逐行归属）→ `git_commit_detail`（该提交全貌）。
- 「这个文件怎么演化的」：`git_file_history`（--follow 识别重命名）→ `git_file_change_at`（某提交对该文件的 diff）。
- 「这个版本长什么样」：`git_show_file`。
- 「这个修复在哪些分支上」：`git_refs_containing`。
- 「提交信息参考既往风格」：`git_commit_template` / 看 `git_commits` 标题风格。

## 4. stash 临时切换

1. `git_stash_push`：存入当前改动（可带说明）。
2. 去处理别的事（切分支、拉取等）。
3. `git_stashes` 找回序号 → `git_stash_restore`（pop=恢复并删除 / apply=恢复保留）。
4. `git_stash_drop`（需 confirm）：确认不要了再删。

## 5. 分支与合并、冲突处理

1. `git_create_branch` 新建；`git_switch_branch` 切换（脏区会被拒）。
2. `git_merge`：style=auto / ff-only / no-ff；冲突时返回冲突文件清单。
3. 冲突两条路：
   - 机械选边：`git_resolve_conflict`（ours/theirs/mergeMarkers）→ `git_mark_conflict_resolved` → 全部解决后 `git_commit_merge`。
   - 人工比对：`git_conflict_stage_contents` 拿三路内容（base/ours/theirs），编辑工作区文件后 `git_mark_conflict_resolved` → `git_commit_merge`。
   - 走不通就 `git_abort_merge`（需 confirm）回到合并前。
4. `git_checkout_remote_branch`（需 confirm）：检出远程分支为本地分支。

## 6. cherry-pick 摘取修复

1. `git_commits` 找到要摘取的提交 SHA。
2. `git_cherry_pick`：摘到当前分支；冲突时返回冲突清单。
3. 冲突时：resolve → mark_resolved → `git_commit_merge`；或 `git_abort_pick`（需 confirm）中止。
4. 验证：`git_status` 干净、`git_commits` 里看到新提交。

## 7. revert 回滚（不重写历史）

1. `git_commits` 定位要撤销的提交 SHA。
2. `git_revert`：生成反向提交；`no_commit: true` 可只应用不提交。
3. 冲突处理同 cherry-pick。

## 8. 丢弃与找回

- `git_discard`（需 confirm）三档：worktree=只还原工作区；stagedAndWorktree=连暂存一起回 HEAD；untracked=未跟踪文件进废纸篓（可找回）。
- 稳妥流程：先 `git_stash_snapshot` 拿快照 SHA → `git_discard` → 反悔时 `git_restore_from_snapshot` 恢复。
- `git_restore_file`（需 confirm）：把历史版本文件取回工作区（覆盖当前内容，先说明影响）。
