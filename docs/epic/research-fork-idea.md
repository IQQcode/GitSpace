# Fork 与 IntelliJ IDEA 的 Git 能力调研

| 文档信息 | 说明 |
|---|---|
| 版本 | v1.0（2026-10-31） |
| 调研对象 | IntelliJ IDEA 2026.2 官方文档 Git 章节；Fork Mac 2.71（官网、Release Notes、官方博客） |
| 方法 | ego-browser 访问官网，IDEA 文档逐页读取官方 Markdown 版本；anysearch 补充检索发布博客与官方博客；只采信官方一手来源 |
| 用途 | [Epic 总览](./INDEX.md) 差距矩阵与各 Epic「对标参考」的事实依据 |

## 1. 结论

1. IDEA 的多仓能力不只是「合并 Log」。分支操作可以对所有 root 同步执行，任一仓失败时建议在已成功的仓回滚；Push 对话框一次列出所有仓的待推送提交；Update Project 对所有 root 统一 fetch 再 merge 或 rebase；Log 用左侧色条区分 root，可按 root 与目录过滤。GitSpace 目前只有合并时间线和批量 fetch / pull / push。
2. Fork 的「轻量顺手」来自大量小细节：命令面板 ⌘P、右键与拖拽覆盖所有动作、空格预览提交详情、暂存后不重置滚动、标签页徽标、危险动作前的冲突预判。GitSpace 现有 1 处右键菜单、2 个在菜单注册的快捷键，体验差距主要在这里。
3. 两者都具备而 GitSpace 缺失的日常能力：并排 diff、blame、文件历史、rebase、cherry-pick、revert、reset、reflog、内置三方合并、tag 推送、stash diff。
4. Fork 没有原生 Gerrit 支持，官方博客示范用 Custom command 做 Gerrit 推送；本次读取的 IDEA Git 章节没有 Gerrit 或 `refs/for` 内容。原生的 Gerrit 评审推送是 GitSpace 面向锚点团队的空位。
5. 两者都在加 AI：Fork 2.59 起可用 Claude、Codex、Cursor 生成提交信息与做分支代码评审；IDEA 2026.2 集成 GitHub Copilot。GitSpace 的开源与本地处理定位要求 AI 只能是显式开启的本机能力。

## 2. IntelliJ IDEA 2026.2

### 2.1 多仓（multi-root）行为

| 能力 | IDEA 行为 | 出处 |
|---|---|---|
| 登记与发现 | Directory Mappings 逐个登记 root；扫描到未登记的仓库时弹通知，可「Add roots」或「Ignore」，之后再出现新仓库会再次提示 | enabling-version-control |
| Log 区分 root | 多仓项目在提交行左侧画彩色条，每个 root 一种颜色，悬停显示 root 路径 | investigate-changes |
| Log 过滤 | 按分支或收藏分支、作者、日期、目录过滤；多 root 项目按 root 加目录过滤；搜索支持提交信息、hash、正则 | investigate-changes |
| 分支分组 | 多仓项目的 VCS widget 自动按仓库分组分支，先选仓库再选分支 | manage-branches |
| 同步分支控制 | 开启「Execute branch operations on all roots」后，checkout、merge、delete 等分支操作在所有 root 同时执行；任一仓失败时建议在已成功的仓回滚，避免分支分叉；只在单个 root 切换时 widget 提示「Branches have diverged」；远程分支出现 Common Remote Branches 节点 | manage-branches |
| Push 对话框 | 列出所有仓库，以及每个仓自上次推送以来当前分支的提交；未开启同步控制时默认只勾选当前仓；可逐仓改目标分支，或用「Edit all targets」一次改全部；可选中提交预览文件；Push tags 可选 All（`--tags`）或 Current Branch（`--follow-tags`）；Force push 实际执行 `--force-with-lease`，受 Protected branches 限制 | commit-and-push-changes |
| Push 被拒 | Push Rejected 对话框可勾选「Update all repositories」，选 Rebase 或 Merge 更新后再推，可记住选择 | commit-and-push-changes |
| Update Project（⌘T） | 从所有 root 与分支 fetch，再把跟踪分支合入本地；更新方式 Merge / Rebase / Reset to Remote 对所有 root 生效；脏工作区按设置用 Stash 或 Shelve 清理；完成后打开 Update Info 标签列出本次新增提交 | sync-with-a-remote-repository、settings-version-control-git |
| Pull 对话框 | 多仓项目多一个仓库下拉；可选 remote 与分支；选项含 `--rebase`、`--ff-only`、`--no-ff`、`--squash`、`--no-commit`、`--no-verify` | sync-with-a-remote-repository |
| Push 到其他目标 | 仓库没有 remote 时显示「Define remote」；目标分支名可直接改写，用于推到新的远端分支 | commit-and-push-changes |

