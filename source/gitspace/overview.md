# GitSpace — overview

GitSpace MVP：面向多仓库工程的 macOS 原生 Git 客户端（MRD 路线一「替代型」的 M1+M2 日常闭环子集）。

## 对外能力

- **多仓纳管**：手动添加 + 父目录扫描（深度 3、跳过构建产物）；工作区配置 JSON 持久化、重启恢复。
- **跨仓统一时间线**：多仓 `git log --all` 合并为一条按时间排序的时间线；按仓库 / 分支 / 作者 / 时间 / 关键字过滤；提交详情与 diff（merge 提交按第一父展示）。
- **多仓状态总览**：当前分支、↑领先 ↓落后（来自 remote-tracking ref）、未提交数、未推送数、最近 fetch 时间；统计卡 + 逐仓表格 + 批量操作条。
- **批量同步**：批量 Fetch / Pull（默认 ff-only）/ Push；逐仓 排队/执行/成功/跳过/失败 + 原因，可取消、失败重跑；默认并发 4（1–8 可调）；单仓 60s 超时、网络错误重试 1 次。
- **提交链路**：未暂存/未跟踪/已暂存三区，文件级 + 块级（hunk）暂存（`git diff` 拆块 → `git apply --cached`）；commit / amend / 丢弃改动（二次确认）；pre-commit / commit-msg 钩子原始输出透出、失败不产生提交。
- **分支**：创建（基于 HEAD 或指定点）/ 切换（脏工作区引导 stash）/ 删除（未合并强确认 -D）/ 重命名 / 检出远程并建 upstream。
- **合并与冲突**：ff / no-ff merge；冲突列表与 `git status --porcelain=v2` 逐项一致；取当前 / 取对方 / 生成合并标记 / 标记已解决；随时中止合并。
- **stash / tag**：保存（带 message）、pop / apply / drop；轻量与附注 tag 创建、删除。
- **安全边界（引擎硬闸）**：永不 force push（参数级拦截）；不接受 `reset --hard` / `clean` / `-f`；全部写操作写 JSONL 操作日志。
- **MCP 与 git-space skill（Story-1031-mcp，待评审）**：`GitSpaceApp mcp-serve` 以 stdio 暴露 59 个 git 读写工具（复用引擎与安全闸）；设置页提供写开关与 MCP 配置复制；git-space skill 随包内置，启动/手动装入 `~/.agents/skills/git-space/`（skill-unify SSOT）。

## 对内依赖

依赖方向单向：`GitSpaceApp → (GSFeatures, GSMCP) → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra`；`GSGitEngine` / `GSIndex` / `GSMCP` 不 import SwiftUI。外部零第三方依赖（GRDB 索引层见 spec 偏离项，M0 验证后引入）。

## 模块地图

| 模块 | 职责 |
|---|---|
| `App/Sources/GitSpaceApp` | @main、三栏骨架、四视图（时间线/状态/改动/分支合并）、弹窗、设置 |
| `Packages/GSGitEngine` | git CLI 进程执行器（超时/取消/重试/安全闸）、porcelain v2 / log / for-each-ref / unified diff 解析器、单仓 actor 门面 |
| `Packages/GSIndex` | 工作区扫描器、工作区配置存储、跨仓时间线聚合（每仓一 lane） |
| `Packages/GSFeatures` | AppModel / TimelineModel / RepoViewModel / BatchSyncModel（@Observable） |
| `Packages/GSMCP` | MCP stdio server（59 工具，映射 GitRepository 与安全闸）、MCPAppConfig、MCPSkillInstaller；`mcp-serve` 子命令承载 |
| `Packages/GSDesignKit` | 设计令牌（取色基准 = 交互原型深浅主题）、色板、mono 字体、图列常量 |
| `Packages/GSInfra` | 应用路径约定、JSONL 操作日志、AsyncSemaphore |
| `Packages/GSTestSupport` | GitShell（同步 CLI 基准）+ FixtureRepo（多 hunk / 冲突 / 钩子场景生成器） |
