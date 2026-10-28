# Story 1029 · MVP 版编码开发（doc）

## 1. 需求与目标

接需求「结合 MRD、技术栈和设计稿交互，完成 MVP 版应用的编码开发」。对应 MRD v1.5（文件 v2.0）路线一（替代型）的落地：把「日常上班不出这个窗口」的 P0 闭环做出第一版可运行实现，交互对齐 `design/gitspace-prototype/index-origin.html`。

## 2. MVP 范围（对齐 MRD 里程碑）

取 **M1 骨架与同步 + M2 日常闭环** 的核心子集：

| 能力域 | 范围 | MRD 依据 |
|---|---|---|
| 工作区纳管 | 手动添加 + 父目录扫描（深度 3、跳过构建产物）+ JSON 持久化恢复 + 移除 | 10.2-A |
| 跨仓时间线 | `git log --all` 合并排序、五维过滤、详情 diff、时间窗截断提示 | 10.2-A |
| 多仓状态 | 分支/领先落后/未提交/未推送/最近 fetch，统计卡 + 表格 + 批量选择 | 10.6 流程三 |
| 批量同步 | fetch / pull(ff-only 默认) / push，逐仓状态机、取消、失败重跑，并发 4 | 10.2-B |
| 提交链路 | 三区改动列表、文件级 + 块级暂存、commit / amend、丢弃（二次确认）、钩子输出透出 | 10.2-C |
| 分支 | 创建/切换（脏区引导）/删除（-d / 强确认 -D）/重命名/检出远程 | 10.2-D |
| 合并冲突 | ff/no-ff、冲突列表、ours/theirs/生成标记/标记解决、中止、完成合并提交 | 10.2-E |
| stash / tag | 保存/pop/apply/drop；轻量+附注 tag 创建删除 | 10.2-F |
| 安全边界 | 引擎参数级硬闸（禁 force/reset --hard/clean/-f）、写操作 JSONL 日志、破坏性操作 UI 二次确认 | 10.2-G |

**不在本版**（按 MRD 10.3 原样后移）：变更集/卡片号聚合检索（P1 视图，原型有演示页但属 P1 范围）、行级暂存、cherry-pick/revert、rebase、图片 diff、GRDB 索引与 FTS5、统计上报、Sparkle。

## 3. 技术设计（对齐 TechStack）

- 模块结构按 TechStack §9 落地：`App` + `Packages/{GSInfra, GSDesignKit, GSGitEngine, GSIndex, GSFeatures, GSTestSupport}`，依赖方向单向，`GSGitEngine`/`GSIndex` 零 SwiftUI。
- git 引擎按 §5：系统 git CLI 为唯一执行与数据来源；actor 门面（同仓串行、跨仓并行）；60s 超时 → SIGTERM；取消 → 终止进程；仅网络类错误重试 1 次；`GIT_TERMINAL_PROMPT=0` 防挂起；管道与进程并行读取防 64KB 死锁。
- 块级暂存按 §5.3 管线：`git diff --no-color` → 自研 unified diff 解析（保留原始行逐字重组）→ `git apply --cached [--reverse] --whitespace=nowarn -`。
- 冲突按 §5.4：porcelain v2 `u` 记录、`checkout --ours/--theirs/--conflict=merge`、`merge --abort`、MERGE_HEAD 检测合并中状态。
- 并发按 §7.1：批量 = TaskGroup + AsyncSemaphore(4)；UI 层 `@Observable` + `@MainActor`（macOS 14 部署目标，采纳 TechStack §3 建议值；MRD 12 的 13 待评审修订）。
- Swift 6 语言模式（严格并发）全仓开启。

## 4. 已知偏离项（待评审，不翻 MRD 已决策）

1. **提交索引暂缓**：TechStack §6.1 的 GRDB + FTS5 未引入，时间线为内存聚合 + 时间窗截断（默认 90 天，每仓上限 800 条）。50 仓 × 10 万提交的 10.4-2 性能指标需 M0 验证后再落 SQLite 层；当前实现在 MVP 规模（≤50 仓、窗口内提交）可用。
2. **App target 形态**：TechStack §3 的 Xcode 27 App target 暂以 SPM 可执行 target 实现（`swift run GitSpaceApp`），签名/公证/DMG 的 pbxproj 链路规划 M1 打磨；AppDelegate 已处理 CLI 直启的 activation policy。
3. **GSFeatures 五子域合一 target**：TechStack §9 的 Timeline/Sync/Staging/BranchMerge/StashTag 五目录先合并为一个 target 内的五个 ViewModel（AppModel / BatchSyncModel / RepoViewModel / TimelineModel），模块边界保留在类型层面，拆 target 待代码量增长后再做。
4. **提交图 lane 布局**：TechStack §4.3 的 Canvas + 预计算 DAG lane 布局，MVP 简化为「每仓一条 lane」的纵向图列（与原型视觉一致），真实 DAG 布局随 P1 变更集视图一起做。
5. **diff 渲染**：已按 §4.3 用 AppKit NSTextView（DiffTextView），但并排视图、语法高亮、行级暂存交互未做（P1）。

以上均不触碰 MRD §17.1 已决策项；第 1、2 条建议随 M0 验证结论一并评审。
