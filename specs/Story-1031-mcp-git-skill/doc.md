# Story-1031: GitSpace MCP 支持与 git-space skill 内置分发

> 状态：设计定稿（决策项含「待评审」标注）。产出范围超出 MRD P0，按 epic 治理约定标注「待评审」，评审通过后回写 MRD。

## 1. 需求

1. GitSpace 支持本机 MCP（Model Context Protocol）：把 `GSGitEngine` 的 git 读写能力以 MCP tools 暴露给本机 Agent 客户端（ZCode / Claude Code / Cursor 等）。
2. 构建名为 `git-space` 的 skill：教 Agent 用上述 MCP 工具完成 git 常规读写工作流（二分查找 commit / bisect、blame、历史追溯、stash、分支、提交、cherry-pick、revert 等）。
3. skill 随 App 分发：安装 App 后自动（且可手动重装）把 skill 写入 `~/.agents/skills`（skill-unify 确立的 SSOT 路径），装完即被 Agent 发现。
4. 开发期 skill 源码落 workspace `skills/git-space/`，经 skill-unify install 落位 SSOT。

## 2. 调研结论（约束与现状）

- 全部文档零处提及 MCP → 全新范围；最近的落点模板是 EP09「外部集成」与 Epic INDEX §7.8「AI 数据外发口径（待定）」。
- 引擎现状：`GitRepository`（actor 门面）已有完整读写 API；引擎级硬闸在 `GitProcessRunner.validate`（禁 force push / reset --hard / clean / 任意 `-f`）；写命令统一 `runWrite` → JSONL 留痕。
- 引擎缺失：bisect、cherry-pick、revert（0 处）。
- App 入口无命令行参数解析；Package.swift 无 resources 声明；打包脚本手工组装 .app。
- 硬约束映射：数据全本地 → stdio 传输（不开端口）；包体 ≤60MB → 零第三方依赖手写协议；Apache 2.0 → 不引入受限 SDK；安全边界 → MCP 写操作不绕过引擎闸、全量留痕。
- 用户未确认的决策按推荐项定稿，见 §8。

## 3. 方案

### 3.1 总体架构

```mermaid
flowchart LR
    subgraph Agent客户端
        Z[ZCode / Claude Code / Cursor]
    end
    Z -- "spawn + stdio<br/>JSON-RPC 2.0" --> M[GSMCP server]
    subgraph GitSpace.app（单二进制）
        E[MainEntry] -- "mcp-serve 子命令" --> M
        E -- 默认 --> G[GitSpaceApp GUI]
        S[SettingsView<br/>MCP 与 Agent Section]
    end
    M --> R[(GSGitEngine<br/>GitRepository + 硬闸 + JSONL)]
    M --> W[(GSIndex<br/>WorkspaceStore 纳管清单)]
    B[Bundle Skill 资源] -- 安装/更新 --> K[(~/.agents/skills/git-space<br/>skill-unify SSOT)]
```

- **新模块 `GSMCP`**（`Packages/GSMCP/Sources/GSMCP/`）：MCP stdio server + tool 注册表 + 引擎映射 + skill 安装器。依赖 `GSGitEngine`、`GSIndex`、`GSInfra`，**不 import SwiftUI**。依赖图变为：`GitSpaceApp → (GSFeatures, GSMCP) → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra`。
- **单二进制子命令**：新增顶层 `@main struct MainEntry`，`CommandLine.arguments` 含 `mcp-serve` 时同步跑 stdio server（不启 GUI），否则转交 `GitSpaceApp.main()`。原 `GitSpaceApp` 的 `@main` 移除、结构体保留。MCP 模式下 stdout 是 JSON-RPC 通道，任何非协议输出禁入 stdout。
- **skill 资源**：skill 文件放 `Packages/GSMCP/Sources/GSMCP/Skill/`，target 声明 `resources: [.copy("Skill")]`——SPM 会产出独立资源 bundle（`GitSpace_GSMCP.bundle`），打包脚本补拷进 `Contents/Resources/`（独立审查 P0 修复：并非「编译进二进制」）；运行时由 `MCPSkillInstaller.bundleSkillDirectory` 手动定位 bundle（不用 `Bundle.module` 访问器，避免资源缺失时 fatalError）。GUI 模式下自动安装/更新 + 设置页手动按钮。

### 3.2 MCP 协议实现（零依赖手写）

