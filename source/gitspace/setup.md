# GitSpace — setup

## 环境要求

- Xcode 27+（含 Swift 6.4 工具链）、macOS 14+（部署目标 14.0，本机验证环境 macOS 27.2 / Xcode 27.1）
- 系统 git ≥ 2.30（启动时校验；本机验证 git 2.54.0）
- 零第三方依赖，无需网络拉包

## 构建

```bash
cd repos/GitSpace
swift build          # 调试构建（含 App 可执行 target GitSpaceApp）
```

## 运行

```bash
swift run GitSpaceApp        # 或直接执行 .build/debug/GitSpaceApp
```

- SPM 可执行 target 直接运行，`AppDelegate` 会把进程提升为常规 GUI 应用（Dock/菜单栏）。
- 数据目录：`~/Library/Application Support/GitSpace/`（`workspaces/workspaces.json` 配置、`logs/ops-*.jsonl` 操作日志）。
- 首次启动为空工作区：左侧「扫描父目录」选一个含多个 Git 仓库的目录即可纳管（也可用任意临时目录 `git init` 几个仓验证）。

## 用 Xcode 开发

Xcode 直接 `Open` 本目录的 `Package.swift` 即可（SPM 工程）；选中 `GitSpaceApp` scheme 运行。正式 `.xcodeproj`（签名/公证/DMG 分发链路）规划在 M1 打磨，见 specs 偏离项。

## 打包 DMG

```bash
cd repos/GitSpace
scripts/package-dmg.sh              # 默认产出 arm64 + x86_64 两个 DMG
scripts/package-dmg.sh arm64        # 也可指定单个架构
```

- 脚本流程：release 构建（`--arch` 交叉编译）→ 组装 `GitSpace.app`（Info.plist：Bundle ID `dev.gitspace.GitSpace` 占位、LSMinimumSystemVersion 14.0）→ **ad-hoc 签名** → `hdiutil` 打 UDZO 镜像，含 `/Applications` 拖装软链。
- 产物在 `dist/GitSpace-0.1.0-<arch>.dmg`；二进制 `minos` 为 14.0（Intel 包可在 macOS 14–26 运行）。
- **分发限制**：ad-hoc 签名未公证，拷到其他机器首次打开会被 Gatekeeper 拦（需右键打开或 `xattr -dr com.apple.quarantine`）；正式分发需 Developer ID 签名 + notarytool 公证（TechStack §12，M1 落地）。
- 应用图标暂缺（M1 补 icns），当前显示系统默认图标。
