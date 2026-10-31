# Story-1031-mcp 实施总结（summary.md）

> Story：GitSpace MCP 支持 + git-space skill 内置分发。
> 规格事实源：[doc.md](./doc.md)（§3 方案 / §5 验收 / §8 决策记录）；执行契约：[tasks.md](./tasks.md)。
> 实施时间：2026-10-31，提交 W1 `d890f13` → W5 `本提交`。

## 1. 交付清单

| 工作项 | 交付 | 提交 |
|---|---|---|
| W1 引擎 | `GitRepository+VCS.swift`：bisect（start/mark/reset/log）、cherry-pick、revert、abortPick；全部 `runWrite` 留痕，无 `-f`/`--force` | d890f13 |
| W2 MCP 模块 | `Packages/GSMCP/`：JSON-RPC 2.0 + stdio server（59 工具，零第三方依赖）、ToolRegistry（public，含 names）、GitToolExecutor（读 22 + 写 36 + list_repos）、MCPAppConfig（fail-closed 语义）、MCPSkillInstaller | 9907f22 |
| W3 App 接入 | `MainEntry`（`GitSpaceApp mcp-serve` 子命令分发，GUI 不受影响）、设置页「MCP 与 Agent」Section、skill 自动安装/更新（stderr 留痕） | 4f36e67 |
| W4 skill | `skills/git-space/`（SKILL.md + workflows + safety）→ `sync-skill.sh` 镜像进 Bundle 源 → skill-unify 落位 `~/.agents/skills/git-space`（12 平台链接） | 464c0e4 |
| W5 收尾 | 文档回写（INDEX / specs / func / epic / overview）、DMG 双冒烟、独立审查 + 修复 | 本提交 |

## 2. 验证结果（全部为新鲜运行证据）

- [x] `swift build` debug + release 通过。
- [x] `swift test` 全绿 **77 用例**（GSGitEngineTests 53 / GSMCPTests 19 / GSIndexTests 5）；新增覆盖：bisect 定位+reset 还原、脏区拒、cherry-pick CLI 等价、冲突+abortPick 还原、revert 反向提交、留痕 action 全覆盖（revert/cherry-pick/bisect.*）、协议协商/回退/-32601/-32700、工具面全量比对（防漂移）、硬闸结构断言（无任意命令透传/无 force 入参）、confirm 拒、写开关拒、config 损坏 fail-closed、安装器四场景。
- [x] `mcp-serve` 冒烟：stdio 往返 initialize（协商 2025-06-18 / 2024-11-05）、tools/list 59 工具、无 GUI 启动、stdout 纯协议输出。
- [x] DMG 打包 + 双冒烟：`GitSpace_GSMCP.bundle` 已随包进 `Contents/Resources/`；二进制 `mcp-serve` 协议往返通过；GUI 启动存活（修复 P0 前会触发 `Bundle.module` fatalError）。
- [x] skill-unify：SSOT 落盘 + 12 平台链接；doctor 0 错误；`sync-skill.sh --check` 一致。
- [ ] 真实 MCP 客户端（ZCode/Claude Code）连接冒烟：**未做**（本环境无可用客户端会话），协议层已按 stdio 规范实现并有协议测试背书；建议首次使用时验证。

## 3. 独立审查与修复

独立 reviewer（fresh eyes）复核结论：规格符合性 W1–W4 主体 pass，发现 **P0×1 / P1×2 / P2×11**，其中必修三项已全部修复：

