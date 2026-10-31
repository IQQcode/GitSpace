# Story-1030 App 界面与交互对齐原型 · 实施总结

状态：已实施，构建与单测通过。对应设计见同目录 `doc.md`。

## 1. 目标回顾

让 macOS App（`repos/GitSpace`）的顶部栏、侧边栏、主区头部对齐交互原型 `design/gitspace-prototype/index.html`，补齐缺失模块与视觉，并新增命令面板（⌘K）。原型 HTML 不改，只改 Swift 代码。

## 2. 交付清单

新增：
- `Packages/GSIndex/Sources/GSIndex/CardAggregator.swift`：卡片号正则提取 + 跨仓分组
- `Tests/GSIndexTests/CardAggregatorTests.swift`：2 个单测
- `App/Sources/GitSpaceApp/TitleBar.swift`：顶部标题栏
- `App/Sources/GitSpaceApp/CommandPalette.swift`：命令面板（PaletteCommand + CommandPaletteView）
- `App/Sources/GitSpaceApp/ChangesetView.swift`：变更集视图
- `App/Sources/GitSpaceApp/SearchView.swift`：聚合检索视图
- `App/Sources/GitSpaceApp/RepoSheets.swift`：BranchSheet / MergeSheet / StashSheet / TagSheet / ImportManifestSheet

修改：
- `Packages/GSFeatures/.../AppModel.swift`：命令面板状态、`AppSheet` 弹窗路由、`selectedRepos`、`anyMergeInProgress` / `mergingRepoID`
- `App/.../RootView.swift`：外层 TitleBar、主区 5 tab 重构、tab 数字徽标、`.sheet(item:)` 统一弹窗、命令面板 overlay、跨仓合并横幅、runBatch 改走 activeSheet
- `App/.../SidebarView.swift`：工作区卡片补 副标题/新鲜度/进度条，底部补 导入 mgit/Stash/Tag，入口走 activeSheet
- `App/.../TimelineView.swift`：`CommitRow` 提权为共享组件
- `App/.../GitSpaceApp.swift`：`.commands` 注册 ⌘K 与 ⌘⇧L

删除：
- `App/.../RepoView.swift`：随「分支·合并」独立 tab 退场，功能迁入弹窗

文档回写：`INDEX.md`、`docs/feature/GitSpace-TechStack-v1.0.md` §4.3 与变更记录 v1.1

## 3. 验证结果（非可视化）

- `swift build`：Build complete（4.55s），整个工程编译通过
- `swift test`：
  - GSIndexTests 5 tests in 4 suites 通过（含新增 CardAggregator 2 个：卡片号多形态提取、跨仓分组与涉及仓计数）
  - GSGitEngineTests 26 tests in 4 suites 通过（Status & Log / Branch & Merge / Commit & Safety / Hunk Staging）
- MRD §10.4-11/12/13 等价性测试（分支切换引导 stash、冲突列表一致、ours/theirs 一致、中止合并恢复、永不 force push）位于 Branch & Merge / Commit & Safety 套件，本次未改其代码路径，仍全绿
- 可视化效果需人工打开 App 最终确认（三栏布局、顶栏、命令面板、弹窗样式）

## 4. 与设计（doc.md）的偏差与简化

- ChangesetModel 未单独建类：内联为 `ChangesetView` 的 `@State groups` + `.task(id: commits.count)` 缓存重算，等价满足"仅 commits 变化时重算"的性能意图
- StatusView 选中集未上移接入：`AppModel.selectedRepos` 字段已加并由命令面板批量 Pull/Push 写入，但 StatusView 仍用自身 `@State`；命令面板批量直接 `runBatch(targets)` 不依赖其选中集，功能正常，视觉联动留待后续
- 全局快捷键只注册 ⌘K（命令面板）与 ⌘⇧L（主题）于 `.commands`；其余（Fetch / 分支 / 合并 / Stash / Tag / 添加 / 扫描）经命令面板点击执行，命令项仅展示快捷键文本，避免 `.commands` 与视图深层动作的桥接复杂度
- RepoSheets 为新建文件（doc 原说追加到 Sheets.swift），实质等价
- 变更集缺口提示降级为「涉及 N 仓」，不做绝对缺口基准
- 聚合检索 MVP 为统一关键字匹配，分字段精确检索列入待评审

## 5. 待评审项（沿用 doc §11）

- 变更集（P1/P2）、聚合检索（P1）提为 P0 界面一级 tab：是否保留一级入口
- 命令面板：MRD 未定义，本次新立口径，命令清单是否以图五为准
- 移除「分支·合并」独立 tab 改弹窗访问：确认产品认可该界面信息架构调整

## 6. 后续建议

- 人工可视化走查三块区域与命令面板，确认与原型一致
- 评审通过后，将 StatusView 选中集正式接入 `AppModel.selectedRepos`，并视需要把更多快捷键纳入 `.commands`
