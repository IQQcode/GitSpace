---
name: git-space
description: 通过 GitSpace 的本地 MCP server 执行 git 常规读写操作：状态查询、提交历史与 blame 追溯、暂存/提交/推送、分支/合并/冲突处理、stash、tag、cherry-pick、revert、二分查找定位坏提交（bisect）。当任务涉及查看仓库状态、历史、diff，或需要执行提交、分支、合并、回滚、二分定位等 git 操作时使用本 skill。
version: 1.0.0
---
# git-space：GitSpace git 读写工作流

通过 GitSpace 内嵌的本地 MCP server（`GitSpaceApp mcp-serve`）操作 git 仓库。
所有操作复用 GitSpace 引擎：数据来自系统 git CLI、破坏性操作受安全闸约束、写操作全量留痕可回溯。

## 连接

1. 用户已安装 GitSpace.app；skill 由 App 自动装到 `~/.agents/skills/git-space/`。
2. MCP 客户端配置（GitSpace 设置页「MCP 与 Agent → 复制 MCP 配置」可直接复制；command 路径以实际安装位置为准）：

```json
{
  "mcpServers": {
    "gitspace": {
      "command": "/Applications/GitSpace.app/Contents/MacOS/GitSpace",
      "args": ["mcp-serve"]
    }
  }
}
```

3. 连接后先 `list_repos` 看纳管清单；其他工具的 `repo` 参数接受**任意本地 git 仓库绝对路径**（含 .git 的仓库根），不限于纳管清单。

## 读写规则

- **读工具**（git_status / git_commits / git_blame / git_worktree_diff 等）零副作用，随便用。
- **普通写工具**（git_stage / git_commit / git_merge / git_create_branch 等）直接调；每次调用引擎自动写入 JSONL 留痕（`~/Library/Application Support/GitSpace/logs/`）。
- **破坏性写工具**（清单见 references/safety.md）：调用前必须先向使用者说明影响范围并获得同意，然后显式传 "confirm": true。缺 confirm 会被 server 拒绝并返回影响说明——这是产品口径，不要绕过。
- 引擎硬闸永远拒绝（无法绕过）：force push、reset --hard、clean、任何 -f 类命令。
- 已在 GitSpace 设置里关闭「允许 MCP 写操作」时，全部写工具被拒；此时只做查询，并告知使用者在 GitSpace 设置 → MCP 与 Agent 里开启。

## 工具地图

**清单与状态**：`list_repos`、`git_status`、`git_current_sha`、`git_has_remote`

**历史与追溯**：`git_commits`、`git_commit_detail`、`git_file_history`、`git_file_change_at`、`git_show_file`、`git_refs_containing`、`git_commit_template`

**diff**：`git_worktree_diff`、`git_staged_diff`、`git_untracked_file_diff`、`git_diff_against_revision`

**分支/tag/stash 读**：`git_local_branches`、`git_remote_branches`、`git_tags`、`git_stashes`、`git_stash_diff`

**blame 与冲突读取**：`git_blame`、`git_conflict_stage_contents`

**暂存与提交（写）**：`git_stage`、`git_unstage`、`git_commit`、`git_commit_merge`

**丢弃与恢复（写）**：`git_discard ⚠`、`git_stash_snapshot`、`git_restore_from_snapshot`、`git_restore_file ⚠`

**stash（写）**：`git_stash_push`、`git_stash_restore`、`git_stash_drop ⚠`

**分支管理（写）**：`git_create_branch`、`git_switch_branch`、`git_delete_branch ⚠`、`git_rename_branch`、`git_checkout_remote_branch ⚠`、`git_checkout_commit ⚠`

**合并与冲突（写）**：`git_merge`、`git_resolve_conflict`、`git_mark_conflict_resolved`、`git_abort_merge ⚠`、`git_abort_pick ⚠`

**同步（写）**：`git_fetch`、`git_pull`、`git_push ⚠`、`git_push_tag ⚠`、`git_delete_remote_tag ⚠`

**tag（写）**：`git_create_tag`、`git_delete_tag ⚠`

**二分查找**：`git_bisect_start ⚠`、`git_bisect_good`、`git_bisect_bad`、`git_bisect_skip`、`git_bisect_reset`（写）；`git_bisect_log`（读）

**摘取与回滚（写）**：`git_cherry_pick`、`git_revert`

## 常见反模式

- 未经使用者同意就传 `confirm: true`。
- 不看 `git_status` 就动手写。
- 跨仓批量写操作前不做逐仓 status 预检。
- 拿工具名去猜参数：以客户端拿到的 tools/list schema 为准。
- `git_checkout_commit` 产生 detached HEAD 后，回分支用 `git_switch_branch`，不要误用 `git_bisect_reset`。