| 级别 | 发现 | 处置 |
|---|---|---|
| P0 | SPM resources 产出独立 `GitSpace_GSMCP.bundle`（非编译进二进制），打包脚本未拷贝 → 打包 .app GUI 启动 fatal error | `package-dmg.sh` 补拷 bundle + `bundleSkillDirectory` 手动定位（不再触碰 `Bundle.module` 访问器）+ DMG 复测通过 |
| P1 | SkillInstallTests / specs 目录未提交 | 测试已随 W5(1) 补交；specs 随本提交入库 |
| P1 | GUI 启动 skill 安装失败完全静默 | MainEntry 改为 stderr 记录（成功/失败/资源缺失三分支） |
| P2（已修 9 项） | 空冲突伪装清单、abortPick 硬编码 .git、repoCache 路径未归一化、config 损坏 fail-open、死代码 targetNotWritable、skillVersion 越界解析、工具面无防漂移比对、硬闸无结构断言、留痕断言不全 | 见 §2 新增测试与代码修正 |
| P2（记录遗留） | bisectStart 竞态窗口（actor 内 await + 跨进程无互斥，git 自身兜底）；StdinLineStream 单次迭代约束（已加注释）；「脚本比对」未沉淀为独立脚本（全量比对测试已覆盖） | 风险低，记入遗留建议 |

## 4. 偏离项与口径订正

1. **截断单位**：doc §3.2 原写「512KB 字节」，实现为 512,000 字符（Character 边界、UTF-8 安全）——doc 已按实现订正，语义上对 CJK 更宽松。
2. **工具数 59**（非 doc §3.3 初稿的 58）：实现含 `git_abort_pick`（超出设计稿的合理补齐，中止 cherry-pick/revert 工作流需要），doc 已回写。
3. **打包口径**：doc §3.1 原写「打包零改动/编译进二进制」，实际 SPM 资源是独立 bundle 需脚本补拷——doc 已订正。
4. **skill 名更名 `git-spece` → `git-space`**（2026-10-31 用户确认笔误）：改动面 = workspace 目录 git mv、frontmatter name、代码安装目标路径（MCPSkillInstaller）、设置页文案、skill 自述标题、全部文档引用、SSOT 重装；spec 历史稿中的旧名一并订正为现名。
5. **EP09-F07 编号未正式入 epic Feature 表**：以 epic INDEX §7.9 回写建议行替代登记（避免与 109 Feature 计数产生未评审漂移），评审时正式编号入库。

## 5. 待评审决策（对齐 doc §8）

- **WP-1 MCP 写操作口径**：默认读写 + 12 个破坏性工具 confirm + 设置页总开关（config 损坏 fail-closed）——与 epic「AI 默认关闭」基调的差异（本地 stdio 无数据外发 vs 云端外发）需评审拍板；若翻案为默认只读，改动面仅为 config 默认值与首启文案。
- D1 skill 名、D5 SSOT 位置见 doc §8。

## 6. 遗留建议

1. 真实 MCP 客户端连接冒烟（首个使用者做即可）。
2. `bisectStart` 跨进程互斥（GUI 与 server 并发 bisect 同仓时 git 自身会拒绝，体验可后补引导）。
3. skill-unify 平台私有目录的同步目前由用户手动 `sync`；如需 App 侧一键全平台同步，需新决策（涉及往平台私有目录写文件）。
4. 长输出截断阈值与格式（是否分页/分块）可在实际使用反馈后调优。
5. 二进制名与打包脚本耦合（`GitSpace` vs `GitSpaceApp`）建议在 M1 正式签名/命名决策时统一。

## 7. 运行过程踩坑记录

1. **SPM `.copy` 资源 ≠ 编译进二进制**：会产出 `GitSpace_GSMCP.bundle`；分发场景必须随包拷贝，且不要直接触碰 `Bundle.module` 访问器（缺失即 fatalError），手动定位 bundle 是唯一稳妥路径。
2. **`.app` 内二进制名 = `GitSpace`**（打包脚本 APP_NAME），与 SPM target 名 `GitSpaceApp` 不同——skill 配置示例、设置页复制路径都按 `Bundle.main.executableURL` 动态生成才可靠。
3. **临时目录符号链接**：`/var` vs `/private/var` 会让 path 前缀比较、copy 相对路径计算全部错位，统一 `resolvingSymlinksInPath()`。
4. **cwd 会话内漂移**：跨 Bash 调用的相对路径不可靠，长流程一律绝对路径。
5. **`git cherry-pick -n` 干净成功不留 CHERRY_PICK_HEAD**：无 abort 可言，勿在测试/文档里假设「-n 后可 abort」。
