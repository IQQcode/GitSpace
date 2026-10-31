# GitSpace 仓库结构与文档导航

> 工作区视角的仓库说明：完整目录树、目录职责、文档导航。面向使用者的产品介绍见[根 README](../README.md)。

GitSpace 是面向多仓库工程的 macOS 原生 Git 客户端：多仓纳管、跨仓统一时间线、批量同步、卡片号聚合检索，以及完整的日常 Git 闭环（提交、分支、合并、冲突）。定位与范围见 [docs/prd/GitSpace-MRD-v2.0.md](./prd/GitSpace-MRD-v2.0.md)。

本仓库以 Workspace 形态组织：既是「指挥仓」（文档、规格、Skill、Hook、索引），也是未来 Swift 工程的源代码承载处，方便任何角色 + Agent 完成从需求到验证的端到端开发。

当前处于**MVP 已落地的 M1 打磨阶段**：文档与原型已产出，Swift 工程初始化于 `repos/GitSpace`（2026-10-29，构建/测试/冒烟通过）。代码模块索引见 [INDEX.md](../INDEX.md)，技术约束见 [GitSpace-TechStack-v1.0.md](./feature/GitSpace-TechStack-v1.0.md)。

## 仓库结构（完整目录树）

```text
GitSpace/                           ← Workspace 根目录
├── .agents/                        ← Agent 平台桥接（skills 为指向 ../skills 的软链）
│
├── AGENTS.md                       ← Agent 行为规范与工作规则（入口文档）
├── CLAUDE.md                       ← AGENTS.md 的软链（跨 Agent 平台互通）
├── README.md                       ← 项目门面：面向使用者的定位与导航
├── INDEX.md                        ← 资产与模块索引：各文档职责、规划模块、已知坑
│
├── repos/                          ← 本工程源代码
│   ├── README.md                   ← 落地约定（模块结构按 TechStack §9）
│   └── GitSpace/                   ← Swift 多模块工程（Package.swift + App/ + Packages/）
│
├── docs/                           ← 人维护的知识（Agent 读不出的上下文）
│   ├── INDEX.md                    ← 知识入口与路由表
│   ├── repo-structure.md           ← 本文件：仓库结构与文档导航
│   ├── prd/
│   │   └── GitSpace-MRD-v2.0.md    ← 市场需求文档（文档头 v1.5）：P0 范围、验收、里程碑
│   ├── feature/
│   │   └── GitSpace-TechStack-v1.0.md ← 技术选型（Draft 待评审）
│   ├── func/
│   │   └── GitSpace-Features-v1.0.md  ← 当前已落地的功能与交互全景
│   ├── epic/                       ← 功能缺口与规划：INDEX.md 总览 + EP01 至 EP12 + Fork/IDEA 调研
│   ├── story/                      ← 已完成 Story 的落盘记录（暂空）
│   └── research/  env/             ← 调研 / 环境配置（待沉淀时创建）
│
├── specs/                          ← 技术规格沉淀：每个 Story 一个目录
│                                   ← 约定：doc.md 设计 + summary.md 实施总结
│
├── source/                         ← 说明索引与外部参考工程
│   └── index.md                    ← 工程登记表与三件套约定
│
├── skills/                         ← 业务 Skill（.agents/skills 软链至此，暂空）
├── agents/                         ← 自定义 Subagent 定义（暂空）
├── hooks/                          ← Hook 注册表与护栏脚本（暂空）
│
├── design/
│   └── gitspace-prototype/         ← 交互原型（index-origin.html 单文件 + README）
│
└── assets/                         ← 静态素材
    └── readme/                     ← README 配图（暂空）
```

## 目录职责说明

| 目录/文件 | 职责 | 维护者 |
|-----------|------|--------|
| `AGENTS.md` / `CLAUDE.md` | Agent 行为规范与工作规则，不写业务逻辑，只描述「Agent 在 Workspace 里如何工作」 | 团队共同维护 |
| `README.md` | 项目门面：定位、当前状态、导航 | PM |
| `INDEX.md` | 资产与模块索引：文档职责、规划模块、跨模块速查、已知坑；改文档或代码前先看 | 团队共同维护 |
| `docs/` | 人维护的知识：产品、技术、设计、调研、需求拆解，均为 Agent 无法从代码中直接读出的上下文 | PM / RD / 设计 |
| `repos/` | 本工程源代码：Swift Package 多模块 + 单一 App target（模块结构按 TechStack §9，依赖方向单向） | RD |
| `specs/` | 技术规格沉淀：每个 Story 一个目录，`doc.md` 设计 + `summary.md` 实施总结 | 需求负责人 |
| `source/` | 说明索引（`index.md` 与各工程 overview / setup / test 三件套）与外部参考工程代码 | RD |
| `skills/` | 业务 Skill：可执行的 Agent 能力封装 | 有沉淀诉求的成员 |
| `agents/` | 自定义 Subagent 定义，跨模块任务时隔离上下文 | 工程负责人 |
| `hooks/` | Hook 注册表：Agent 行为的硬性护栏 | 工程负责人 |
| `design/` | 交互原型与设计稿 | 设计 |
| `assets/` | 静态素材：README 配图、界面截图 | 设计 / 产品 |

## 文档导航（给 Agent 与新成员）

- 想知道「产品要做什么」：读 `docs/INDEX.md` → `docs/prd/GitSpace-MRD-v2.0.md`
- 想知道「还缺什么、先做什么」：读 `docs/epic/INDEX.md`
- 想知道「技术怎么选、边界在哪」：读 `docs/feature/GitSpace-TechStack-v1.0.md` §2 约束锚点
- 想知道「界面怎么交互」：读 `design/gitspace-prototype/`（原型 + README）
- 想知道「某个资产/模块在哪」：读根 `INDEX.md`
- 想知道「某次需求当初怎么设计的」：读 `specs/[Story-MMDD]-*/doc.md` 与 `summary.md`
- 想知道「工程怎么登记、参考代码放哪」：读 `source/index.md`
- 想知道「Agent 在这里怎么工作」：读 `AGENTS.md`

## 快速开始

- **交互原型**：浏览器直接打开 `design/gitspace-prototype/index-origin.html`。
- **Swift 工程**（已初始化于 `repos/GitSpace`，Xcode 27 / Swift 6.4 / macOS 14+）：

  ```bash
  cd repos/GitSpace
  swift build            # 构建
  swift run GitSpaceApp  # 启动应用
  swift test             # 全量测试（含 git 等价性用例）
  ```

  构建、运行、测试的完整说明见三件套 `source/gitspace/{overview,setup,test}.md`。
