# EP07 合并、冲突、Stash 与 Tag 补齐

> 目标：先兑现 MRD 已承诺的合并收尾、外部合并工具、「两者都保留」、stash diff、tag 推送；再补内置三方合并编辑器，减少冲突时离开应用。

| 项 | 说明 |
|---|---|
| 优先级分布 | P0 5 项；P1（待评审） 5 项；P1（待评审） 1 项 |
| 人周（粗估） | P0 阶段（M1–M3） 4；P1 阶段（M4 首批） 8；P1 阶段（M4 后期） 1.5；合计 13.5 |
| 依赖 | EP03-F01 / F02（合并编辑器复用 diff 渲染）；EP05-F10 冲突中心；EP09-F02 外部工具设置 |
| 关联 | MRD 10.2-E、10.2-F、10.4-12、17.2-9（冲突解决深度待定）；TechStack §5.4；[调研 §2.2、§3.3](./research-fork-idea.md) |

## 1. 现状

- 合并：来源分支 + no-ff 开关；合并命令固定 `--no-edit`，合并信息不可编辑；完成后没有「立即推送」提示（MRD 10.2-E 要求两者都有）。
- 冲突：列表与 `git status --porcelain=v2` 一致；取当前 / 取对方 / 生成合并标记 / 标记已解决；可中止；全部解决才可完成。「生成合并标记」执行 `checkout --conflict=merge`，用户需要自己找编辑器改，界面内没有预览与确认（TechStack §5.4 要求读三路 stage 生成预览，确认后 `git add`）。
- 外部合并工具：设置与调用都未实现（代码中没有 `opendiff`、`ksdiff`、`code --wait` 等调用）。
- Stash：保存（带描述）、列表、pop / apply / drop；引擎有 `stashDiff`，界面没有接入，看不到 stash 内容。
- Tag：创建（轻量 / 附注）、列表、删除；引擎有 `pushTag`，界面没有接入，无法推送 tag。

## 2. 对标参考

- IDEA：冲突时自动弹 Conflicts 对话框（Accept Yours / Accept Theirs / Merge）；Resolve All Simple Conflicts；三栏合并器有「应用全部非冲突改动」、魔棒、Resolve using Left / Right、Revert conflict resolution；Accept and Finish；Pull 选项含 `--squash`、`--no-commit`。
- Fork：内置合并器，可选 3 栏布局，用分支名代替 ours / theirs（2.13），滚动条标记冲突（2.53）；外部合并器解决后展示结果 diff（2.58）；可合并图片、LFS、submodule；partial stash、重命名 stash、stash 另存为补丁；创建 tag 时可勾选推送（2.19）。

## 3. Feature 清单

| ID | Feature | 优先级 | 排期 | 人周 | 依据 |
|---|---|---|---|---|---|
| EP07-F01 | 合并收尾：非快进合并可编辑合并信息；合并完成后提示「立即推送」 | P0 | M1–M3 | 0.5 | MRD 10.2-E |
| EP07-F02 | 外部合并工具：设置中选择 FileMerge / Kaleidoscope / VS Code / 自定义模板；冲突文件一键打开；工具退出后检查结果并展示 diff | P0 | M1–M3 | 1.5 | MRD 10.2-E、TechStack §5.4 |
| EP07-F03 | 「两者都保留」：读取三路 stage 生成带标记的合并预览，用户确认或修改后再 `git add` | P0 | M1–M3 | 1 | MRD 10.2-E、TechStack §5.4 |
| EP07-F04 | Stash diff：选中 stash 查看文件列表与 diff | P0 | M1–M3 | 0.5 | MRD 10.2-F「查看 diff」 |
| EP07-F05 | Tag 推送：tag 列表与创建对话框提供推送 | P0 | M1–M3 | 0.5 | MRD 10.2-F「推送」 |
| EP07-F06 | 合并选项：`--squash`、`--no-commit` | P1（待评审） | M4 首批 | 0.5 | IDEA Pull 选项、Fork 2.4 |
| EP07-F07 | 内置三方合并编辑器 | P1（待评审） | M4 首批 | 4 | MRD 17.2-9、IDEA、Fork |
| EP07-F08 | 冲突列表增强：撤销冲突解决、二进制与图片选边、显示分支名 | P1（待评审） | M4 首批 | 1 | IDEA、Fork 2.13 |
| EP07-F09 | Stash 增强：包含未跟踪（`-u`）、保留索引（`--keep-index`）、只 stash 选中文件、重命名、另存为补丁、从 stash 新建分支 | P1（待评审） | M4 首批 | 1.5 | Fork、IDEA |
| EP07-F10 | Tag 增强：删除远端 tag、时间线提交上打 tag、附注 tag 详情、创建时同时推送 | P1（待评审） | M4 首批 | 1 | Fork 2.0、2.19 |
| EP07-F11 | 补丁：从提交或选中改动创建补丁、复制为补丁、从文件或剪贴板应用 | P1（待评审） | M4 后期 | 1.5 | IDEA Patch、Fork 2.29 / 2.64 |

## 4. 交互规格

### 4.1 合并对话框（F01、F06）

