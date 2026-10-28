# repos/ — 本工程源代码

Swift 多模块工程落地处，尚未初始化。

- 模块结构按 [docs/feature/GitSpace-TechStack-v1.0.md](../docs/feature/GitSpace-TechStack-v1.0.md) §9：`App`（主 target）+ `Packages/` 下的 `GSDesignKit` / `GSGitEngine` / `GSIndex` / `GSFeatures` / `GSInfra` / `GSTestSupport`。
- 依赖方向单向：`App → Features → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra`；`GSGitEngine` 与 `GSIndex` 不 import SwiftUI。
- 初始化工程后：在 [source/index.md](../source/index.md) 登记并补 overview / setup / test 三件套，同步更新根 [INDEX.md](../INDEX.md)。
