# Story-1031 批次 A 高优 P0 兑现·第一批 实施总结

| 属性 | 内容 |
| --- | --- |
| 状态 | 已实施（构建 + 47 测试全绿；可视化走查由人负责） |
| 对应设计 | [doc.md](./doc.md)（§5 简化项与 §6 待评审项均有效） |
| 分波提交 | W1 `3f74dc1` → W2 `1d14db6` → W3+W4 `b1e3f43` → W5 `a3cddd2` |
| 下批顺延 | EP02-F01 DAG 提交图、EP05-F01 多仓框架完整化、EP01-F01/F02/F03 多工作区/标签页/凭据、EP12-F04 至 F08（VoiceOver/双语/索引/统计/发布） |

## 1. 交付结果

- `swift build` 零错误；`swift test`：**47 条测试全绿**（31 既有 + 16 新增引擎等价性测试），7 个 Suite。
- 17 项 P0 Feature 落地（批次 A 的 A1 交互底座 + A2 看与改核心），范围与 doc.md §1 清单一致。
- 安全边界保持：无 force 路径（删远端 tag 走 `push --delete`）；块丢弃/取回旧版本/检出提交/删远端 tag 均二次确认；新写命令全部经 `runWrite` 留痕。

## 2. 实现清单

| 层 | 文件 | 要点 |
| --- | --- | --- |
| 引擎 | `GSGitEngine/GitRepository+History.swift`（新） | blame（porcelain 解析+连续行分组）、fileHistory（--follow）、fileChangeAt、showFileContent、diffAgainstRevision、refsContaining（for-each-ref --contains）、recentCommitSubjects、commitTemplate、conflictStageContents |
| 引擎 | `GSGitEngine/GitRepository+Write.swift` | discardHunks（apply --reverse）、stashCreate/restoreFromSnapshot、trashUntracked（trashItem 取代 removeItem）、checkoutDetached（脏区预检）、merge(message:)、createTag(at:)、pushTag(remote:)、deleteRemoteTag、restoreFile |
| 引擎 | `GSGitEngine/Models.swift` / `Parsers.swift` / `DiffParser.swift` / `WordDiff.swift`（新） | CommitInfo committer 字段、DiffLine 行号（hunk 头计数、meta 不消耗）、Blame/ContainsRefs 模型、词级差异（公共前缀/后缀裁剪，整行增删不做高亮） |
| 特性 | `GSFeatures/DiscardUndoCenter.swift`（新） | 丢弃快照（stash create）+ 撤销（哈希校验拒绝覆盖已变化文件）+ 未跟踪备份/废纸篓 + 24h 窗口 |
| 特性 | `GSFeatures/AppModel.swift` | PushPreviewItem 预检、openPushConfirmation/confirmPush、Toast 动作、commitDrafts、MainTab 上移、bulkPull/bulkPush/openRepoSheet 命令入口 |
| 特性 | `GSFeatures/RepoViewModel.swift` | 标题/正文拆分与合成、标题长度三态、信息辅助（历史/模板/草稿）、合并信息、tag 推送/删远端、checkoutDetached、历史只读透传、conflictStageContents、readFile/writeResolvedContent |
| UI | `DiffFileView.swift`（新，替代 DiffTextView） | 文件标题栏（重命名/模式变化）、统一/并排（@AppStorage 记忆）、行号、词级高亮、hunk 导航状态条；并排两列共置一个外层 NSScrollView 天然同步滚动 |
| UI | `BlameSheet.swift`（新） | 信息列（组首行显示、SHA 着色）、行右键 Blame 上一版本、后退/前进栈、点击跳时间线；FileHistorySheet 同文件：--follow 历史、与当前比较、取回此版本、Blame 此版本 |
| UI | `PushConfirmSheet.swift`（新） | 仓库/分支→上游/N 提交 + 跳过原因；永不 force；确认后走 BatchSyncModel |
| UI | `ExternalMergeTool.swift` / `ExternalTools.swift`（新） | 合并工具模板拆参（尊重引号、不进 shell）、opendiff 轮询 + 手动完成检查兜底、冲突标记计数；终端/编辑器预设探测 + CLI 定位行 |
| UI | `WorkingView.swift` | 标题/正文 + 计数三态 + 历史下拉 + 提交 ⌘↩/提交并推送 ⌥⌘↩、块丢弃 + 丢弃全部（可撤销）、文件右键（Blame/历史/编辑器/复制路径） |
| UI | `RepoSheets.swift` | MergeSheet 合并信息编辑 + 外部工具状态区 + 两者都保留编辑预览（BothKeepSheet）；StashSheet 左右分栏 + 逐文件 diff；TagSheet 推送/删远端/预填 |
| UI | `TimelineView.swift` | CommitRow ref 徽标（类型化胶囊、双击分支检出）、提交右键（复制/建分支/打 tag/检出）、PendingCheckout 确认流（脏区 stash 后检出）、DetailPanel committer/trailer/父提交跳转/包含于 |
| UI | `GitSpaceApp.swift` / `RootView.swift` / `StatusView.swift` / `SidebarView.swift` / `Components.swift` | 菜单快捷键全注册（⌘O/⌘⇧O/⌘⇧B/⌘⇧M/⌘⇧S/⌘⇧T/⌘⇧F + ⌘1–⌘5）、命令面板复用 AppModel、推送确认路由、分支一致性横幅/行标注/侧栏小结、Toast 动作按钮 |

