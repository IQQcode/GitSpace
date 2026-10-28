# AGENTS.md

本文描述 Agent 在 GitSpace Workspace 中的工作规则。**不讲业务逻辑，不介绍产品是做什么的**，业务上下文请走 `docs/INDEX.md` 知识入口。

## 1. 工作入口

接需求后，先建立上下文，再动手：

1. 读 `docs/INDEX.md`，定位本次需求涉及的产品、技术、设计、调研文档。
2. 要改文档或代码时，先读根目录 `INDEX.md`（资产与模块索引：各文件职责、规划模块、已知坑）。
3. 涉及需求范围取舍时，先查 MRD 第 17 章：**17.1 已决策项不得擅自翻案**，17.2 待定项可在产出方案时给出建议但须标注「待评审」。
4. 涉及技术实现约束时，读 `docs/feature/GitSpace-TechStack-v1.0.md` 第 2 章「约束锚点」——性能、行为一致性、安全边界都是硬约束。
5. 涉及结构问题（某个目录放什么、新文件落哪）时，读 `docs/repo-structure.md`。
6. 不确定 Agent 行为约束时，以本文件为准；本文件与 `CLAUDE.md`（软链）互通。

## 2. 目录速览

```text
docs/      人维护的知识（产品/技术/设计/调研/story），Agent 无法从代码读出的上下文；入口 docs/INDEX.md
INDEX.md   资产与模块索引：动文档或代码前的第一站
specs/     技术规格沉淀：一个 Story 一个目录（doc.md 设计 + summary.md 实施总结）
skills/    业务 Skill，可被当前 workspace 识别（.agents/skills 为其软链）
agents/    自定义 Subagent 定义
hooks/     Hook 注册表，Agent 行为的硬性护栏
repos/     本工程源代码：Swift 多模块工程落地处（未初始化，约定见 TechStack §9）
source/    说明索引（index.md 与各工程 overview / setup / test 三件套）与外部参考工程
design/    交互原型与设计稿（gitspace-prototype）
assets/    静态素材（README 配图等）
```

## 3. 工作流程

- **需求进来**：先澄清目标、范围与验收标准，识别「未知的未知」；涉及 P0 范围的改动必须回写 MRD 并记入其变更记录。
- **拆卡**：复杂需求拆成可独立验证的 Story / Task，落 `specs/[Story-MMDD]-<slug>/`；一次会话装不下时善用 handoff 交接。
- **实现**：代码落 `repos/`，模块边界按 TechStack §9（`App` + `Packages/GS*`），依赖方向单向：`App → Features → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra`；`GSGitEngine` 与 `GSIndex` 不得 import SwiftUI。初始化工程时在 `source/index.md` 登记并补三件套。
- **验证**：验收口径是与 git 基准的等价性（MRD 10.4 十三条），先完成非可视化验证（构建、单测、等价性比对），人负责最终可视化确认。
- **收尾**：产出沉淀到 `docs/story/`，运行过程中发现的新知识写入对应 docs 或 skill。

## 4. Subagent 使用规范

- 探索陌生文档或代码：用 Explore 类 Subagent（fast / medium / thorough），不要在主会话里大量盲搜。
- 跨模块排查：用 General 类 Subagent 执行多步任务，主 Agent 只做编排与裁决。
- 验证类工作：用验证类 Subagent 做编程式断言（尤其 git 等价性比对），不要相信「看起来完成了」。
- 只有需要长期复用的自定义角色，才在 `agents/` 定义；默认 Subagent 已覆盖大部分场景，避免过度沉淀。

## 5. 编写规则

- **文档**：只整理「非显而易见」的内容（决策原因、验收口径、常见错误、命名规范）；能从代码读出的 API 文档、编码规范不重复整理。
- **代码**：遵循 TechStack 既定选型（Swift 6 严格并发）；Git 相关数据一律来自 CLI 输出，不自算；破坏性操作必须走引擎层硬闸与二次确认。
- **Commit**：描述部分用中文，保留 `feat:` / `fix:` 等英文标签与卡片号。
- **索引同步**：新增、移动、重命名文档或代码模块时，**必须同步更新 `INDEX.md`**；行数会漂移，职责说明以代码为准。
- **Docs 与 Skills 的分工**：可执行的流程优先沉淀为 Skill；Docs 集中整理 product、design、env 等信息，其余交给 Agent 自我产生和销毁。
- **命名**：术语与命名以 MRD 17.4 为准，全篇统一，不另起炉灶。
