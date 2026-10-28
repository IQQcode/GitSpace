# Story 1029 · MVP 版编码开发（summary）

## 1. 交付结果

`repos/GitSpace/` SPM 多模块工程（7 target + 2 测试 target，Swift 6 严格并发，零第三方依赖）：

- **构建**：`swift build` 通过（Xcode 27.1 / Swift 6.4 / macOS 27 SDK，部署目标 macOS 14）。
- **测试**：`swift test` **26/26 通过**（4 个 Suite）。
- **冒烟**：`.build/debug/GitSpaceApp` 直接启动，4 秒存活无崩溃，RSS ≈ 136MB（调试构建，MRD 空载 ≤200MB 预算内）。

## 2. 实现清单

| 层 | 文件 | 要点 |
|---|---|---|
| GSInfra | `Paths` / `OperationLog` / `AsyncSemaphore` | 日志 JSONL 按日滚动；信号量用 `withLock` 作用域锁（NSLock 直接调用在 async 上下文编译不过） |
| GSGitEngine | `GitProcessRunner` / `GitRepository(+Write)` / `Parsers` / `DiffParser` / `GitError` / `Models` | 安全闸 `validate()` 参数级拦截；`OnceBox` 防 continuation 双恢复；管道与进程并行读防死锁 |
| GSIndex | `WorkspaceStore` / `WorkspaceScanner` / `Timeline` | 扫描深度 3 + 构建产物跳过 + 仓内不下钻；每仓一 lane 聚合排序 |
| GSFeatures | `AppModel` / `TimelineModel` / `RepoViewModel` / `BatchSyncModel` | `@MainActor @Observable`；批量状态机 queued/running/succeeded/skipped/failed/cancelled |
| GitSpaceApp | `RootView` / `Sidebar` / `Timeline` / `Status` / `Working` / `Repo` / `DiffTextView`(AppKit) / `Sheets` / `Settings` / `Components` | 三栏 + 四视图 + 批量面板 + 冲突横幅 + toast + 状态栏；主题三态 |
| GSTestSupport | `GitShell` / `FixtureRepo` | 多 hunk / 冲突 / 钩子 fixture；等价性基准 = git CLI 原始输出 |

## 3. 验证口径对照（MRD 10.4）

自动化已覆盖：3（状态 ≡ porcelain/rev-list）、4（无 force/确认路径，安全闸单测）、9（批量=逐仓 CLI，本地 bare 远端 push 被拒用例）、10（hunk 暂存 ≡ 过滤 patch、amend 父不变、钩子不吞错）、11（脏区阻断切换、-D 强删路径）、12（冲突列表 ≡ u 记录、ours/theirs ≡ checkout、中止 ≡ reflog 校验）、13（非快进原样拒绝）。

未覆盖（需人/后续）：1/2 的 50 仓性能口径（等 M0 数据 + SQLite 索引）、5 的真实远端（GitHub/Gerrit 鉴权）、6 冷启动包体正式口径（当前为 SPM 调试构建）、可视化验收（人负责）。

## 4. 过程中踩的坑（防复发）

1. **`map(String.init)` 对 `Data` 切片**：解析成 Data 的 description 而非 UTF-8 内容，导致 porcelain 解析全空——必须 `String(decoding:as:)`。
2. **porcelain v2 字段数**：`u` 记录是 11 个 token（`u XY sub m1 m2 m3 mW h1 h2 h3 path`），`1` 记录 9 个；sub 字段形如 `N...` 是单 token。
3. **fixture 文件末行**：`split(omittingEmptySubsequences: false)` 会引入尾随空串，join 后多出空行改变 hunk 结构。
4. **NSLock 在 async 上下文不可直接 lock/unlock**，用 `withLock`。
5. **`@MainActor` 类的 `Identifiable` conformance**：`id` 计算属性需 `nonisolated`，否则严格并发报 conformance 隔离错误。
6. **GitShell 造仓时 `switch -c` 会直接切换**，分支测试断言要按此语义写。

## 5. 遗留与建议

- 偏离项 5 条见 `doc.md` §4，其中 GRDB 索引与正式 App target 建议进 M0/M1 评审。
- 批量同步的 MainActor 状态机在 UI 压测（50 仓）下可能需要把聚合刷新移出主线程（M1 观察点）。
- 时间线大数据量（>1 万条）下 `List` 行视图未做 diff 优化（EquatableView），滚动帧率需实测。