### 2.2 日常能力与交互要点

| 域 | 能力与交互 | 出处 |
|---|---|---|
| 提交 | Commit 工具窗口（⌘0）；Amend 可选要修改的提交；提交信息历史；读取 `commit.template`；Commit Checks（格式化、优化 import、代码分析、TODO、运行配置）；可指定 Author、Sign-off；可关闭 Git hooks；Commit and Push（⌥⌘K） | commit-and-push-changes |
| 部分提交 | 在 diff 中勾选块；右键「Split Chunks and Include Selected Lines into Commit」做到行级；块可移到其他 Changelist；开启 staging area 后可在编辑器 gutter 暂存块，并用「HEAD / Staged / Local」三栏编辑器暂存任意粒度 | commit-and-push-changes |
| Changelist 与 Shelve | 改动默认进入活动 Changelist，可按逻辑分组分别提交；Shelve 可只选部分文件，生成由 IDE 管理的补丁；Stash 由 git 生成且包含全部改动；两者可合并在一个标签页 | managing-changelists、shelving-and-unshelving-changes |
| 分支 | 收藏分支置顶（主分支默认收藏）；最近 5 个分支；按前缀分组；新建时按已有分支名提示前缀；Checkout and Update；Smart Checkout（shelve、切换、再恢复）与 Force Checkout；删除后通知里可恢复，并可查看未合并提交 | manage-branches |
| 比较 | Compare with Current 列出对方有、当前没有的提交，可 Swap；Show Diff with Working Tree；Branch 过滤支持 `a..b` 两点语法；Log 中选两条提交做 Compare Versions | manage-branches、investigate-changes |
| 合并与变基 | Merge into Current、Rebase Current onto Selected、Checkout and Rebase onto Current、Pull into Current Using Rebase | apply-changes-from-one-branch-to-another |
| 交互式 rebase | Log 中「Interactively Rebase from Here」；Pick、Stop to Edit、Reword、Squash、Fixup、Drop；Start Rebasing；暂停时通知可继续或中止；高级选项 `--autosquash`、`--root`、`--update-refs` | apply-changes-from-one-branch-to-another |
| Cherry-pick | 工具栏 Cherry-pick；「Highlight Non-Picked Commits」灰显已拣选的提交；状态栏 Abort / Continue；Cherry-Pick Selected Changes 只拣选部分文件；Get from Branch 取整个文件 | apply-changes-from-one-branch-to-another |
| 撤销 | Rollback（⌘⌥Z）回滚未提交改动；Undo Commit；Revert Commit 自动生成信息并可去掉部分文件；Revert Selected Changes；Drop Commit；Drop Selected Changes；Reset Current Branch to Here（Soft / Mixed / Hard / Keep）；从文件历史 Get 旧版本 | undo-changes |
| 历史编辑 | Edit commit message、Amend any earlier commit（fixup）、Squash、Drop、Extract selected changes | edit-project-history |
| 冲突 | 冲突时自动弹 Conflicts 对话框：Accept Yours / Accept Theirs / Merge；Resolve All Simple Conflicts；三栏合并器提供「应用全部非冲突改动」、魔棒解决简单冲突、Resolve using Left / Right、Revert conflict resolution，全部解决后 Accept and Finish；关闭对话框后 Commit 窗口保留 Merge Conflicts 节点与 Abort Merge。2026.2 发布说明列出「Streamlined Git conflict resolution flow」 | resolve-conflicts、2026.2 发布博客 |
| Annotate 与历史 | Annotate with Git Blame、Annotate previous revision；Show History（文件、目录、选区）；Show Repository at Revision | investigate-changes |
| Diff viewer | Side-by-side / Unified；忽略空白（无、首尾、全部、含空行、import 与格式）；高亮粒度（Words / Lines / Split chars）；对齐改动、同步滚动、折叠未改动片段；F7 / ⇧F7 跳转改动 | differences-viewer |
| Issue 链接 | Version Control 中的 Issue Navigation 配置「正则 → URL」，提交信息里的匹配项在 Log 中渲染为链接，例如 `[A-Z]+\-\d+` 对应 `http://mytracker/issue/$0` | handling-issues |
| 设置 | 后台自动 fetch（每 20 分钟）；检查远端未拉取提交并在 widget 标注；Fetch tags 模式（Auto、`--prune-tags`、`--tags`、`--no-tags`）；push 被拒后自动更新；Protected branches；提交 CRLF 警告；detached HEAD 或 rebase 中提交的警告；cherry-pick 附加来源 hash | settings-version-control-git |

