# Story-1031 执行契约（tasks.md）

> 工作项定义见 `doc.md` §6，本文件逐项转写为可验收契约。提交信息前缀带工作项编号。
> 全局约束：不触碰 Story-1031-p0-batch1 的在改文件（BlameSheet.swift、DiffFileView.swift、RepoSheets.swift、RootView.swift、TimelineView.swift、WorkingView.swift 及其删除的 DiffTextView.swift）；不修改引擎硬闸；不引入第三方依赖；`GSMCP` 不 import SwiftUI；MCP 模式下 stdout 只允许协议输出。
> 验证基线命令：`cd repos/GitSpace && swift build && swift test`（构建+全量测试）。

---

## Task W1: 引擎补齐 bisect / cherry-pick / revert

- **目标**：`GitRepository` 具备 bisect（start/good/bad/skip/reset/log）、cherry-pick、revert 能力，全部走 `runWrite` 留痕，等价于手工 git CLI。
- **上下文**：`doc.md` §3.4。现有写操作模式参考 `Packages/GSGitEngine/Sources/GSGitEngine/GitRepository+Write.swift`（`runWrite` 定义在 `GitRepository.swift:138`）；冲突返回结构 `MergeOutcome`（Models.swift）已在 merge 中使用。硬闸 `GitProcessRunner.validate`（GitProcessRunner.swift:169）会拦任意 `-f`，新命令不得使用。
- **范围**：新增 `Packages/GSGitEngine/Sources/GSGitEngine/GitRepository+VCS.swift`；新增枚举 `BisectMark`、结果类型（bisect 用 `String` 返回 log 原文，cherry-pick/revert 返回既有 `MergeOutcome`）；测试新增 `Tests/GSGitEngineTests/VCSTests.swift`。不改既有文件（除确需公开的 Parser 复用，最小 diff）。
- **行为细节**：
  - `bisectStart(bad:good:)`：先 `status()` 检查工作区干净（有改动/未跟踪→抛 `GitError`，错误文案说明原因），然后 `git bisect start [bad] [good]`（有则传）。
  - `bisectMark(_ mark:rev:)`：`git bisect good|bad|skip [rev]`；返回 `git bisect log` 原文供调用方了解当前状态（含「is the first bad commit」定位结果）。
  - `bisectReset()`：`git bisect reset`。
  - `bisectLog()`：`git bisect log`（读操作，不走 runWrite）。
  - `cherryPick(sha:noCommit:)`：`git cherry-pick [--no-commit] <sha>`；返回值判定：非零退出且输出含冲突标记→`.conflicts`（用既有冲突检测路径：`rev-parse -q --verify MERGE_HEAD` 不可靠于 cherry-pick，改用 `git status` 含 `Unmerged paths` 或 `CHERRY_PICK_HEAD` 存在判定）；成功→`.merged`。
  - `revert(sha:noCommit:)`：同上，`git revert [--no-commit] <sha>`，`REVERT_HEAD` 判定。
- **验收标准**：
  1. `swift build` 通过。
  2. `swift test --filter VCSTests` 全绿，用例至少覆盖：
     - fixture 仓库 10 个提交、第 7 个注入 bug → bisect start(bad:HEAD, good:首个) + 逐步 good/bad → `bisectLog` 含 "first bad commit" 指向第 7 提交 → reset 后 HEAD 回原位（currentSHA 相等）。
     - bisect 脏工作区 start 被拒（断言错误抛出，且未改变 HEAD）。
     - cherry-pick 干净摘取：目标提交改动出现在 HEAD（`git log -1 --stat` 等价比对 CLI 基准 `GitShell`）。
     - cherry-pick 冲突：返回 `.conflicts`，abort 后工作区回原态。
     - revert 无冲突：生成反向提交（提交数 +1，父提交为 revert 前 HEAD）。
  3. 所有写命令在 `OperationLog`（注入测试 logger）中留痕，action 名分别为 `bisect.start` / `bisect.mark` / `bisect.reset` / `cherry-pick` / `revert`。
- **测试预期**：`swift test --filter VCSTests` 退出码 0。
- **提交**：`[Story-1031-mcp] W1: 引擎层补齐 bisect/cherry-pick/revert 与等价性测试`

## Task W2: GSMCP 模块（协议 + 工具注册 + 引擎映射）

