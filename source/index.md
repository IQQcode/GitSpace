# source 说明索引

GitSpace Workspace 的工程登记入口。`source/` 只放说明，代码本体在 `repos/`（本工程源代码）与本目录下的参考工程中。

## 本工程源代码（repos/）

| 工程 | 定位 | 技术栈 | 状态 |
|------|------|--------|------|
| `repos/GitSpace` | macOS 原生 Git 多仓客户端：多仓纳管、跨仓时间线、批量同步、提交、分支、合并与冲突 | Swift 6.4（严格并发）+ SwiftUI/AppKit 混编 + 系统 git CLI；SPM 多模块，零第三方依赖 | **MVP 已落地**（2026-10-29）：构建/26 测试/冒烟通过；三件套见 [gitspace/](./gitspace/) |

三件套：

- [gitspace/overview.md](./gitspace/overview.md) — 对外能力与模块地图
- [gitspace/setup.md](./gitspace/setup.md) — 构建 / 运行 / Xcode 开发
- [gitspace/test.md](./gitspace/test.md) — 测试结构与等价性口径

## 参考与原型工程

三件套说明与代码同放一处，便于就近查阅。

| 工程 | 定位 | 说明位置 | 状态 |
|------|------|---------|------|
| （暂无） | — | — | Fork / IDEA 为闭源商业软件，不落代码，调研结论在 MRD 第 6、7 章；后续引入开源参考工程（如 gitoxide）时，代码放 `source/<repo>/` 并补三件套 |

## 三件套约定

- **overview.md**：这个仓库是什么、对外提供什么能力、对内依赖什么模块。
- **setup.md**：如何 Build、如何启动 / Debug。
- **test.md**：如何测试、如何写测试用例。

> 新增本工程模块时：在 `repos/` 落代码，在本目录登记并补三件套。引入外部参考工程时：代码放 `source/<repo>/`，三件套与代码同放；上游 git 仓库的说明文件写入其 `.git/info/exclude`，不污染上游工作区。