### 2.3 官方文档列出的 macOS 快捷键

| 快捷键 | 动作 | 快捷键 | 动作 |
|---|---|---|---|
| ⌃V | VCS Operations Popup | ⌘9 / ⌘0 | Git 工具窗口 / Commit 工具窗口 |
| ⌘K | Commit | ⌥⌘K | Commit and Push |
| ⌘⇧K | Push | ⌘T | Update Project |
| ⌘⌥Z | Rollback | ⌘D | Show Diff |
| ⌘F | Log 中跳到 hash / 分支 / tag | ⌘L | 聚焦 Log 搜索框 |
| ← / → | 跳到父 / 子提交 | F7 / ⇧F7 | diff 中下 / 上一处改动 |
| ⌃⌥⇧↓ / ↑ | 编辑器中下 / 上一处改动 | ⌘⌥A | 暂存文件（staging area 模式） |

## 3. Fork（Mac 2.71）

### 3.1 官网功能清单

- 基础：fetch / pull / push，commit / amend，分支与 tag 的增删，remote 的增删，检出分支或修订，cherry-pick，revert，merge，rebase，stash，submodule。
- 仓库：创建、克隆或添加已有仓库，快速打开最近的仓库。
- 提交视图：逐行暂存与取消暂存，最近的提交信息。
- 进阶：交互式 rebase，blame，浏览任意提交时的文件树，冲突解决，用 Reflog 找回丢失的提交，stash 直接显示在提交列表，git-flow，Git LFS，GPG。
- 首页展示的模块：GitHub 通知，合并冲突助手与内置解析器，可视化交互式 rebase，图片 diff，高级 diff，文件与目录历史，blame。
- 定价与平台：$59.99，免费评估；Mac 要求 OS X 10.11+。最新版本 2.71，发布日期 2026-10-23（MRD §17.3 已核验）。

### 3.2 近期版本演进（Release Notes for Mac，2.48 至 2.71）

| 主题 | 版本与新增 |
|---|---|
| 工作区与标签 | 2.26 Workspaces 组织多仓；2.45 标签徽标显示未提交改动；2.58 同名仓库的标签显示路径差异；2.67 ⇧⌘T 恢复关闭的标签；2.68 标签右键：重命名、选颜色、在终端打开、在访达显示；2.70 Vertical tabs；2.71 每个窗口独立的 Workspace，⌘ 点击在新窗口打开 |
| 键盘与导航 | 2.61 ⇧⌘. 切换 reflog 或忽略文件；2.66 侧栏方向键导航，Tab 在侧栏与提交列表间切换，⌘D 折叠提交详情；2.67 空格弹出提交详情，⌘↑ / ⌘↓ 上下块导航，Tab 在提交列表与详情间切换 |
| 提交列表 | 2.53 分支标签按图的颜色绘制；2.55 有正文的提交显示「↩︎」；2.62 Pull / Push 按钮显示 ahead / behind 数；2.67 重启后记住折叠的提交 |
| 历史改写 | 2.55 在当前分支内拖拽重排与 squash；2.55 rebase 对话框预判是否冲突；2.61 / 2.63 `--update-refs`；2.66 预判 cherry-pick、revert 能否无冲突完成 |
| 冲突 | 2.53 合并器滚动条标记冲突位置；2.58 外部合并器解决后展示结果 diff |
| 历史与 blame | 2.59 选中代码片段的文件历史；2.60 文件树右键查看某个块的历史 |
| AI | 2.59 用 Claude 做分支代码评审与生成提交信息；2.60 Claude Code Review；2.61 AI 评审 SHA 区间；2.64 支持 Codex，可编辑默认 AI 请求；2.70 支持 Cursor |
| worktree | 2.31 侧栏显示 worktree；2.41 创建与删除；2.63 Create Worktree 对话框（Quick Launch 可达），删分支时可一并删除 worktree；2.68 把远端分支检出为 worktree |
| 其他 | 2.52 仓库 Treemap；2.56 自动显示新仓库，bisect 用颜色标记好坏；2.62「选择陈旧本地分支」；2.64 ⌘V 从剪贴板应用补丁；2.65 .gitignore 模板选择；2.69 stash 另存为补丁，active 分支 upstream 无效时显示警告 |