- **目标**：新增 `GSMCP` target，实现最小 MCP stdio server 与 §3.3 工具面，协议往返与工具行为有自动化测试。
- **上下文**：`doc.md` §3.2/§3.3/§3.5。协议要点：newline-delimited JSON-RPC 2.0；`initialize` 返回 `{protocolVersion, capabilities:{tools:{listChanged:false}}, serverInfo:{name:"gitspace-mcp", version}}`，版本协商在支持集 `["2025-06-18","2024-11-05"]` 内取客户端版本、否则回退本地最新；`tools/call` 返回 `{content:[{type:"text",text}], isError?}`；错误（未知工具/参数缺失/仓库无效/写被禁/缺 confirm）→ `isError:true` + 文本原因。响应带 `jsonrpc:"2.0"` 与 `id`，notification 不回包。
- **范围**：`Packages/GSMCP/Sources/GSMCP/` 新文件——`MCPServer.swift`（stdio 循环+dispatch）、`JSONRPC.swift`（最小编解码，`Codable`）、`ToolRegistry.swift`（工具元数据：name/description/inputSchema/是否写/是否需 confirm）、`GitTools.swift`（读工具映射）、`GitWriteTools.swift`（写工具映射+confirm/config 检查，action 前缀 `mcp.`）、`MCPSkillInstaller.swift` 留 W3。`Package.swift` 注册 target 并给 `GitSpaceApp` 加依赖（W3 用）；GSMCP 依赖 GSGitEngine/GSIndex/GSInfra。
- **config**：`GSInfra/GSPaths` 增加 `configFile`（`appSupportRoot/config.json`）；GSMCP 读 `{"mcpWritesEnabled": Bool}`（缺省 true），每次 tools/call 写工具时重读（不缓存，保证设置页改动即时生效）。
- **长输出保护**：单工具响应文本 >512_000 字节时截断并追加尾部提示行（含原始字节数）。
- **验收标准**：
  1. `swift test --filter MCPTests` 全绿，覆盖：initialize 往返（版本协商 2024-11-05 客户端 / 未知版本回退）、tools/list 含全部工具且 inputSchema 为合法 JSON object、ping、未知方法返回 JSON-RPC error code -32601、未知工具 isError。
  2. 工具行为测试（fixture 仓库）：`git_status` 与直接引擎调用等价；`git_stage`+`git_commit` 落一个提交且 OperationLog 有 `mcp.commit` 记录；`git_discard` 无 confirm 被拒、有 confirm 成功；config `mcpWritesEnabled=false` 时 `git_commit` 被拒。
  3. `GSMCP` 源码 0 处 `import SwiftUI`。
- **测试预期**：`swift test --filter MCPTests` 退出码 0。
- **提交**：`[Story-1031-mcp] W2: GSMCP 模块——MCP stdio 协议与 git 读写工具映射`

## Task W3: App 接入（子命令分发 + 设置页 + skill 安装器）

- **目标**：`GitSpaceApp mcp-serve` 可启动 server（GUI 不弹）；设置页新增「MCP 与 Agent」Section；skill 安装器把 Bundle 内 skill 装入 `~/.agents/skills/git-space/` 并随启动自动更新。
- **上下文**：`doc.md` §3.1/§3.6/§3.8。现 `GitSpaceApp.swift` 的 `@main` 需迁移到新 `MainEntry`；设置页 Section 模式参考 `SettingsView.swift` 的「环境」Section。
- **范围**：
  - `GitSpaceApp.swift`：去 `@main`，新增 `MainEntry`（@main）：`CommandLine.arguments.contains("mcp-serve")` → 同步运行 GSMCP server 后 `exit(0)`；否则 `GitSpaceApp.main()`。
  - `GSInfra/Paths.swift`：新增 `configFile`、`skillInstallManifest`（`appSupportRoot/skill-install.json`）。
  - 新文件 `App/Sources/GitSpaceApp/MCPSettings.swift`：设置 Section 视图（MCP 配置 JSON 复制按钮——路径 `Bundle.main.executableURL`，`swift run` 开发态回退 `.build` 产物路径；写开关 Toggle 绑定 config.json；skill 状态行 + 安装按钮 + 打开目录）。
  - `MCPSkillInstaller`（GSMCP 内）：`installIfNeeded(bundle: Bundle, force: Bool) -> InstallResult`——读 bundle `Skill/` 下文件清单与版本（SKILL.md frontmatter `metadata.version`），对比 `skill-install.json`，需要时覆盖写入 `~/.agents/skills/git-space/`（只覆盖清单内文件，不删用户其他文件）；GUI 启动时调用一次（后台 Task，失败仅记日志不打断启动）。
  - 打包/资源：`Package.swift` GSMCP target 加 `resources: [.copy("Skill")]`；`scripts/sync-skill.sh`（W4 产出 skill 后同步 `skills/git-space → Packages/GSMCP/Sources/GSMCP/Skill`，带 `--check` 校验模式）。
