# GitSpace MVP（v0.1.0）实施计划

> 面向执行者：逐个 Task 实施本计划，步骤用 checkbox (`- [ ]`) 跟踪。
> **本文档为回溯归档**：实现先于文档完成（2026-10-29），每个 Task 的「复核状态」记录了实际完成情况与验证证据；实现过程记录见 [Story-1029-mvp-coding](../Story-1029-mvp-coding/)。

**目标：** 在 `repos/GitSpace/` 落地 GitSpace MVP——多仓纳管、跨仓统一时间线、批量同步、提交（含块级暂存）、分支、合并冲突、stash/tag 的 macOS 原生客户端，构建/测试/冒烟全部通过。

**架构：** SPM 多模块 + 单 App target（TechStack §9），依赖单向 `App → GSFeatures → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra`。系统 git CLI 为唯一执行与数据来源，每仓一个 actor 门面，UI 层 `@MainActor @Observable`。方案详见同目录 `doc.md`。

**技术栈：** Swift 6.4（语言模式 v6 严格并发）、SwiftUI + AppKit 混编、Swift Testing、零第三方依赖、部署目标 macOS 14。

**工作项清单来源：** `doc.md` §工作项拆分（W1–W14）。

**提交绑定策略：** 提交信息前缀带上工作项编号，例如 `W3: Git 进程执行器与安全闸`。（回溯说明：本轮一次性落地且 Workspace 尚未 git 化，无逐项提交记录；后续迭代按此策略执行。）

## 工作项任务列表

| Task | 工作项编号 | 工作项标题 | 复核状态 |
| --- | --- | --- | --- |
| Task 1 | W1 | 工程骨架与严格并发基线 | ✅ 已完成 |
| Task 2 | W2 | GSInfra 基础设施 | ✅ 已完成 |
| Task 3 | W3 | Git 进程执行器与安全闸 | ✅ 已完成 |
| Task 4 | W4 | git 输出解析器套件 | ✅ 已完成 |
| Task 5 | W5 | 单仓引擎门面与写操作 | ✅ 已完成 |
| Task 6 | W6 | 工作区扫描与配置存储 | ✅ 已完成 |
| Task 7 | W7 | 跨仓时间线聚合 | ✅ 已完成 |
| Task 8 | W8 | ViewModel 状态层 | ✅ 已完成 |
| Task 9 | W9 | App 骨架与全局组件 | ✅ 已完成 |
| Task 10 | W10 | 时间线视图与 diff 渲染 | ✅ 已完成 |
| Task 11 | W11 | 状态总览与批量面板 | ✅ 已完成 |
| Task 12 | W12 | 改动提交与分支合并视图 | ✅ 已完成 |
| Task 13 | W13 | 测试基建与等价性用例 | ✅ 已完成（26/26） |
| Task 14 | W14 | 文档与索引同步 | ✅ 已完成 |

---

### Task 1: 工程骨架与严格并发基线

## 目标
SPM 工程可 `swift build` 通过，产出 `GitSpaceApp` 可执行产品；模块边界与依赖方向符合 TechStack §9。

## 上下文
一切代码的承载结构，后续所有 Task 在此骨架内落文件。

## 工作项绑定
- 编号：W1
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：`Package.swift`、各 target 目录骨架
- 范围外：任何业务代码

## 相关文件
- 创建：`repos/GitSpace/Package.swift`
- 创建：`repos/GitSpace/{App/Sources/GitSpaceApp, Packages/{GSInfra,GSDesignKit,GSGitEngine,GSIndex,GSFeatures,GSTestSupport}/Sources/<module>, Tests/{GSGitEngineTests,GSIndexTests}}`

## 验收标准
- [x] `swift build` 零错误，products 含 executable `GitSpaceApp`
- [x] 依赖方向：GSFeatures → GSGitEngine/GSIndex/GSDesignKit/GSInfra；GSGitEngine、GSIndex 不依赖 SwiftUI
- [x] Swift 6 语言模式（`swiftLanguageModes: [.v6]`）+ 部署目标 macOS 14

