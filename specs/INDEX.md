# specs 技术规格索引

一个 Story 一个目录（`[Story-MMDD]-<slug>/`），沉淀该次研发的设计（doc.md）、任务拆解（tasks.md）与实施总结（summary.md）。**动相关模块代码前，先读对应 Story 的 doc.md**。

## Story 一览

| Story | 状态 | 内容 | 文件 |
|---|---|---|---|
| `Story-1029-mvp-plan/` | 已确认（回溯归档） | MVP 方案事实源：设计 + W1 至 W14 执行契约（含复核证据） | doc.md, tasks.md |
| `Story-1029-mvp-coding/` | 已实施 | MVP 编码实施记录与 5 条待评审偏离项 | doc.md, summary.md |
| `Story-1030-app-ui-alignment/` | 已实施（构建 + 单测通过） | App 界面对齐原型：顶部栏 / 五视图 tab / 命令面板 / 弹窗 / 变更集 / 聚合检索 | doc.md, summary.md |
| `Story-1031-p0-batch1/` | 已实施（构建 + 47 测试全绿） | 批次 A 第一批：交互底座（菜单/右键/键盘）+ 看与改核心（并排 diff/Blame/文件历史/丢弃撤销/推送确认/合并收尾/外部合并工具/tag 推送等 17 项 P0） | doc.md, summary.md |

## 约定

- 目录命名 `Story-MMDD-<slug>`，slug 用短横或驼峰英文
- `doc.md`：设计（背景、架构、数据流、接口、测试策略、明确不做、待评审）
- `tasks.md`：任务拆解与执行契约
- `summary.md`：实施总结（交付清单、验证结果、偏差、待评审）
- 验证口径：非可视化优先（构建 / 单测 / 与 git 基准等价性），可视化由人最终确认
- 相关入口：功能全景见 `docs/func/GitSpace-Features-v1.0.md`；资产与模块见根 `INDEX.md`；知识路由见 `docs/INDEX.md`