- 传输：stdio，换行分隔 JSON-RPC 2.0（MCP stdio 规范）。
- 方法面（最小闭环，YAGNI）：`initialize`（protocolVersion 支持 `2025-06-18` / `2024-11-05`，协商取交集）、`notifications/initialized`、`ping`、`tools/list`、`tools/call`；`notifications/cancelled` 忽略即可。不实现 resources/prompts/sampling。
- 工具结果统一 `content: [{type:"text", text}]`；引擎错误与参数校验失败返回 `isError: true` + 可读原因（含建议动作），不抛崩溃。
- 长输出保护：diff / log 类结果默认截断（单工具响应文本 ≤512,000 字符，Character 计数、按字符边界截断，UTF-8 安全；尾部标注截断提示），防 agent 上下文爆量。

### 3.3 工具面（tool list）

仓库定位参数统一为 `repo`（绝对路径）；`list_repos` 返回纳管清单（读 `WorkspaceStore`，含路径），Agent 也可传任意本地 git 仓库路径（`GitRepository.init?` 校验 `.git` 存在）。server 内按路径缓存 actor 实例（同仓串行复用引擎既有语义）。

| 组 | 工具（read） |
|---|---|
| 状态 | `list_repos`、`git_status`、`git_current_sha`、`git_has_remote` |
| 历史 | `git_commits`、`git_commit_detail`、`git_file_history`、`git_file_change_at`、`git_show_file`、`git_refs_containing` |
| diff | `git_worktree_diff`、`git_staged_diff`、`git_untracked_file_diff`、`git_diff_against_revision` |
| 分支/tag/stash | `git_local_branches`、`git_remote_branches`、`git_tags`、`git_stashes`、`git_stash_diff` |
| blame/冲突 | `git_blame`、`git_conflict_stage_contents`、`git_commit_template` |

| 组 | 工具（write，默认注册；`⚠` = 需 `confirm: true`） |
|---|---|
| 暂存提交 | `git_stage`、`git_unstage`、`git_commit`、`git_commit_merge` |
| 丢弃恢复 | `git_discard` ⚠、`git_stash_snapshot`、`git_restore_from_snapshot`、`git_restore_file` ⚠ |
| stash | `git_stash_push`、`git_stash_restore`、`git_stash_drop` ⚠ |
| 分支 | `git_create_branch`、`git_switch_branch`、`git_delete_branch` ⚠、`git_rename_branch`、`git_checkout_remote_branch` ⚠、`git_checkout_commit` ⚠（detached） |
| 合并冲突 | `git_merge`、`git_resolve_conflict`、`git_mark_conflict_resolved`、`git_abort_merge` ⚠、`git_abort_pick` ⚠（cherry-pick/revert 中止） |
| 同步 | `git_fetch`、`git_pull`、`git_push` ⚠、`git_push_tag` ⚠、`git_delete_remote_tag` ⚠ |
| tag | `git_create_tag`、`git_delete_tag` ⚠ |
| 新增 | `git_bisect_start` ⚠、`git_bisect_good`、`git_bisect_bad`、`git_bisect_skip`、`git_bisect_reset`、`git_bisect_log`、`git_cherry_pick`、`git_revert` |

hunk 级操作（`stageHunks` 等）**首批不暴露**（参数结构复杂、agent 按文件粒度足够），doc 记为后续增强。

### 3.4 引擎补齐（GSGitEngine）

新文件 `GitRepository+VCS.swift`（bisect/cherry-pick/revert，写法照抄 `runWrite` 模式）：

```swift
// bisect：mark 类是受控写操作（改变 HEAD），统一 runWrite 留痕；硬闸不涉及（无 -f/--force）
public func bisectStart(bad: String?, good: String?) async throws   // 前置：工作区必须干净（脏区抛错，防 checkout 失败半态）
public func bisectMark(_ mark: BisectMark, rev: String?) async throws // mark = good|bad|skip
public func bisectReset() async throws                               // git bisect reset，回原 HEAD
public func bisectLog() async throws -> String                       // git bisect log 原文
// cherry-pick / revert：冲突时返回 MergeOutcome.conflicts，复用既有冲突流程（resolve/abort）
public func cherryPick(sha: String, noCommit: Bool) async throws -> MergeOutcome
public func revert(sha: String, noCommit: Bool) async throws -> MergeOutcome
```

