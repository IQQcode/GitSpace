# git-spece 安全口径

## 引擎硬闸（永远拒绝，任何调用方式都无法绕过）

- force push（push --force 及 -f 变体）
- reset --hard
- git clean
- 任何带 -f 的命令

被拦截时返回「命令被安全闸拦截」及原因。

## 破坏性写工具（需使用者同意 + "confirm": true）

- `git_discard`：丢弃工作区/暂存改动，或把未跟踪文件移入废纸篓
- `git_restore_file`：历史版本内容覆盖当前工作区文件
- `git_stash_drop`：删除一条 stash 引用
- `git_delete_branch`：删除分支（force 可删未合并分支）
- `git_checkout_remote_branch`：检出远程分支为本地分支
- `git_checkout_commit`：detached HEAD 检出
- `git_abort_merge` / `git_abort_pick`：放弃当前合并/摘取/回滚的中间状态
- `git_push`：推送到远端（对外可见，永不 force）
- `git_push_tag`：推送 tag 到远端
- `git_delete_remote_tag`：删除远端 tag
- `git_delete_tag`：删除本地 tag
- `git_bisect_start`：开始二分（来回检出历史提交，要求工作区干净）

调用方式：先向使用者说明影响并获得同意，再显式传 "confirm": true。缺 confirm 的拒绝信息自带影响说明，可原文转述。

## 写操作留痕

所有经 MCP 的写操作写入两份日志（`~/Library/Application Support/GitSpace/logs/ops-*.jsonl`）：
- server 侧 action 前缀 `mcp.`（如 mcp.git_commit）
- 引擎侧原始 action（如 commit / push）
- 排查时按时间取交集即可还原操作序列
- 写开关（GitSpace 设置 → MCP 与 Agent）关闭时写工具全部被拒，读工具不受影响
