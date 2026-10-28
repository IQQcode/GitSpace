# GitSpace — test

## 运行测试

```bash
cd repos/GitSpace
swift test
```

框架为 Swift Testing（`import Testing`），全部测试可在命令行跑完（无需 Xcode GUI）。fixture 仓使用临时目录，运行后可清理：

```bash
rm -rf "${TMPDIR:?}"/gitspace-tests
```

## 测试结构与口径

| 文件 | 覆盖 |
|---|---|
| `Tests/GSGitEngineTests/StatusAndLogTests.swift` | porcelain v2 解析 ≡ git 原始记录、上游 ahead/behind、log 字段与顺序、merge 提交判定 |
| `Tests/GSGitEngineTests/HunkStagingTests.swift` | diff 解析 roundtrip 逐字还原、**块级暂存 ≡ 过滤 hunk 后的 patch**（MRD 10.4-10 口径）、反暂存、整文件暂存 |
| `Tests/GSGitEngineTests/BranchMergeTests.swift` | 分支 CRUD、脏工作区阻断切换（10.4-11）、**冲突列表 ≡ porcelain u 记录**、ours/theirs ≡ `git checkout --ours/--theirs`、**中止合并 ≡ 合并前状态 + reflog 校验**（10.4-12）、远程检出 upstream |
| `Tests/GSGitEngineTests/CommitAndSafetyTests.swift` | 提交 HEAD 前进 1、amend 父提交不变、空提交拒绝、钩子失败透出原始输出且不产生提交（10.4-10）、**安全闸：force push / reset --hard / clean / -f 全部拦截**（10.2-G）、非快进 push 原样拒绝、stash/tag 闭环 |
| `Tests/GSIndexTests/ScannerAndTimelineTests.swift` | 扫描器发现/跳过规则、工作区配置 JSON roundtrip、跨仓时间线合并排序 |

等价性测试的基准统一是 git CLI 本身（TechStack §5.1：让 git 背书行为一致性），fixture 生成器在 `Packages/GSTestSupport`。

## 新增测试约定

- 场景仓库一律用 `FixtureRepo.make*`，禁止在固定路径创建；
- 断言尽量与 `GitShell.run` 的原始输出比对（等价性），而不是只断言自己解析器的输出；
- 网络类用例（fetch/push）用本地 bare 仓模拟远端，不依赖外网。