## 3. 验证口径对照

| 验收口径 | 结果 |
| --- | --- |
| Blame 每行归属 ≡ `git blame --porcelain`（EP03 验收） | ✅ 自动化（blameMatchesPorcelainOutput） |
| 文件历史 ≡ `git log --follow`（含重命名前历史） | ✅ 自动化（fileHistoryFollowsRename） |
| 取回旧版本内容 ≡ `git show <rev>:<path>` | ✅ 自动化 |
| 「包含于」≡ `for-each-ref --contains` | ✅ 自动化（refsContainingMatchesForEachRef） |
| 块丢弃后仅选中块回退（≈ add -p 反向） | ✅ 自动化（discardHunksRevertsOnlySelectedHunks） |
| 撤销丢弃后内容 ≡ 丢弃前（EP04 验收） | ✅ 自动化（discardThenUndoRestoresContent） |
| 合并信息编辑后 `log -1 --format=%B` ≡ 输入（EP07 验收） | ✅ 自动化（mergeWithCustomMessage…） |
| Tag 推送后 `ls-remote --tags` 包含 / 删远端后消失（EP07 验收） | ✅ 自动化（pushTagAndDeleteRemoteTagRoundtrip，bare origin） |
| 未跟踪文件移废纸篓、快照对纯未跟踪改动返回空 | ✅ 自动化 |
| 推送确认数量 ≡ `rev-list --count @{u}..HEAD`（MRD 10.4-13） | ⚠️ 预检取 porcelain v2 `branch.ab`（同源数据），UI 流程待人走查 |
| 提交链路 MRD 10.4-10 / 冲突 MRD 10.4-12 / 分支 10.4-11 | ✅ 既有测试保持全绿，未回归 |
| 词级/行号/并排渲染正确性 | ⚠️ 渲染层 UI，等价性由 diff 数据（CLI 直出）保证，视觉由人走查 |

## 4. 踩坑记录（防复发）

1. **macOS 27 SDK 移除了 `NSScrollViewDelegate`**（原计划双滚动视同步）。替代方案：并排两列放入同一外层 NSScrollView，行数与行高一致 → 天然同步滚动；hunk 导航按「行索引 × 统一行高」换算 y 偏移。SwiftUI 侧替代 API 为 `onScrollGeometryChange`（本次未用）。
2. **`NSFont`/`NSColor` 的 `static let` 在 Swift 6 严格并发下不合规**（非 Sendable 全局存储）——改为计算属性。
3. **git blame 不支持 `--no-color`**（会报 ambiguous option），porcelain 输出本身无色。
4. **`git config --get commit.template` 会读全局配置**——测试需本地置空屏蔽用户 `~/.gitconfig`。
5. **快照撤销语义**：`git stash create` 捕获的是**丢弃时的工作区状态**（含改动），撤销恢复的是改动而非 HEAD——测试断言曾写反。
6. `String.commonPrefix` 在 Foundation 有，`commonSuffix` 没有——用反转求公共前缀实现。

## 5. 遗留与建议

1. **EP12 文档冲突待评审**（doc.md §6-1）：本 Story 按 INDEX §6.1 实施了菜单/右键/键盘导航；`EP12-ux-foundation.md` 需同步修订或明示维持「不做」决策。
2. **性能验收**（MRD 10.4-2：50 仓 × 10 万提交）仍依赖 EP12-F06 提交索引（GRDB，Story-1029 偏离项 1 待评审）；本批时间线仍是内存聚合。
3. **Mimosa 安全审计**：提交时 hook 提示未取得完整扫描结论，建议对本 Story 四个提交跑一次完整扫描复核。
4. **可视化走查清单**（人负责）：① DiffFileView 统一/并排切换与行号/词级高亮观感；② Blame 信息列配色与跳转；③ 推送确认面板；④ 提交栏新布局；⑤ 合并外部工具流程（需真实工具）；⑥ 分支一致性横幅（多仓场景）。
5. 下一批建议顺序：多工作区/标签页（EP01）→ DAG 提交图（EP02-F01）→ 凭据入口（EP01-F03，git credential 口径，INDEX §8-4）→ 双语/索引/统计/发布（A3）。