### 3.5 写操作安全口径（待评审项 WP-1）

- 引擎硬闸原样生效（MCP 层无法也不得绕过）：force push / reset --hard / clean / `-f` 一律拒。
- **总开关**：`GSPaths.appSupportRoot/config.json` 的 `mcpWritesEnabled`（默认 `true`）。GUI 设置页与 server 共读；关闭时写工具返回明确错误提示「已在设置中关闭 MCP 写操作」。
- **破坏性工具**（§3.3 标 ⚠）要求入参 `confirm: true`，否则返回错误并说明影响范围（对齐 MRD 10.2-G「二次确认并说明影响范围」——MCP 场景的「确认」由 Agent 使用者在其客户端完成，App 内 UI 确认不适用）。
- 全部写操作仍走 `runWrite` → JSONL 留痕，来源可区分：MCP 写操作 action 前缀 `mcp.`。
- 与 epic「AI 默认关闭」基调的差异：MCP 是本地 stdio、无数据外发、不内置云端，因此 server 随装可用；但该口径为**待评审项**，若评审认为应对齐默认关闭，仅需把默认值与首启行为翻转，实现不变。

### 3.6 skill 安装与分发（位置规划依据 skill-unify）

- **SSOT**：`~/.agents/skills`（skill-unify 默认生态路径，OpenCode / Cline 原生读取；本机 ZCode 亦发现该路径）。App 只写 SSOT，不复制到各平台私有目录——平台差异由用户侧 `skill-unify sync` 处理，App 不重新实现其链接逻辑（YAGNI）。
- **内置**：skill 源在 workspace `skills/git-space/`；构建时经 GSMCP 的 `resources: [.copy("Skill")]` 进入二进制（`Bundle.module`）。发布前以脚本同步 `skills/git-space/ → Packages/GSMCP/Sources/GSMCP/Skill/`（`scripts/sync-skill.sh`，源为唯一事实源，防止双份漂移；GSMCP 侧目录进 .gitignore？不——SPM resources 必须在源码树内且随仓库提交，采用「脚本同步 + 提交两份、源为准、CI 前校验一致」的简化策略，校验放在 sync 脚本 `--check` 模式）。
- **安装时机**：GUI 启动时对比 bundle 内 skill 版本（SKILL.md frontmatter `version:`）与已装版本（`GSPaths.appSupportRoot/skill-install.json` 记录版本+时间），bundle 较新或未装则自动覆盖写入 `~/.agents/skills/git-space/`；设置页提供「安装/更新 skill」按钮 + 状态行（未装/已装 vX）。
- 写入规则：整目录覆盖（`SKILL.md` + `references/`），保留用户在目录内的其他文件不删（只覆盖已知文件名清单）。

### 3.7 git-space skill 内容（源：workspace `skills/git-space/`）

- `SKILL.md`（frontmatter：name=git-space、description 触发词覆盖「git 操作/bisect 二分/blame/历史/stash/分支/cherry-pick/revert」）：先讲连接方式（App 安装后 MCP server 配置片段）、工具分组地图、读写安全规则（⚠ 工具先看影响再 confirm）。
- `references/workflows.md`：核心工作流手册——bisect 二分定位坏提交（完整对话脚本）、提交链路（status→stage→commit→push）、历史追溯（log/blame/file_history/show_file 组合）、stash 临时切换、分支与合并、cherry-pick 摘取修复、revert 回滚。
- `references/safety.md`：硬闸清单、破坏性工具表、JSONL 日志位置（`~/Library/Application Support/GitSpace/logs/`）。

### 3.8 设置页（SettingsView 新增 Section「MCP 与 Agent（待评审）」）

- MCP 状态行 + 「复制 MCP 配置」按钮（JSON 片段：`{"command": "<可执行文件路径>", "args": ["mcp-serve"]}`，路径用 `Bundle.main.executableURL`，含 `swift run` 开发态回退）。
- 「允许 MCP 写操作」开关（默认开）→ 写 config.json。
- git-space skill 状态行（未安装/已装 vN）+ 「安装/更新 skill」按钮 + 「打开 skill 目录」。

## 4. 不做（YAGNI）

- resources/prompts/sampling 等 MCP 能力面；hunk 级 MCP 工具；App 重新实现 skill-unify 的多平台链接；MCP server 鉴权（stdio 天然本机）；TCP/网络传输；skill 装到平台私有目录；GUI 内 skill 编辑器。

