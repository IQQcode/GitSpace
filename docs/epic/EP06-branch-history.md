# EP06 分支管理与历史改写

> 目标：补齐 Fork / IDEA 都有的分支面板与历史操作：rebase、cherry-pick、revert、撤销提交、reflog、交互式 rebase；并做一个多仓专属能力：按卡片号把一组跨仓提交 cherry-pick 到发版分支。

| 项 | 说明 |
|---|---|
| 优先级分布 | P1 3 项；P1（待评审） 6 项；P1（原 P2） 2 项；P1（待评审） 1 项 |
| 人周（粗估） | P1 阶段（M4 首批） 14.5；P1 阶段（M4 后期） 6；合计 20.5 |
| 依赖 | EP02-F01 提交图与 F03 右键菜单；EP05-F01 多仓框架（F06）；EP07 冲突流程（rebase / cherry-pick 冲突）；EP11 变更集（F06） |
| 关联 | MRD 10.1（cherry-pick / revert、非交互 rebase 为 P1，交互式 rebase 为 P1（原 P2））、10.2-D、10.2-G、10.4-11；[调研 §2.2、§3.2、§3.3](./research-fork-idea.md) |

## 1. 现状

- 分支管理在「分支」弹窗（⇧⌘B）里：本地与远程列表、新建并切换、切换（脏工作区引导 stash）、重命名、删除（`-d` / 强确认 `-D`）、检出远程分支。
- 合并只有 merge；引擎没有 rebase、cherry-pick、revert、reset、reflog 的调用路径。
- 安全闸禁止 `reset --hard`、`clean` 与任何 `-f` / `--force` 参数（`GitProcessRunner.validate`）。
- 侧栏只列仓库，不显示某个仓库的分支、tag、stash。

## 2. 对标参考

- IDEA：VCS widget 中收藏分支置顶、最近 5 个分支、按前缀分组；Checkout and Update；Smart Checkout；删除分支后通知里可恢复；Rebase Current onto Selected、Checkout and Rebase onto Current；Cherry-pick 支持多个提交与「Highlight Non-Picked Commits」；Undo Commit；Reset Current Branch to Here（Soft / Mixed / Hard / Keep）；Interactively Rebase from Here。
- Fork：侧栏分支树；拖分支到分支即合并或变基；双击检出；「选择陈旧本地分支」（2.62）；rebase、cherry-pick、revert 前预判冲突（2.55、2.66）；cherry-pick `-x`（2.4）；交互式 rebase 支持多选、快速动作、当前分支内拖拽重排与 squash（2.55）、`--update-refs`；Reflog 找回提交；Bisect。

## 3. Feature 清单

| ID | Feature | 优先级 | 排期 | 人周 | 依据 |
|---|---|---|---|---|---|
| EP06-F01 | 侧栏分支树：展开仓库查看本地分支、远程分支、tag、stash；搜索、收藏置顶、最近使用、按前缀分组、ahead / behind 徽标 | P1（待评审） | M4 首批 | 2 | Fork 侧栏、IDEA VCS widget |
| EP06-F02 | 分支快捷操作：双击检出、拖拽合并或变基、检出并更新、删除后可恢复、设置 / 取消 upstream、陈旧分支批量清理 | P1（待评审） | M4 首批 | 2 | Fork、IDEA |
| EP06-F03 | 智能切换：有改动时 stash、切换、再自动恢复；恢复冲突转入冲突流程 | P1（待评审） | M4 首批 | 1 | IDEA Smart Checkout、Fork lean branching |
| EP06-F04 | Rebase（非交互）：当前分支变基到所选分支、检出所选分支并变基到当前；进行中横幅提供继续 / 跳过 / 中止 | P1 | M4 首批 | 2 | MRD 10.1 |
| EP06-F05 | Cherry-pick：单个或多个提交、`-x` 选项、执行前预判冲突、进行中继续 / 中止、灰显已拣选的提交 | P1 | M4 首批 | 2 | MRD 10.1 |
| EP06-F06 | 跨仓 cherry-pick：选一个卡片号（或一组跨仓提交），挑到各仓的目标分支，逐仓预判与执行 | P1（待评审） | M4 首批 | 2 | 差异化：发版回合修复 |
| EP06-F07 | Revert：回滚整个提交（信息可编辑），或只回滚提交中的部分文件 | P1 | M4 首批 | 1 | MRD 10.1、IDEA Revert Selected Changes |
| EP06-F08 | 撤销最近提交与重置到此：未推送的最近提交「撤销提交」；「重置当前分支到此」提供 soft / mixed / keep | P1（待评审） | M4 首批 | 1.5 | IDEA Undo Commit、Reset |
| EP06-F09 | Reflog 与找回：查看 HEAD 与分支的 reflog，在条目上新建分支或检出 | P1（待评审） | M4 首批 | 1 | Fork 官网、MRD 10.2-G「可回溯」 |
| EP06-F10 | 交互式 rebase：从时间线发起，pick / reword / edit / squash / fixup / drop，拖拽排序，多选，`--update-refs` | P1（原 P2） | M4 后期 | 3 | MRD 10.1 |
| EP06-F11 | 历史快捷改写：对未推送提交直接 reword、squash 到上一个、fixup、drop | P1（原 P2） | M4 后期 | 1.5 | MRD 10.1（交互式 rebase 的快捷入口）、IDEA 历史编辑 |
| EP06-F12 | Bisect：标记 good / bad / skip，自动二分定位 | P1（待评审） | M4 后期 | 1.5 | Fork |