### 3.3 更早的奠基功能

- Quick Launch 命令面板 ⌘P（1.0.84），模糊搜索（1.0.85），可搜索文件路径（2.57），可调用 Workspaces 与 Create Worktree。官方博客示范：输入几个字符检出分支、按文件名打开文件历史。
- Custom commands：1.0.99 可共享给团队，URL 命令可在自建服务器上创建 PR；2.7 bash 命令；2.29 带界面的命令（文本框、分支下拉、文件选择器）；2.51 复选框控件。官方博客用 Custom command 示范 Gerrit 推送。
- 提交搜索：按信息、diff 内容（1.0.92）、文件路径（1.0.98）；记住最近搜索（2.9）；可按当前分支过滤（⇧⌘A，1.0.82）。
- 交互式 rebase：快速动作（1.0.78），多选（1.0.91），提交右键「Edit」（1.0.95）；squash、drop、cherry-pick 支持多个提交（1.0.83）。
- 图片 diff：swipe 与 onion skin（2.12），像素级差异（2.42），支持 HEIC、WebP、SVG、TGA。
- Blame：时间线（2.10），前进与后退（2.11）。
- 合并器：3 栏布局（2.13），用分支名代替 ours / theirs（2.13），导航链接（2.18），可合并图片、LFS 文件与 submodule（2.6），自定义合并与 diff 工具（2.0），VS Code 作为合并工具（1.0.80）。
- Stash：partial stash（1.0.92），保存快照（1.0.99），重命名（2.3）。
- Lean branching：同步时先 stash，再恢复未提交改动（2.16、2.20）。
- 细节：丢弃块后不重置滚动位置；块暂存更精确（2.20）；块暂存失败时提示关闭忽略空白；Activity Manager 展示每条 git 命令与输出；Push 窗口对 `--force` 显示警告图标；一次推送多个分支；侧栏显示分支 upstream 状态。
- 集成：GitHub、GitLab、Bitbucket（含服务器版）登录与 GitHub 通知；在 Xcode、BBEdit 中定位到行；终端可选 Kitty、Ghostty。

### 3.4 Fork 手感的关键细节

下面每条都能直接转成 GitSpace 的验收项，括号内为出处。

1. ⌘P 命令面板能执行所有动作，并能把分支、文件当参数补全（Quick Launch 博客）。
2. 右键与拖拽覆盖核心动作，拖分支到另一个分支即可合并或变基（官方博客 1.48）。
3. 暂存或丢弃块后，列表与 diff 不跳回顶部（Release Notes；MRD §7.2）。
4. 空格看提交详情，Tab 在侧栏、列表、详情间移动，方向键导航（2.66、2.67）。
5. 标签页徽标提示未提交改动，标签可着色与重命名（2.45、2.68）。
6. 分支标签用图的颜色绘制，双击标签即检出（2.16、2.53）。
7. 危险动作前预判：rebase、cherry-pick、revert 会不会冲突（2.55、2.66）。
8. 冲突解决界面写分支名，不写 ours / theirs（2.13）。
9. Pull / Push 按钮直接显示 ahead / behind 数字（2.62）。
10. 同步时自动 stash 并恢复未提交改动（lean branching，2.16、2.20）。
11. 外部合并器解决后，回到 Fork 立刻看到结果 diff（2.58）。
12. Activity Manager 能查到每条 git 命令与输出（Release Notes）。
13. 提交信息历史与模板随手可取（官网）。
14. 新出现的仓库自动显示在仓库管理器（2.56）。
15. 误关的标签可以恢复（⇧⌘T，2.67）。

