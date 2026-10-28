# GitSpace

> 一句话定位：IDEA 的多仓合并内核 × Fork 的轻量交互手感 × 开源免费可商用 × 轻量独立（macOS 首发）。

面向组件化、微服务、多仓库（multi-repo）工程的 macOS 原生 Git 可视化客户端。把分散在多个独立 Git 仓库里的提交、分支、改动汇聚进一个统一窗口，让开发者像看单个仓库一样掌控整个工程全局。

## 它解决什么

- **多仓一个窗口**：多仓纳管、跨仓统一时间线、多仓状态体检、按卡片号跨仓聚合检索、批量同步（fetch / pull / push）。
- **日常闭环不切窗**：提交（文件 + 块级暂存）、分支、合并、冲突处理、stash、tag——P0 的判定线是「日常上班不出这个窗口」。
- **行为以 git 为准**：引擎即系统 git CLI，块级暂存 ≡ `git add -p`、冲突列表 ≡ `git status --porcelain`，git 替产品背书行为正确性。

免费阵营（SourceTree / GitHub Desktop）停留在单仓；手感最好的 Fork 收费且多仓是「切换」而非「合并」；多仓合并能力藏在重型 IDE 里。GitSpace 把「多仓合并」这件只有 IDE 能做好的事，做成人人可免费商用的独立轻量工具。

## 当前状态

需求与方案阶段，代码未开工：

- MRD 已到「范围冻结，待技术评审」（见 [docs/prd/GitSpace-MRD-v2.0.md](docs/prd/GitSpace-MRD-v2.0.md)）。
- 技术选型 v1.0 已产出（Draft）：Swift 6.4 / Xcode 27，SwiftUI 主导 + AppKit 关键路径，系统 git CLI 唯一引擎，SQLite（GRDB + FTS5）提交索引，Apache 2.0 兼容依赖（见 [docs/feature/GitSpace-TechStack-v1.0.md](docs/feature/GitSpace-TechStack-v1.0.md)）。
- 交互原型已验证核心流程（统一时间线、批量操作、聚合检索、仓库纳管，见 [design/gitspace-prototype/](design/gitspace-prototype/)）。

## 导航

| 想看什么 | 去哪 |
|---|---|
| 需求、范围、验收标准 | [docs/prd/GitSpace-MRD-v2.0.md](docs/prd/GitSpace-MRD-v2.0.md) |
| 技术选型与架构 | [docs/feature/GitSpace-TechStack-v1.0.md](docs/feature/GitSpace-TechStack-v1.0.md) |
| 交互原型 | [design/gitspace-prototype/](design/gitspace-prototype/) |
| 知识路由表 | [docs/INDEX.md](docs/INDEX.md) |
| 工作区结构与目录树 | [docs/repo-structure.md](docs/repo-structure.md) |
| Agent 工作规则 | [AGENTS.md](AGENTS.md) |
| 代码 / 资产索引 | [INDEX.md](INDEX.md) |

## 工作区约定

本仓库按 Agent WorkSpace 规范组织：`AGENTS.md` 描述 Agent 工作规则，`docs/` 放人维护的知识，`specs/` 沉淀 Story 技术规格，`source/` 登记工程与参考项目，完整目录树与职责见 [docs/repo-structure.md](docs/repo-structure.md)。
