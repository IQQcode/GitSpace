# 资产与模块索引

快速定位各资产与模块。**动文档或代码前先看本索引**；结构与职责的完整说明见 `docs/repo-structure.md`。

最后更新：2026-10-29。MVP 已落地：Swift 工程初始化于 `repos/GitSpace`（构建 / 26 测试 / 冒烟通过），进入 M1 打磨阶段。

## 一、文档资产

| 资产 | 版本 / 状态 | 职责 | 关键点 |
|---|---|---|---|
| `docs/prd/GitSpace-MRD-v2.0.md` | 文档头 v1.5 · Draft（范围冻结，待技术评审） | 市场需求文档：定位、P0 范围、13 条验收标准、里程碑 M0–M4 | 608 行；范围决策看 §17.1（已决策，不得擅自翻案）与 §17.2（待定 9 项）；验收标准 §10.4 是一切实现的比对基准 |
| `docs/feature/GitSpace-TechStack-v1.0.md` | v1.0 · Draft（供技术评审） | 技术选型：语言/工具链、UI 分层、git 引擎、存储、并发、依赖许可、构建、测试 | 337 行；硬约束锚点在 §2；工程模块结构在 §9；M0 技术验证清单在 §15，结论回填后转 Ready |
| `design/gitspace-prototype/index-origin.html` | 已验证 | 交互原型：统一跨仓时间线、批量操作、变更集聚合、聚合检索、仓库纳管、主题切换 | 单文件 HTML+CSS+原生 JS，浏览器直接打开；数据为演示示例，不访问真实仓库 |
| `specs/Story-1029-mvp-plan/` | 已确认（回溯归档） | MVP 方案事实源（spec-flow 格式）：doc.md 设计 + tasks.md 执行契约（W1–W14 全部 ✅ 含复核证据） | 14 个工作项全部完成；MRD 10.4 的 3/4/9/10/11/12/13 条已自动化 |
| `specs/Story-1029-mvp-coding/` | 已实施 | MVP 编码实施记录：范围、偏离项、验证口径、踩坑记录 | **偏离项 5 条待评审**（doc.md §4）：GRDB 索引暂缓、SPM 可执行 target、GSFeatures 合一 target、每仓一 lane、diff 渲染简化 |

## 二、代码模块（repos/GitSpace，SPM 多模块）

依赖方向单向：`GitSpaceApp → GSFeatures → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra`；`GSGitEngine` 与 `GSIndex` 不 import SwiftUI。三件套见 `source/gitspace/`。

| 模块 | 职责 | 状态 |
|---|---|---|
| `App/Sources/GitSpaceApp/` | 主 target：@main、三栏骨架、四视图（时间线/多仓状态/改动提交/分支合并）、弹窗与设置 | ✅ MVP |
| `Packages/GSDesignKit/` | 设计令牌（取色基准=原型深浅主题）、色板、mono 字体、图列常量 | ✅ MVP |
| `Packages/GSGitEngine/` | git CLI 进程执行器（60s 超时/取消/网络重试/安全闸）、porcelain v2·log·for-each-ref·unified diff 解析、单仓 actor 门面、hunk 暂存管线 | ✅ MVP |
| `Packages/GSIndex/` | 父目录扫描器、工作区配置 JSON 存储、跨仓时间线聚合 | ✅ MVP（SQLite/FTS5 索引层按偏离项暂缓） |
| `Packages/GSFeatures/` | AppModel（纳管/状态/批量）、TimelineModel、RepoViewModel（改动/分支/合并/stash/tag）、BatchSyncModel | ✅ MVP（五子域合一 target，见偏离项） |
| `Packages/GSInfra/` | 应用路径约定、JSONL 操作日志、AsyncSemaphore | ✅ MVP |
| `Packages/GSTestSupport/` | GitShell（CLI 基准）+ FixtureRepo（多 hunk/冲突/钩子 fixture 生成器） | ✅ MVP |

## 三、跨模块速查

| 要找 / 要改什么 | 去哪 |
|---|---|
| 产品定位、P0 范围、验收标准 | MRD §9 / §10 / §10.4 |
| 技术约束、模块边界、依赖许可 | TechStack §2 / §9 / §11 |
| 某个界面怎么交互 | `design/gitspace-prototype/index-origin.html` + TechStack §4.3 界面映射表 |
| 代码怎么构建 / 跑 / 测 | `source/gitspace/setup.md` / `test.md` |
| MVP 方案与任务拆解 | `specs/Story-1029-mvp-plan/doc.md` + `tasks.md` |
| MVP 实施记录与偏离项 | `specs/Story-1029-mvp-coding/doc.md` + `summary.md` |
| 新文件 / 新目录落哪 | `docs/repo-structure.md` 目录职责表 |
| 新 Story 的规格 | `specs/[Story-MMDD]-<slug>/`（doc.md + summary.md） |
| 术语与命名 | MRD §17.4（全篇唯一口径） |

## 四、已知坑

1. **原型文件名**：MRD 与 TechStack 均引用 `design/gitspace-prototype/index.html`，实际文件为 `index-origin.html`——修正引用或恢复文件名前，以 `index-origin.html` 为准。
2. **MRD 版本号不一致**：文件名为 `GitSpace-MRD-v2.0.md`，文档头与变更记录标注 v1.5（v1.0→v1.5 均在 §16）。引用时写清「MRD（文件 v2.0）」，版本统一动作待与 PM 确认。
3. **最低系统版本待评审**：TechStack §3 建议 macOS 13 修订为 14（`@Observable` 收益），MRD 12 仍写 13——**代码已按 14.0 部署目标落地**，评审拍板后修订 MRD。
4. **技术栈整体 Draft**：M0 验证清单（TechStack §15）结论回填前，§5 git 引擎等核心决策均标注「待确认」；MVP 实现已按 §5 的系统 git CLI 路线先行落地，等价性由 26 条测试背书。
5. **`git status --porcelain=v2` 字段数**：`u` 记录 11 个 token、`1` 记录 9 个、`2` 记录 10 个 + NUL 分隔的 origPath；`Data` 切片转字符串必须 `String(decoding:as:)`（详见 specs summary §4）。