- **验收标准**：
  1. `swift run GitSpaceApp mcp-serve` 进程内 echo 一条 initialize 请求得到合法响应（冒烟脚本或手测记录），且无 GUI 窗口、无 Dock 图标。
  2. `swift run GitSpaceApp`（GUI）启动正常，skill 自动装入 `~/.agents/skills/git-space/SKILL.md`；设置页可见 MCP Section；写开关关闭后 config.json 值变化且 `mcp-serve` 进程读生效（测试层断言 config 读取函数）。
  3. `swift test --filter SkillInstall` 覆盖：未装→安装成功、同版本跳过、高版本覆盖、目标目录已有用户额外文件不被删除。
- **测试预期**：`swift build && swift test` 全绿；`echo '...' | swift run GitSpaceApp mcp-serve` 冒烟输出合法 JSON-RPC 响应。
- **提交**：`[Story-1031-mcp] W3: App 接入——mcp-serve 子命令/设置页/skill 安装器`

## Task W4: git-space skill 编写与落位

- **目标**：产出完整可用的 `git-space` skill，经 skill-unify 装入 SSOT，并同步进 Bundle 源。
- **上下文**：`doc.md` §3.7；工具名以 W2 定稿的 ToolRegistry 为准（实现时以代码为准核对，skill 中工具名必须与 tools/list 输出一致）。
- **范围**：`skills/git-space/SKILL.md` + `references/workflows.md` + `references/safety.md`；运行 `scripts/sync-skill.sh`；skill-unify 安装（`python3 ~/.agents/skills/skill-unify/scripts/skill-unify install /Users/jiazihui/Documents/VibeSpace/GitSpace/skills/git-space`，先看计划再 `--yes`；SSOT 为默认 `~/.agents/skills`）。
- **内容要求**：
  - SKILL.md：frontmatter（name: git-space；description 覆盖 git 读写/bisect/blame/历史/stash/分支/cherry-pick/revert 触发词；metadata.version: 1.0.0）；正文：MCP 配置方法（配置片段模板）、工具分组地图、读写规则（⚠ 工具先述影响再 confirm）、常见反模式（未确认就 confirm、跨仓批量写不看 status）。
  - workflows.md：bisect 完整脚本（含 good/bad 迭代与结果解读）、提交链路、历史追溯组合、stash、分支合并、cherry-pick/revert，每个工作流给出工具调用顺序与失败分支处理。
  - safety.md：硬闸清单、⚠ 工具表、JSONL 日志路径与排查方法。
- **验收标准**：
  1. `~/.agents/skills/git-space/SKILL.md` 存在且与 workspace 源哈希一致（skill-unify install 输出确认）。
  2. skill 内引用的工具名与 `tools/list` 输出零偏差（实现后用脚本比对）。
  3. `scripts/sync-skill.sh --check` 通过（workspace 源与 Bundle 源一致）。
- **提交**：`[Story-1031-mcp] W4: git-space skill 编写与 skill-unify 落位`

## Task W5: 收尾（全量验证 + 文档回写 + summary）

- **目标**：全链路验证通过，知识与索引同步，实施记录归档。
- **范围**：
  1. `swift build && swift test` 全绿；`scripts/package-dmg.sh arm64` 产出 DMG，对产物内二进制跑 `mcp-serve` 冒烟（initialize 往返）。
  2. 文档回写：根 `INDEX.md`（代码模块表加 GSMCP 行、已知坑如有）、`docs/INDEX.md`（story 落位）、`docs/func/GitSpace-Features-v1.0.md`（新增 MCP 与 skill 章节标待评审）、`docs/epic/INDEX.md`（新增 EP09-F07「MCP server 与 git-space skill」，标待评审，并把 WP-1 写入口径并入 §7.8 AI 数据外发待定项）、`specs/INDEX.md`（登记本 Story）、`source/gitspace/overview.md`（模块树补 GSMCP + mcp-serve 说明）。
  3. `summary.md`：偏离项、验证证据（命令+输出摘要）、遗留建议。
- **验收标准**：上述命令与回写全部完成；summary 中未勾选项如实标注。
- **提交**：`[Story-1031-mcp] W5: 收尾——全量验证与文档回写`