## 测试预期
- 命令：`cd repos/GitSpace && swift build`
- 预期结果：退出码 0，无 error；`swift build --show-bin-path` 产物可执行
- 复核状态（2026-10-29）：✅ 通过，0 error

## 约束
- 零第三方依赖（GRDB 暂缓见 doc.md 明确不做）；工具链 Xcode 27+

---

### Task 2: GSInfra 基础设施

## 目标
提供应用数据目录约定、JSONL 操作日志与并发限流信号量，供引擎与特性层使用。

## 上下文
依赖链最底层；操作日志是 MRD 10.2-G「写操作全量留痕」的落点，信号量是批量并发 4 的执行原语。

## 工作项绑定
- 编号：W2
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：GSInfra 模块内三个工具
- 范围外：任何 git 语义

## 相关文件
- 创建：`Packages/GSInfra/Sources/GSInfra/Paths.swift`
- 创建：`Packages/GSInfra/Sources/GSInfra/OperationLog.swift`
- 创建：`Packages/GSInfra/Sources/GSInfra/AsyncSemaphore.swift`

## 验收标准
- [x] `OperationLog.record` 追加写 `logs/ops-yyyy-MM-dd.jsonl`，写失败静默不影响业务
- [x] `AsyncSemaphore(4).wait()/signal()` 在 TaskGroup 下限流正确，`NSLock` 仅经 `withLock` 使用（async 上下文禁止直接 lock/unlock）
- [x] `GSPaths.ensureDirectory` 幂等创建 `~/Library/Application Support/GitSpace/` 子目录

## 测试预期
- 单元测试：`AsyncSemaphore` 行为经 Task 13 批量链路与 `swift test` 全量间接覆盖；日志 roundtrip 由 `WorkspaceStore` 测试同目录策略覆盖
- 命令：`swift build`
- 预期结果：编译通过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 日志按日滚动文件名 `ops-<yyyy-MM-dd>.jsonl`，每行一条 `OperationLogEntry` JSON

---

### Task 3: Git 进程执行器与安全闸

## 目标
统一的 git 进程执行 actor：60s 超时、取消即终止进程、仅网络类错误重试 1 次、错误按语义分类；参数级安全闸拦截危险命令。

## 上下文
TechStack §5.2 进程层设计；MRD 10.2-G「永不 force push」的引擎级硬闸落点。所有 git 调用（读写）都经过它。

## 工作项绑定
- 编号：W3
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：进程执行、错误分类、安全闸
- 范围外：具体 git 命令语义（Task 5）、输出解析（Task 4）

## 相关文件
- 创建：`Packages/GSGitEngine/Sources/GSGitEngine/GitProcessRunner.swift`
- 创建：`Packages/GSGitEngine/Sources/GSGitEngine/GitError.swift`

## 验收标准
- [x] `run` 对非零退出按 stderr 关键词归类 `GitError`（conflict/nonFastForward/auth/network/hookFailed/nothingToCommit 等）；`runRaw` 保留原始退出码不抛业务错误
- [x] 超时（默认 60s）→ SIGTERM；Task 取消 → 终止进程并抛 `.cancelled`；网络类错误重试恰 1 次，鉴权/非快进绝不重试
- [x] stdout/stderr 管道与进程并行读（防 64KB 死锁）；continuation 经 `OnceBox` 恰好恢复一次
- [x] `validate` 拦截 `push --force*`、`-f`、`reset --hard`、`clean`；环境透传 + `GIT_TERMINAL_PROMPT=0`

## 测试预期
- 单元测试：`forcePushNeverAllowed`、`resetHardAndCleanDenied`、`nonFastForwardPushRejectedByGitNotSilenced`
- 命令：`swift test --filter "Commit & Safety"`
- 预期结果：3 条用例全过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 继承用户 shell 环境（PATH/SSH_AUTH_SOCK/代理）；不改写用户 git 配置

---

### Task 4: git 输出解析器套件