```text
+-- 合并到 GdThread / feature/TASK-123456 -------------------------+
| 来源分支   [origin/master                                   v]   |
| 方式       (*) 自动   ( ) 仅快进   ( ) 总是生成合并提交 --no-ff   |
|            ( ) squash --squash   ( ) 不自动提交 --no-commit       |
| 合并信息   [Merge branch 'master' into feature/TASK-123456   ]   |
+------------------------------------------------------------------+
| 将合入 5 个提交                              [取消]   [合并 ⌘↩]  |
+------------------------------------------------------------------+
```

- 合并信息默认取 git 生成的文本，只在会产生合并提交时可编辑（执行时用 `-m` 传入，不再固定 `--no-edit`）。
- 合并成功后通知「合并完成 [推送]」，点击进入推送确认（EP05-F02）。

### 4.2 冲突文件的处理路径（F02、F03、F07、F08）

| 文件状态 | 可选动作 | 结果 |
|---|---|---|
| 未解决 | 取当前分支 / 取对方分支 | `git checkout --ours / --theirs` + `git add`（现有） |
| 未解决 | 两者都保留 | 生成标记预览（F03），确认后写入并 `git add` |
| 未解决 | 用外部工具打开 | 按模板启动工具，等待退出（F02） |
| 未解决 | 在 GitSpace 中合并 | 打开三方合并编辑器（F07） |
| 外部工具已退出 | 查看结果 diff、标记已解决、重新打开 | 文件仍含冲突标记时提示「仍有 2 处冲突标记」，不自动标记解决 |
| 已解决 | 撤销解决 | `git checkout -m -- <path>` 恢复冲突状态（F08） |

- 列表与按钮上写分支名（「取 feature/TASK-123456」「取 master」），不写 ours / theirs（Fork 2.13）。rebase 时双方含义相反，按分支名显示可以避免误选。
- 外部工具命令模板示例：`opendiff "$LOCAL" "$REMOTE" -ancestor "$BASE" -merge "$MERGED"`、`ksdiff --merge --output "$MERGED" --base "$BASE" -- "$LOCAL" "$REMOTE"`、`code --wait --merge "$REMOTE" "$LOCAL" "$BASE" "$MERGED"`；路径以变量传入，不拼接进 shell 字符串。

### 4.3 内置三方合并编辑器（F07）

```text
+-- GdHome / Sources/Feed/FeedModel.m   冲突 1 / 2 ------------------------------------------+
| 取自 feature/TASK-123456     |  结果（可编辑）                 |  取自 master                |
|  41  if (type == kHot) {  [>>]|  41  <<< 冲突 1：选择左 / 右 / 两者 >>> |[<<]  if (type == kDaily) { |
|  42      return 1;           |  42      return 1;              |  42      return 2;            |
+-------------------------------------------------------------------------------------------+
| [应用全部非冲突改动]  [自动解决简单冲突]   上一处冲突 ⌘↑   下一处冲突 ⌘↓   滚动条标记冲突位置   |
|                                         [取消]   [保存并标记已解决 ⌘↩]                     |
+-------------------------------------------------------------------------------------------+
```

- 三栏内容分别来自 `git show :2:<path>`、编辑中的结果、`git show :3:<path>`，基线来自 `:1:`。
- 「自动解决简单冲突」只处理同一行两侧改动不重叠的情况（IDEA 魔棒的规则），其余冲突必须人工选择。
- 保存时检查结果中不再有冲突块；仍有冲突时不允许标记已解决。

### 4.4 Stash 与 Tag（F04、F05、F09、F10）

- Stash 面板：左侧列表（描述、时间、所属分支），右侧文件列表与 diff（`git stash show -p stash@{n}`）；右键 pop、apply、drop（二次确认）、重命名、另存为补丁、从此 stash 新建分支（`git stash branch`）。
- 保存对话框：描述、包含未跟踪文件、保留暂存区；从提交视图选中文件右键「只 stash 这些文件」（`git stash push -- <paths>`）。
- Tag：创建对话框增加「同时推送到 origin」；列表右键「推送」「删除远端 tag」（`git push <remote> --delete <tag>`，二次确认）；附注 tag 显示作者、时间、信息。

## 5. 验收口径

1. 冲突列表与 `git status --porcelain=v2` 的 `u` 记录完全一致（MRD 10.4-12，现有用例保持全绿）。
2. 合并信息编辑后，`git log -1 --format=%B` 与输入一致。
3. 外部工具退出后，只有在用户确认后才执行 `git add`；文件仍含冲突标记时不标记解决。
4. 「两者都保留」写入的内容与 `git checkout --conflict=merge -- <path>` 生成的标记文本一致，确认后的结果与用户编辑一致。
5. Stash diff 与 `git stash show -p stash@{n}` 一致；只 stash 选中文件后，未选中的文件改动仍在工作区。
6. Tag 推送后 `git ls-remote --tags <remote>` 包含该 tag；删除远端 tag 后不再包含。

## 6. 风险与明确不做

- 不做三方自动合并算法（MRD 10.2-E），「自动解决简单冲突」只处理不重叠改动，判断规则写进测试用例。
- 内置合并编辑器的投入会把 M3 推后 4 至 6 周（MRD 17.2-9），本文将其放在P1 阶段（M4 首批），P0 保持「列表 + 选边 + 外部工具」。
