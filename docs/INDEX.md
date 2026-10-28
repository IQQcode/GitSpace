# docs 知识索引

GitSpace Workspace 的知识入口。Agent 接需求后从这里路由到对应文档；人类成员沉淀知识时也按此结构落位。

## 文档地图

| 类别 | 入口 | 详细文档 | 维护者 |
|------|------|---------|--------|
| 产品需求 | `prd/` | [MRD（文件 v2.0，文档头 v1.5）](./prd/GitSpace-MRD-v2.0.md)：定位、P0 范围、验收、里程碑 | PM |
| 技术方案 | `feature/` | [技术选型 v1.0](./feature/GitSpace-TechStack-v1.0.md)（Draft 待评审）；P0 PRD 待产出，以 MRD §10 P0 为范围基线 | PM / RD |
| 交互设计 | `../design/` | [gitspace-prototype](../design/gitspace-prototype/)（原型 `index-origin.html` + 说明）；设计规范待沉淀 | 设计 |
| 调研内容 | （暂无独立文档） | Fork / IDEA / 竞品分析目前都在 MRD 第 6、7、8 章；独立调研沉淀时建 `research/` | 调研人 |
| 需求实现拆解 | `story/` | [story/](./story/) 目录（暂空，首个 Story 开始拆卡后落位） | Agent / RD |
| 环境配置与联调 | （待建 `env/`） | Swift 工程初始化后落 `env/dev.md` | RD |
| 仓库结构与导航 | [repo-structure.md](./repo-structure.md) | 完整目录树、目录职责、文档导航 | 团队共同维护 |

## 给 Agent 的导航

- 想知道「产品要做什么、做到什么程度」：`prd/GitSpace-MRD-v2.0.md`（范围决策看 §17）
- 想知道「技术怎么选、模块怎么分」：`feature/GitSpace-TechStack-v1.0.md`（硬约束看 §2）
- 想知道「界面长什么样、怎么交互」：`../design/gitspace-prototype/index-origin.html` + TechStack §4.3 映射表
- 想知道「竞品为什么这么定」：MRD 第 6、7、8 章（IDEA 基底 / Fork 交互 / 竞品分析）
- 想知道「某次需求怎么拆的」：`story/`
- 想知道「某个目录放什么、新文件落哪」：`repo-structure.md`
- 想知道「资产与模块在哪」：根 `INDEX.md`
- 想知道「Agent 在这里怎么工作」：根 `AGENTS.md`

## 沉淀约定

- **人维护**：Agent 无法从代码读出的上下文（决策原因、验收口径、设计原则、常见错误）。
- **Agent 维护**：执行过程的产物且对后续任务有参考意义的（如每个 Story 的开发记录），落到 `story/`；技术设计细节与实施总结落 `specs/`（根目录约定）。
- **不重复整理**：能从代码读出的 API 文档、编码规范不写进 docs。
- **决策一致性**：改 P0 范围必须回写 MRD 并记入其变更记录；已决策项（MRD §17.1）不得擅自翻案。