## 5. 验收标准

1. `GitSpaceApp mcp-serve` 以 stdio JSON-RPC 2.0 响应 initialize / tools/list / tools/call；tools/list 包含 §3.3 全部工具。
2. 读工具结果与直接调 `GitRepository` 对应方法等价（测试断言）；写工具触发 `OperationLog` 记录（action 前缀 `mcp.`）。
3. 硬闸回归：经 MCP 无法触发 force push / reset --hard / clean / `-f`（引擎测试已覆盖，补 MCP 层转译断言）。
4. ⚠ 工具缺 `confirm:true` 时被拒且说明影响；`mcpWritesEnabled=false` 时全部写工具被拒。
5. bisect：在 fixture 仓库（含注入 bug 的提交链）上 start→good/bad 迭代→定位→reset，结果与 `git bisect` 手工执行等价（reflog / log 交叉校验）。
6. App 安装后 `~/.agents/skills/git-space/SKILL.md` 存在且与 workspace 源一致；bundle 版本更新后再次启动自动覆盖。
7. `swift build` / `swift test` 全绿；`scripts/package-dmg.sh` 产物含新能力（子命令冒烟）。
8. 文档回写：INDEX.md、docs/INDEX.md、specs/INDEX.md、func、epic（新增 EP09-F07 MCP，标待评审）。

## 6. 工作项拆分

| # | 内容 | 类型 | 关注文件 |
|---|---|---|---|
| W1 | 引擎补齐 bisect / cherry-pick / revert + 等价性测试 | 改造 GSGitEngine | `GitRepository+VCS.swift`、`Tests/GSGitEngineTests/VCSTests.swift` |
| W2 | GSMCP 模块：协议层 + 工具注册 + 引擎映射 + config 读取 + 协议/工具测试 | 新增模块 | `Packages/GSMCP/**`、`Package.swift` |
| W3 | App 接入：MainEntry 子命令分发 + 设置页 Section + skill 安装器（Bundle→SSOT，版本管理） | 改造 App | `GitSpaceApp.swift`、`SettingsView.swift`、`GSInfra/Paths.swift`（config/skill-install 路径） |
| W4 | git-space skill 编写（SKILL.md + references）+ skill-unify 落位 SSOT + sync 脚本 | 新增 | `skills/git-space/**`、`scripts/sync-skill.sh` |
| W5 | 收尾：全量构建/测试/DMG 冒烟 + 文档回写 + summary.md | 收尾 | specs/、INDEX.md、docs/** |

依赖：W1 → W2（工具映射需要新 API）；W4 依赖 W2 的工具清单定稿；W3 与 W1 并行可行、依赖 W2 入口；串行 W1→W2→W3→W4→W5。

## 7. 风险与备注

- MCP 协议手写需对齐客户端实现：以 newline-delimited JSON + 标准 handshake 为准，用真实客户端（ZCode）冒烟验证。
- `~/.agents/skills` 是用户全局目录：App 只写 `git-space/` 自己的子目录，绝不触碰其他 skill。
- 当前工作区有未提交改动（BlameSheet / DiffFileView 等，属 Story-1031-p0-batch1 线）：本 Story 不触碰这些文件；提交只包含本 Story 文件。
- 二进制体积：新增模块预计 <1MB（源码级增量），60MB 约束无虞。

## 8. 决策记录（用户未逐项确认，按推荐项定稿，均可低成本翻案）

| # | 决策 | 依据 | 状态 |
|---|---|---|---|
| D1 | skill 名定为 `git-space`（用户确认初稿 `git-space` 为笔误，2026-10-31 更名） | 与产品名 GitSpace 一致 | 已定 |
| D2 | MCP server = 主二进制子命令 `mcp-serve` | 单二进制、打包零改动、包体不变 | 推荐 |
| D3 | 写操作默认开启 + ⚠ 工具 confirm 参数 + 设置页总开关 | 用户要「读写 skill」；硬闸与 JSONL 不动 | 待评审（WP-1） |
| D4 | 引擎补齐 bisect + cherry-pick + revert | 用户点名 bisect；revert/cherry-pick 是 skill 工作流完整性需要 | 推荐 |
| D5 | skill 落位 `~/.agents/skills`（skill-unify SSOT） | skill-unify 生态默认路径，本机各 Agent 均可发现 | 推荐 |