### 3.5 已核实的 Fork 快捷键

| 快捷键 | 动作 | 出处 |
|---|---|---|
| ⌘P | Quick Launch 命令面板 | 官方博客 |
| ⌥⌘↩ | Commit & Push | 2.68 |
| ⇧⌘G | 新建 tag | 2.67 |
| ⇧⌘T | 恢复关闭的标签 | 2.67 |
| 空格 | 弹出提交详情 | 2.67 |
| ⌘↑ / ⌘↓ | 上 / 下一块 | 2.67 |
| ⌘D | 折叠提交详情 | 2.66 |
| ⇧⌘. | 切换 reflog 或忽略文件 | 2.61 |
| ⇧⌘A | 只看当前分支 | 1.0.82 |

其余快捷键没有在官方页面找到出处，未列入。

## 4. 对 GitSpace 的映射

| 借鉴点 | 来源 | 落位 |
|---|---|---|
| 同步分支操作 + 失败回滚 | IDEA | [EP05](./EP05-multi-repo-ops.md) |
| 多仓 Push 对话框、被拒后更新全部仓 | IDEA | [EP05](./EP05-multi-repo-ops.md) |
| Update Project 与 Update Info | IDEA | [EP05](./EP05-multi-repo-ops.md) |
| 一次提交覆盖多个 root | IDEA | [EP05](./EP05-multi-repo-ops.md) |
| root 色条、root 与目录过滤、跳转 hash、父子提交导航、多个 Log 标签 | IDEA | [EP02](./EP02-timeline.md) |
| 并排 diff、忽略空白、高亮粒度、blame、文件 / 选区历史、图片 diff | IDEA、Fork | [EP03](./EP03-diff-blame-history.md) |
| 行级暂存、提交信息历史与模板、Commit and Push、Changelist 思路 | IDEA、Fork | [EP04](./EP04-commit-workbench.md) |
| 分支收藏 / 最近 / 前缀分组、拖拽合并、Smart Checkout、rebase、cherry-pick、reset、reflog、交互式 rebase | IDEA、Fork | [EP06](./EP06-branch-history.md) |
| 三栏合并器、外部合并器结果 diff、stash 补齐、tag 推送、补丁 | IDEA、Fork | [EP07](./EP07-merge-conflict-stash-tag.md) |
| Gerrit 推送（Fork 用 Custom command 实现） | Fork 博客 | [EP08](./EP08-gerrit-review.md) |
| Open in 终端 / 编辑器、Custom commands、Issue 链接 | Fork、IDEA | [EP09](./EP09-integrations-commands.md) |
| worktree、submodule、LFS、git-flow、GPG | Fork、IDEA | [EP10](./EP10-advanced-repo.md) |
| 命令面板、右键、拖拽、键盘导航、标签页、Activity Manager | Fork | [EP12](./EP12-ux-foundation.md)、[EP01](./EP01-workspace-repos.md) |

## 5. 来源

IntelliJ IDEA 2026.2 文档（前缀 `https://www.jetbrains.com/help/idea/2026.2/`，每页加 `.md` 后缀即官方 Markdown 版本）：

- `using-git-integration.html`、`enabling-version-control.html`、`set-up-a-git-repository.html`
- `investigate-changes.html`、`manage-branches.html`、`sync-with-a-remote-repository.html`
- `commit-and-push-changes.html`、`apply-changes-from-one-branch-to-another.html`、`resolve-conflicts.html`
- `undo-changes.html`、`edit-project-history.html`、`shelving-and-unshelving-changes.html`、`managing-changelists.html`
- `differences-viewer.html`、`handling-issues.html`、`main-version-control-shortcuts.html`、`settings-version-control-git.html`
- `use-git-worktrees.html`、`set-up-GPG-commit-signing.html`、`using-patches.html`、`use-tags-to-mark-specific-commits.html`
- IntelliJ IDEA 2026.2 发布博客（2026-07-16）：https://blog.jetbrains.com/idea/2026/07/intellij-idea-2026-2/

Fork：

- 官网：https://git-fork.com/
- Release Notes for Mac：https://git-fork.com/releasenotes
- 官方博客（Quick Launch 与 Custom commands、Gerrit 推送示例、1.48 拖拽合并与 partial stash）：https://www.fork.dev/blog
