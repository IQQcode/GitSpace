# EP10 高级仓库能力：Worktree、Submodule、LFS、git-flow、签名

> 目标：支持组件化工程里常见的高级仓库形态与团队规范，先能正确识别与展示，再逐步提供管理操作。

| 项 | 说明 |
|---|---|
| 优先级分布 | P2 3 项；P2 待评审 3 项 |
| 人周（粗估） | 批次 C 8.5 |
| 依赖 | EP01-F02 标签页（worktree / submodule 在新标签打开）；EP06-F01 侧栏分支树；EP04-F08 提交选项 |
| 关联 | MRD 10.1「worktree / submodule：只读展示 → 管理，P2」、10.5「submodule 递归操作 P2」「LFS 大文件托管不做」、10.6 流程一「separate-git-dir 与 submodule 判定规则待定」 |

## 1. 现状

- 扫描器把 `.git` 目录或文件都当作仓库，进入仓库后不再下钻，submodule 由纳管清单决定（`WorkspaceScanner`）；worktree 与 submodule 没有专门标识。
- 没有 LFS、git-flow、签名相关的读取或展示。

## 2. 对标参考

- Fork：侧栏显示 worktree（2.31），创建与删除（2.41），把远端分支检出为 worktree（2.68），删分支时可一并删 worktree（2.63）；submodule 显示与更新，推送时提醒未推送的 submodule（2.35），检出时默认更新 submodule（2.19）；LFS 锁定 / 解锁、状态对话框、图片预览（1.0.76、2.14、2.37），大文件未纳入 LFS 时警告（2.0）；git-flow；GPG。
- IDEA：Worktrees 菜单；Update Project 会更新处于分支上的 submodule，detached 的 submodule 执行 `git submodule update`；GPG 签名设置。

## 3. Feature 清单

| ID | Feature | 优先级 | 批次 | 人周 | 依据 |
|---|---|---|---|---|---|
| EP10-F01 | Worktree 只读展示：识别 linked worktree，侧栏标出所属主仓与检出的分支 | P2 | C | 0.5 | MRD 10.1 |
| EP10-F02 | Worktree 管理：新建（含把远端分支检出为 worktree）、移除（有未提交改动时阻止）、在新标签打开 | P2 | C | 1.5 | MRD 10.1、Fork 2.41 / 2.68 |
| EP10-F03 | Submodule：显示状态（未初始化、提交偏移、有改动），init / update（默认非递归）、作为仓库打开、推送前提醒未推送的 submodule | P2 | C | 2 | MRD 10.1、10.5 |
| EP10-F04 | Git LFS：识别 LFS 跟踪文件，diff 中显示指针或下载预览，查看 LFS 状态，锁定 / 解锁，大文件未纳入 LFS 时警告 | P2 待评审 | C | 2 | Fork |
| EP10-F05 | git-flow：初始化，开始 / 结束 feature、release、hotfix | P2 待评审 | C | 1.5 | Fork 官网 |
| EP10-F06 | 提交签名：按 `commit.gpgsign`、`gpg.format`、`user.signingkey` 签名提交（GPG 或 SSH）；提交详情显示签名状态 | P2 待评审 | C | 1 | IDEA、Fork |

## 4. 交互规格

- 侧栏标识：worktree 仓显示「worktree · 主仓 GdThread」，submodule 显示为父仓下的子节点并带偏移徽标（如「↑ 新提交 3」）。
- Submodule 右键：初始化、更新到父仓记录的提交（`git submodule update --init -- <path>`）、在新标签打开、在访达显示。递归更新需要显式勾选。
- Push 确认（EP05-F02）中，若父仓提交引用的 submodule 提交尚未推送，显示警告「GdIM 子模块有 2 个提交未推送，推送父仓后其他人将无法检出」。
- LFS：文件行显示 LFS 标记；diff 中默认显示指针内容，提供「下载并预览」；状态与锁定在仓库右键「LFS」子菜单中。
- 签名：提交区在仓库配置了签名时显示「将签名」，提交详情用 `%G?` 显示「已验证 / 无法验证 / 未签名」。

| 场景 | 表现 |
|---|---|
| 扫描到 submodule 与父仓同时在工作区 | 父仓下显示子节点，子仓同时作为独立仓库出现在列表，标注「也是 GdHome 的子模块」 |
| worktree 的主仓不在工作区 | 显示主仓路径，提供「添加主仓」 |
| 未安装 git-lfs | LFS 功能入口置灰并提示安装方式 |
| 签名失败（密钥不可用） | 提交失败，原样显示 gpg / ssh-keygen 输出，不自动去掉签名重试 |

## 5. 验收口径

1. worktree 列表与 `git worktree list --porcelain` 一致。
2. submodule 状态与 `git submodule status` 一致；update 后子仓 HEAD 等于父仓记录的提交。
3. LFS 文件识别与 `git lfs ls-files` 一致。
4. 签名状态与 `git log --format=%G?` 一致。

## 6. 风险与明确不做

- MRD 10.5 的「LFS 大文件托管」指服务端存储，客户端识别与锁定不在其列；F04 是否纳入仍需确认。
- separate-git-dir 与 submodule 的纳管判定规则是 MRD 10.6 的待定项，F01 至 F03 落地前需要先定规则。
- git-flow 对锚点团队的价值未验证，排在最后。