## 4. 交互规格

### 4.1 侧栏分支树与快捷操作（F01、F02）

```text
v GdThread            feature/TASK-123456   ↑2
    本地分支
      * feature/TASK-123456          ↑2
      ★ master                       ↓5
        feature/TASK-122001          （陈旧：60 天无提交）
    远程分支
      > origin
    Tag (12)
    Stash (1)
> GdFeedSupports      master                 ✓
```

- 仓库行可展开；单仓标签页（EP01-F02）中侧栏直接显示该仓的树。
- 分支右键：检出、检出并更新、合并到当前分支、当前分支变基到此、从此新建分支、重命名、删除、设置 / 取消 upstream、与当前分支比较、复制名称。
- 拖拽：把分支 A 拖到分支 B 上，弹出菜单「把 A 合并到 B / 把 B 变基到 A」，只在 B 是当前分支时直接执行，否则先提示切换。
- 删除后通知提供「恢复」（按删除前记录的 SHA 执行 `git branch <name> <sha>`），删除的分支跟踪远端时附加「同时删除远端分支」入口（需二次确认）。
- 「选择陈旧分支」：按「已合并到当前分支」或「N 天无提交」筛出本地分支，批量删除前列出清单确认。

### 4.2 进行中操作的统一横幅（F04、F05、F07、F10）

| 检测依据 | 横幅文案 | 按钮 |
|---|---|---|
| `MERGE_HEAD` | 合并进行中：2 个冲突文件 | 解决冲突、中止 |
| `rebase-merge/` 或 `rebase-apply/` | 变基进行中（3 / 7）：停在 a1b2c3d | 继续、跳过此提交、中止 |
| `CHERRY_PICK_HEAD` | Cherry-pick 进行中：1 个冲突文件 | 继续、中止 |
| `REVERT_HEAD` | Revert 进行中 | 继续、中止 |

- 应用启动时检测上述状态并显示横幅（TechStack §8 崩溃恢复）。
- 有冲突时「继续」置灰，引导进入 EP07 的冲突列表。

### 4.3 Cherry-pick 与跨仓 cherry-pick（F05、F06）

- 单仓：时间线多选提交右键「Cherry-pick 到当前分支」，按提交时间从旧到新应用；选项 `-x`（信息追加来源）。
- 预判：执行前对每个提交用 `git merge-tree --write-tree` 判断是否会冲突，确认框标出「预计冲突」的提交。
- 跨仓：在变更集（EP11）选中卡片 `TASK-123456`，选择「挑到分支...」：

```text
+-- 把 TASK-123456 挑到 release/22.14 ------------------------------+
| GdThread        2 提交   预计无冲突       目标分支存在             |
| GdFeedSupports  1 提交   预计冲突 1 个    目标分支存在             |
| GdHome          1 提交   已包含（跳过）                            |
+-------------------------------------------------------------------+
| 执行方式：每仓切到目标分支 -> cherry-pick -> 切回原分支（有改动的仓跳过） |
|                                            [取消]   [执行 ⌘↩]      |
+-------------------------------------------------------------------+
```