## 目标
四组纯函数解析器：porcelain v2 状态、log 自定义分隔符、for-each-ref、unified diff，输出强类型模型；diff 解析保留原始行以支持 patch 逐字重组。

## 上下文
TechStack §5.1「数据只来自 CLI 输出」的解析侧；块级暂存管线（Task 5）的重组基础。 porcelain 字段数是已知坑（见 Task 13 踩坑记录）。

## 工作项绑定
- 编号：W4
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：解析器与值模型（`RepoStatus`/`CommitInfo`/`BranchInfo`/`FileDiff` 等）
- 范围外：进程执行、仓库门面

## 相关文件
- 创建：`Packages/GSGitEngine/Sources/GSGitEngine/Parsers.swift`
- 创建：`Packages/GSGitEngine/Sources/GSGitEngine/DiffParser.swift`
- 创建：`Packages/GSGitEngine/Sources/GSGitEngine/Models.swift`

## 验收标准
- [x] porcelain v2：`# branch.*` 头（含 `branch.ab` 的 `+N -M`）、`1`（9 token）/`2`（10 token + NUL origPath）/`u`（11 token）/`?` 记录全解析；`Data` 切片用 `String(decoding:as:)` 转字符串
- [x] log：`%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%ct%x1f%P%x1f%D%x1f%s%x1f%b%x1e` 记录/字段分离，decorations 拆分
- [x] for-each-ref：本地分支（upstream/track/HEAD）、远程分支（剔除 origin/HEAD）、tag（objecttype 区分 annotated）、stash（`stash@{N}` 序号）
- [x] unified diff：`diff --git`/`@@` 头定位，`+ - 空 \` 四类行，`FileDiff.patch(selectingHunkIDs:)` 重组与原文逐字一致

## 测试预期
- 单元测试：`statusMatchesPorcelainV2`、`commitLogOrderAndFields`、`diffRoundtripPreservesPatchText`、`branchAheadBehindFromUpstream`
- 命令：`swift test --filter "Status & Log"` 与 `swift test --filter "Hunk Staging"`
- 预期结果：全过
- 复核状态（2026-10-29）：✅ 通过（roundtrip 与原始 `git diff` 输出 byte 级一致）

## 约束
- 解析器零副作用纯函数；不 import SwiftUI

---

### Task 5: 单仓引擎门面与写操作

## 目标
每仓一个 `GitRepository` actor：只读快照（status/commits/diff/refs/stash 列表）+ 全部写操作（暂存/提交/分支/合并冲突/stash/tag），写操作统一经操作日志留痕。

## 上下文
TechStack §7.1 actor 模型（同仓串行、跨仓并行）；MRD 10.2-C/D/E/F 的引擎实现；块级暂存管线在此闭环（`git apply --cached [--reverse] -`）。

## 工作项绑定
- 编号：W5
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：GitRepository 两个文件
- 范围外：UI 状态层（Task 8）、进程与解析（Task 3/4）

## 相关文件
- 创建：`Packages/GSGitEngine/Sources/GSGitEngine/GitRepository.swift`
- 创建：`Packages/GSGitEngine/Sources/GSGitEngine/GitRepository+Write.swift`

## 验收标准
- [x] 块级暂存：选中 hunk 重组 patch → `git apply --cached --whitespace=nowarn -`；取消暂存走 `--cached --reverse`；失败原样抛错不静默改写
- [x] 提交：暂存区空抛 `.nothingToCommit`；amend 父提交不变；钩子失败抛 `.hookFailed` 且 HEAD 不动
- [x] 分支：切换前脏工作区预检抛 `.uncommittedChanges`；删除支持 `-d`/`-D`；检出远程 `switch --track` 建 upstream
- [x] 合并：ff/no-ff/auto 三态；冲突返回 `MergeOutcome.conflicts(porcelain u 记录)`；`merge --abort`、`commit --no-edit` 收尾
- [x] stash/tag：push/pop/apply/drop、轻量与附注 tag、写操作全量进 JSONL 日志（测试注入 nil 可关）

## 测试预期
- 单元测试：`stagedResultEqualsFilteredPatch`、`unstageHunksReversesSelection`、`stageWholeFileMatchesGitAdd`、`commitAdvancesHeadOnce`、`amendKeepsParentUnchanged`、`hookFailureSurfacesRawOutputAndNoCommit`、`createSwitchDeleteBranch`、`dirtyWorkspaceBlocksSwitch`、`deleteUnmergedBranchRequiresForce`、`renameBranch`、`checkoutRemoteBranchSetsUpstream`、`conflictListMatchesGitPorcelain`、`oursTheirsMatchGitCheckout`、`abortMergeRestoresPreMergeState`、`fullConflictResolutionFlow`、`stashRoundtrip`、`tagsCreateListDelete`
- 命令：`swift test --filter "Hunk Staging"`、`--filter "Branch & Merge"`、`--filter "Commit & Safety"`
- 预期结果：全过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 无 `push --force` / `reset --hard` / `clean` 调用路径；丢弃改动仅 `git restore` 逐文件 + 未跟踪文件 FileManager 删除

---

### Task 6: 工作区扫描与配置存储

## 目标
父目录递归发现 Git 仓库（含 worktree/submodule 的 .git 文件形态），工作区配置 JSON 持久化与恢复。

## 上下文
MRD 10.2-A 纳管与 10.6 流程一；TechStack §6.2 工作区配置 JSON 载体。

## 工作项绑定
- 编号：W6
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：扫描器与存储
- 范围外：仓库状态读取（Task 5）、UI 弹窗（Task 11）

## 相关文件
- 创建：`Packages/GSIndex/Sources/GSIndex/WorkspaceScanner.swift`
- 创建：`Packages/GSIndex/Sources/GSIndex/WorkspaceStore.swift`

## 验收标准
- [x] 扫描深度 3，跳过 node_modules/build/Pods/DerivedData 等 15 类目录，命中 `.git` 即停不下钻，结果按名称排序并标记 `alreadyManaged`
- [x] 配置 roundtrip：`WorkspaceConfig`（id/name/repos/createdAt）写 `workspaces/workspaces.json`，跨实例读取一致，损坏文件返回空数组不崩溃

## 测试预期
- 单元测试：`discoversReposSkippingBuildDirs`、`roundtripConfig`
- 命令：`swift test --filter "Scanner & Workspace"`、`--filter "WorkspaceStore"`
- 预期结果：全过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 存储路径 `~/Library/Application Support/GitSpace/workspaces/`；NSLock 串行化文件 IO

---

### Task 7: 跨仓时间线聚合

## 目标
把多仓提交合并为一条按 committer 时间降序、sha 升序稳定排序的时间线，每仓一条 lane。

## 上下文
MRD §9 产品内核（IDEA 多仓合并 Log 对标）；MVP 简化为每仓一 lane（偏离项，见 doc.md）。

## 工作项绑定
- 编号：W7
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：`TimelineCommit` 与聚合器
- 范围外：DAG lane 布局（P1）、过滤逻辑（Task 8）

## 相关文件
- 创建：`Packages/GSIndex/Sources/GSIndex/Timeline.swift`

## 验收标准
- [x] 跨仓提交按时间降序合并，时间相同按 sha 稳定排序；`colorSlot`/`lane` 按仓序号分配；id 含 sha+repoName 防跨仓碰撞

## 测试预期
- 单元测试：`mergesAndSortsAcrossRepos`
- 命令：`swift test --filter "Timeline Aggregator"`
- 预期结果：通过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 值类型 Sendable，可在 TaskGroup 内跨并发域传递

---

### Task 8: ViewModel 状态层

## 目标
`@MainActor @Observable` 四个模型：AppModel（纳管/逐仓状态刷新）、BatchSyncModel（批量状态机）、TimelineModel（加载/过滤/详情）、RepoViewModel（当前仓改动/暂存/提交/分支/合并/stash/tag 全量操作）。

## 上下文
TechStack §7.1 UI 状态层；引擎 actor 与 SwiftUI 之间的唯一隔离层，视图层（Task 9–12）只读模型。

## 工作项绑定
- 编号：W8
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：GSFeatures 三个 Model 文件 + ToastCenter/GitPresenter
- 范围外：SwiftUI 视图、引擎行为变更

## 相关文件
- 创建：`Packages/GSFeatures/Sources/GSFeatures/AppModel.swift`
- 创建：`Packages/GSFeatures/Sources/GSFeatures/TimelineModel.swift`
- 创建：`Packages/GSFeatures/Sources/GSFeatures/RepoViewModel.swift`

## 验收标准
- [x] 批量状态机：queued/running/succeeded/skipped(原因)/failed(原因)/cancelled，TaskGroup + AsyncSemaphore 并发可调，取消保留已完成仓，失败可重跑
- [x] 单仓失败不阻塞：`refresh` 按仓隔离 errorText（MRD 10.4-7）
- [x] 脏工作区切换抛 `SwitchBlocker.dirtyWorkspace`，提供 `stashThenSwitchBranch` 补偿路径；合并中状态（MERGE_HEAD）驱动 canCommitMerge
- [x] 时间线过滤五维（仓/分支/作者/时间窗/关键字）纯函数可判定，窗口天数来自 AppModel 设置

## 测试预期
- 单元测试：本层经 Task 13 引擎用例 + `swift build` 编译期并发检查覆盖（VM 层语义依赖真实 UI 交互，独立单测列入 M1）
- 命令：`swift build`（严格并发零警告错误）
- 预期结果：编译通过
- 复核状态（2026-10-29）：✅ 完成；VM 级行为单测（批量状态机编排）列为 M1 待补项

## 约束
- `@MainActor` 类的 `Identifiable.id` 等跨并发访问成员需 `nonisolated`；模型只持有引擎 actor 引用不复制 git 数据

---

### Task 9: App 骨架与全局组件

## 目标
可启动的 GUI 应用：三栏骨架、侧栏仓库列表（徽标 ↑↓●✓）、toast、状态栏、设置页、明暗跟随主题。

## 上下文
TechStack §4.1 SwiftUI 主导；交互对齐原型 titlebar/sidebar/statusbar。

## 工作项绑定
- 编号：W9
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：App 模块骨架与全局组件
- 范围外：四个业务视图（Task 10–12）

## 相关文件
- 创建：`App/Sources/GitSpaceApp/GitSpaceApp.swift`
- 创建：`App/Sources/GitSpaceApp/RootView.swift`
- 创建：`App/Sources/GitSpaceApp/SidebarView.swift`
- 创建：`App/Sources/GitSpaceApp/Components.swift`
- 创建：`App/Sources/GitSpaceApp/SettingsView.swift`

## 验收标准
- [x] SPM 可执行直接运行即为常规 GUI 应用（AppDelegate 提升 activation policy），窗口最小 1180×700
- [x] 侧栏：工作区卡、仓库筛选（⌘K 占位）、仓库行（色点/名称/分支/同步徽标）、右键移除确认；添加/扫描入口带快捷键
- [x] 设置页：并发度 1–8、Pull 模式、时间窗口、主题三态、打开日志目录、git 版本展示

## 测试预期
- 运行时验证：`.build/debug/GitSpaceApp` 启动 4 秒存活无崩溃，RSS ≈ 136MB（MRD 空载 ≤200MB 预算内）
- 命令：`swift build && .build/debug/GitSpaceApp & sleep 4 && kill %1`
- 预期结果：进程存活
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 界面代码只引用 GSDesignKit 令牌与系统语义色，不写死 hex

---

### Task 10: 时间线视图与 diff 渲染

## 目标
统一时间线：过滤栏（仓库/分支/作者/时间/关键字 + 计数）、提交列表（图列/信息/仓库 chip/时间）、详情面板（元数据/文件列表/选中文件 diff）。

## 上下文
MRD 10.6 流程二（跨仓核对核心路径）；TechStack §4.3「SwiftUI 列表 + AppKit diff」分工。

## 工作项绑定
- 编号：W10
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：TimelineView 与 DiffTextView
- 范围外：状态页（Task 11）、改动页（Task 12）

## 相关文件
- 创建：`App/Sources/GitSpaceApp/TimelineView.swift`
- 创建：`App/Sources/GitSpaceApp/DiffTextView.swift`

## 验收标准
- [x] 列表选中触发详情异步加载；过滤无结果给空态 + 一键重置；截断仓显示「已按时间窗口截断」提示条
- [x] 图列 Canvas 每仓一 lane（节点 + 纵向连线 + 仓色）；行内 MERGE 徽标、作者徽章、短 SHA、相对时间
- [x] diff 渲染走 AppKit NSTextView（NSViewRepresentable）：+/− 行红绿底色、hunk 头强调色、上下文灰、万行级可滚动

## 测试预期
- 编译 + 冒烟：`swift build`；交互验收（人负责）
- 命令：`swift build`
- 预期结果：通过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 相对时间用 `RelativeDateTimeFormatter`（`.abbreviated`）；详情面板宽度 330–460 可拖

---

### Task 11: 状态总览与批量面板

## 目标
多仓状态总览：四统计卡、逐仓表格（复选框多选）、批量操作条；批量执行 Sheet（逐仓状态机展示、取消、重跑失败项）；添加仓库与扫描父目录弹窗。

## 上下文
MRD 10.6 流程三/四；原型 status 视图与 batch 弹窗。

## 工作项绑定
- 编号：W11
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：StatusView 与 Sheets（AddRepo/Scan/Batch）
- 范围外：批量执行逻辑（Task 8）

## 相关文件
- 创建：`App/Sources/GitSpaceApp/StatusView.swift`
- 创建：`App/Sources/GitSpaceApp/Sheets.swift`

## 验收标准
- [x] 统计卡数值来自 AppModel 聚合（纳管/干净/待同步/需处理）；「选中待同步」一键勾选异常仓
- [x] 批量 Sheet：每仓 queued/running/成功/跳过/失败+原因实时刷新；运行中可取消；完成后可重跑失败项并 toast 汇总
- [x] 扫描弹窗：目录选择 → 发现列表（已纳管禁选）→ 勾选导入；添加弹窗：路径 + fileImporter + 校验错误提示

## 测试预期
- 编译 + 冒烟：`swift build`；真实远端批量行为由 Task 13 的本地 bare 远端用例背书
- 命令：`swift build`
- 预期结果：通过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 表格用 Grid 手绘（非 SwiftUI Table），列对齐原型；目录枚举放后台任务不卡 UI

---

### Task 12: 改动提交与分支合并视图

## 目标
当前仓工作视图：未暂存/未跟踪/已暂存三区 + hunk 勾选暂存 + 提交栏（amend/钩子输出/合并中收尾）；分支管理页：合并与冲突选边、分支 CRUD、stash、tag。

## 上下文
MRD 10.6 流程五（提交）与流程六（分支合并）；冲突「列表 + 选边 + 外部工具」中的列表与选边。

## 工作项绑定
- 编号：W12
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：WorkingView 与 RepoView
- 范围外：时间线（Task 10）、引擎语义（Task 5）

## 相关文件
- 创建：`App/Sources/GitSpaceApp/WorkingView.swift`
- 创建：`App/Sources/GitSpaceApp/RepoView.swift`

## 验收标准
- [x] 改动区三段（未暂存/未跟踪/已暂存）行内 暂存/取消/丢弃 按钮；丢弃走 confirmationDialog 二次确认；hunk 勾选支持「暂存/取消暂存选中块」（未勾选默认全选）
- [x] 提交栏：message 编辑、amend 开关、canCommit 门禁（合并中要求冲突清零）、钩子失败原始输出 DisclosureGroup、错误红字提示
- [x] 合并区：冲突行提供 取当前/取对方/生成合并标记/标记已解决；全部解决才亮「完成合并提交」；随时可中止（强确认）；非合并态提供来源分支选择 + no-ff 开关
- [x] 分支区：创建（基于 HEAD/指定点）、切换、重命名、删除强确认（-d/-D 分列）；远程分支检出；stash 保存/pop/apply/丢弃确认；tag 创建（轻量/附注）与删除确认

## 测试预期
- 编译 + 冒烟：`swift build`；等价性由 Task 13 引擎用例背书
- 命令：`swift build`
- 预期结果：通过
- 复核状态（2026-10-29）：✅ 通过

## 约束
- 破坏性操作（丢弃/强删/stash 丢弃/中止合并/tag 删除）全部 confirmationDialog，不提供无确认路径

---

### Task 13: 测试基建与等价性用例

## 目标
GitShell（同步 CLI 基准）+ FixtureRepo（多 hunk/冲突/钩子场景生成器），26 条用例覆盖 MRD 10.4 的 3/4/9/10/11/12/13 条。

## 上下文
TechStack §13 测试策略；等价性基准 = git CLI 本身。

## 工作项绑定
- 编号：W13
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：GSTestSupport 与 Tests 两目录
- 范围外：性能基准（M0）、UI 自动化（M1）

## 相关文件
- 创建：`Packages/GSTestSupport/Sources/GSTestSupport/GitShell.swift`
- 创建：`Packages/GSTestSupport/Sources/GSTestSupport/FixtureRepo.swift`
- 创建：`Tests/GSGitEngineTests/StatusAndLogTests.swift`
- 创建：`Tests/GSGitEngineTests/HunkStagingTests.swift`
- 创建：`Tests/GSGitEngineTests/BranchMergeTests.swift`
- 创建：`Tests/GSGitEngineTests/CommitAndSafetyTests.swift`
- 创建：`Tests/GSIndexTests/ScannerAndTimelineTests.swift`

## 验收标准
- [x] fixture 全部落临时目录并自清理路径；等价性断言与 `GitShell.run` 原始输出逐项比对（非仅自解析器互证）
- [x] 网络类用例用本地 bare 仓模拟远端（clone --bare + push 被拒场景），不依赖外网
- [x] `swift test` 全量通过：4 Suite / 26 tests

## 测试预期
- 命令：`cd repos/GitSpace && swift test`
- 预期结果：`Test run with 26 tests in 4 suites passed`
- 复核状态（2026-10-29）：✅ 26/26 通过（测试后清理：`rm -rf "${TMPDIR:?}"/gitspace-tests`）

## 约束
- fixture 用户身份固定（Tester/tester@example.com）保证断言确定性；解析器字段数坑（u=11 token 等）以用例固化防回归

---

### Task 14: 文档与索引同步

## 目标
按 AGENTS.md 收尾约定落盘：本 spec（doc.md + tasks.md）、实施记录、source 三件套、根 INDEX 与 repo-structure 同步。

## 上下文
AGENTS.md §3「收尾：产出沉淀到 docs/story，运行知识写入对应 docs 或 skill」与「索引同步」硬规则。

## 工作项绑定
- 编号：W14
- 来源：`doc.md` 工作项拆分

## 范围
- 范围内：specs、source、INDEX、repo-structure
- 范围外：MRD/TechStack 正文（偏离项只登记不擅自改约束）

## 相关文件
- 创建：`specs/Story-1029-mvp-plan/doc.md`、`tasks.md`（本文件）
- 创建：`specs/Story-1029-mvp-coding/doc.md`、`summary.md`（实施记录）
- 创建：`source/gitspace/overview.md`、`setup.md`、`test.md`
- 修改：`source/index.md`、`INDEX.md`、`docs/repo-structure.md`

## 验收标准
- [x] 新增/移动的模块与文档在 INDEX.md 全部登记，偏离项可见
- [x] 三件套可让无上下文执行者完成构建、运行、测试

## 测试预期
- 人工核对：INDEX 引用路径与实际文件一一对应
- 复核状态（2026-10-29）：✅ 完成

## 约束
- 不修改 MRD/TechStack 正文决策，偏离项单独成节待评审