- 「已包含」用 `git cherry` 或 patch-id 判断，避免重复挑。
- 执行后汇总成功、冲突、跳过；冲突的仓停在 cherry-pick 进行中，进入 EP05-F10 冲突中心。

### 4.4 撤销提交、重置与 reflog（F08、F09）

- 「撤销提交」只对当前分支最新且未推送的提交可用，等价 `git reset --soft HEAD~1`，改动回到暂存区，提交信息回填到输入框。
- 「重置当前分支到此」对话框：

| 模式 | 结果 | 说明 |
|---|---|---|
| soft | 之后的提交撤销，改动回到暂存区 | 默认选中 |
| mixed | 之后的提交撤销，改动回到工作区 | |
| keep | 之后的提交撤销，保留本地未提交改动；有冲突时 git 拒绝执行 | |
| hard | 不提供 | 引擎安全闸禁止；是否开放列为待评审 |

- 目标提交之后有已推送的提交时，对话框红字提示「将改写已推送的历史，之后只能强推，GitSpace 不提供强推」，并默认禁用确认按钮（Gerrit 评审仓例外，见 §6）。
- Reflog：仓库右键「查看 Reflog」，列出 `HEAD@{n}`、动作、时间、提交标题；条目右键「在此新建分支」「检出（detached）」。删分支、reset 之后的找回都从这里完成。

### 4.5 交互式 rebase（F10、F11）

入口：时间线提交右键「从此交互式变基」（范围为该提交到 HEAD）；提交右键的快捷改写（F11）在后台生成同样的 todo 列表执行。

```text
+-- 交互式变基：GdThread / feature/TASK-123456（4 个提交） ------------+
| 动作      提交                                       作者   时间     |
| pick      a1b2c3d  [TASK-123456] 话题卡曝光埋点修正   jia    2 小时   |
| squash    b2c3d4e  修复拼写                           jia    2 小时   |
| reword    c3d4e5f  [TASK-123456] 补充单测             jia    1 小时   |
| drop      d4e5f6a  调试日志                           jia    30 分钟  |
+---------------------------------------------------------------------+
| 拖动行调整顺序；快捷键 P / R / E / S / F / D 切换动作；可多选批量设置   |
| [x] --update-refs        ! 有 1 个提交已推送（见 §6）                 |
|                                      [取消]   [开始变基 ⌘↩]           |
+---------------------------------------------------------------------+
```

- reword 与 squash 的信息编辑在对话框内完成，执行时通过 `GIT_SEQUENCE_EDITOR` 与 `GIT_EDITOR` 写入，不弹出终端编辑器。
- edit 动作停下时显示横幅（§4.2），用户可在提交视图中 amend 后「继续」。
- 执行中失败或冲突，状态与普通 rebase 一致，随时可中止回到开始前。

## 5. 验收口径

1. Rebase、cherry-pick、revert 的结果（提交数、树对象、信息）与命令行执行同一命令一致。
2. `-x` 选项追加的来源行与 `git cherry-pick -x` 一致。
3. 冲突预判与实际执行结果一致；预判无冲突但实际冲突时按冲突流程处理，不丢改动。
4. 撤销提交与三种重置模式的结果分别与 `git reset --soft HEAD~1`、`git reset --soft / --mixed / --keep <sha>` 一致。
5. 交互式 rebase 生成的 todo 与执行结果，与在 `git rebase -i` 中手工编辑同样 todo 的结果一致。
6. 中止任意进行中操作后，HEAD、分支指针与工作区恢复到操作前（`git reflog` + `git status` 校验，同 MRD 10.4-12）。
7. 删除分支后「恢复」得到的分支指向删除前的 SHA。

## 6. 风险与明确不做

- 改写已推送历史：GitSpace 永不强推，因此在普通仓库中改写已推送的提交会让分支无法推送。默认禁止对已推送提交执行 reset、交互式 rebase、快捷改写，确认框说明原因。
- Gerrit 评审仓例外：未合入的 change 通过 amend 或 rebase 后再推到 `refs/for/<分支>` 只会产生新补丁集，不需要强推。仓库标记为评审模式（EP08-F01）时，允许对「已推送到 refs/for 但未合入」的提交改写，并在确认框说明。
- `reset --hard` 与 `clean` 不在本 Epic 开放；如果评审决定开放，必须走强确认并在执行前自动快照（同 EP04-F01）。
