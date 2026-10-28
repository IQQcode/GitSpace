# GitSpace 技术选型文档(Tech Stack)

| 文档信息 | 说明 |
|---|---|
| 版本 | v1.0(2026-10-29) |
| 状态 | Draft(供技术评审; 对应 MRD 13 章"技术评审"节点) |
| 关联文档 | MRD v2.0 `docs/prd/GitSpace-MRD-v2.0.md`(性能口径见其 10.4, 约束见第 12 章); 交互原型 `design/gitspace-prototype/index.html` |
| 范围 | 语言/工具链, UI 框架与 macOS 27 适配, Git 执行引擎, 数据存储, 并发模型, 依赖与许可, 构建分发, 测试策略 |

---

## 1. 决策总览(一页速览)

| 领域 | 选型 | 一句话理由 |
|---|---|---|
| 语言 | Swift 6.4(Swift 6 语言模式, 严格并发) | 原生手感与性能的硬约束只有原生栈能满足 |
| 工具链 | Xcode 27(2026-09)+ macOS 27 SDK | 支持 macOS 27 UI 属性的最低官方工具链 |
| UI 框架 | SwiftUI 主导 + AppKit 关键路径混编 | 结构层用 SwiftUI(声明式, 双语/无障碍免费获得); diff/大文本用 AppKit 保性能 |
| macOS 27 适配 | Liquid Glass 材质体系(macOS 26 基座)+ `@available(macOS 27)` 分层增强 | 27 是打磨版, 基座来自 26 的 `glassEffect` 系列 API |
| 最低系统 | 建议 macOS 14 Sonoma(提请评审修订 MRD 的 13) | `@Observable` 框架(macOS 14+)对大列表状态管理收益显著; 14/15 仍支持 Intel |
| Git 引擎 | **系统 git CLI 作为唯一执行与数据来源**(异步进程池 + 流式解析) | 钩子/冲突语义/`add -p` 等价性/Gerrit 兼容, 只有 CLI 能保证与 git 行为 100% 一致 |
| 提交索引 | SQLite(GRDB.swift)+ FTS5 全文检索 | 50 仓 × 10 万提交下"过滤 ≤300ms"必须靠本地索引, 不能每次实时解析 |
| 并发模型 | Swift Concurrency(actor 隔离 + TaskGroup), 批量默认并发 4 | 直接映射 MRD 的并发/超时/重试参数 |
| 文件监听 | FSEvents(工作区级单流)+ 事件去抖 + 30s 低频轮询兜底 | MRD 12: 触发式 + 轮询折中, 50+ 仓避开 FSEvents 上限 |
| 凭据 | macOS Keychain(Security framework)+ ssh-agent 透传 | MRD 12 硬约束: 不落明文, 不写日志 |
| 存储 | 索引用 SQLite(派生数据, 可重建); 工作区配置用 JSON; 操作日志 JSONL | 索引可删可重建, 配置可读可导出, 各司其职 |
| 更新分发 | Developer ID 签名 + 公证 + Sparkle 2 + Homebrew Cask | MRD 12 的 Gatekeeper/更新要求 |
| 测试 | Swift Testing + XCTest + git fixture 仓生成器 + 性能基准脚本 | 验收 13 条全部可自动化比对 git 基准 |

---

## 2. 约束锚点(来自 MRD, 选型必须满足)

选型不是自由发挥, 以下 MRD 条目是硬约束:

- **性能(MRD 10.4)**: 50+ 仓冷扫描 60s / 增量 ≤5s; 50 仓 × 10 万提交下首屏 ≤3s、过滤 ≤300ms、滚动 ≥55fps、常驻内存 ≤500MB; 冷启动 ≤2s、空载内存 ≤200MB、安装包 ≤60MB(Apple Silicon, 基准 M1/16GB)。
- **行为一致性(MRD 10.4)**: 块级暂存与 `git add -p` 等价; 冲突列表与 `git status --porcelain` 完全一致; ours/theirs 与 `git checkout --ours/--theirs` 一致。
- **安全边界(MRD 10.2-G)**: 永不 force push; 破坏性操作二次确认; 写操作全量本地日志; 崩溃后仓库不处于半完成状态。
- **轻量与独立(MRD 12)**: 不绑定 IDE 与语言; 依赖系统 git ≥2.30 或内置 libgit2/gitoxide 由本评审决定。
- **网络(MRD 12)**: 批量并发默认 4(可调 1–8), 单仓超时 60s, 网络错误自动重试 1 次; 企业代理与自签证书可用。
- **凭据(MRD 12)**: SSH key 与 HTTPS token 交由 Keychain, 支持 ssh-agent 与 `~/.ssh/config`。
- **许可(MRD 12/14)**: Apache 2.0(建议)开源 → 所有第三方依赖必须与 Apache 2.0 兼容, GUI/diff 相关库的许可需单独审查。
- **兼容(MRD 12)**: Apple Silicon 优先, Intel 可用; 中英双语; VoiceOver 与全键盘。

---

## 3. 平台与工具链

| 项 | 值 | 说明 |
|---|---|---|
| 语言 | Swift 6.4 | Xcode 27 内置; 开启 **Swift 6 语言模式**(严格并发检查), 把数据竞争在编译期拦下——多仓并发读写索引的场景必须有这个保障 |
| IDE / SDK | Xcode 27(2026-09-14 发布)+ macOS 27 SDK | 最低能编译 macOS 27 UI 属性的工具链 |
| UI 目标 | macOS 27 适配为"增强层", 不是最低要求 | 见第 4 章分层策略 |
| 工程组织 | Swift Package 多模块 + 单一 App target | 模块边界即编译边界, 保住增量编译速度与职责清晰(见第 9 章) |
| git 二进制 | 系统 `/usr/bin/git`(启动时校验版本 ≥2.30, 低于则引导升级) | macOS 13 自带 git 2.32+, 天然满足 MRD 口径; 不随包内置 git, 控制包体 |

**最低系统版本的决策点(需评审拍板)**:

- MRD 12 写"最低 macOS 13"。本文建议**修订为 macOS 14(Sonoma)**, 理由:
  1. `@Observable`(Observation 框架)要求 macOS 14+, 其细粒度依赖追踪对"50 仓状态总览 + 时间线过滤"这类高频状态更新场景, 比传统 `ObservableObject` 全量刷新有实打实的 CPU/能耗收益;
  2. macOS 13 在目标用户(开发者)中的装机占比已很低, 为它引入 `ObservableObject`/条件编译双路径的维护成本不划算;
  3. macOS 14/15 仍支持 Intel Mac, MRD 的"Intel 可用"不受影响(macOS 26 起才放弃 Intel)。
- 若评审坚持 13: 方案退化为 `ObservableObject` + `Combine`, 其余选型不变, 预估增量成本约 2 周(状态层返工 + 双路径测试)。

---

## 4. UI 框架与 macOS 27 适配

### 4.1 框架分工: SwiftUI 主导, AppKit 守住性能敏感路径

| 路径 | 框架 | 理由 |
|---|---|---|
| 窗口结构 / 侧栏 / 工具栏 / 设置 | SwiftUI(`NavigationSplitView`, `Settings` scene) | 双栏"仓库树 + 内容区"结构、双语、VoiceOver、快捷键系统在 SwiftUI 上免费获得 |
| 跨仓统一时间线 | SwiftUI `List`(虚拟化)+ `Canvas` 绘制提交图 | 行高固定, 虚拟化下 10 万行无压力; `Canvas` 是 GPU 路径, 55fps 有保障 |
| 状态总览 / 批量面板 | SwiftUI `Table`(排序/多选内建) | 直接对应 MRD 流程三/四 |
| **diff(统一/并排)** | **AppKit `NSTextView`(TextKit 2)**, 经 `NSViewRepresentable` 桥接 | 万行级 diff 的渲染与滚动只有 TextKit 2 稳; 行内红绿高亮用 `NSAttributedString` |
| blame / 文件历史 | 同上, 复用 DiffTextView 渲染层 | `git blame --porcelain` 解析后渲染 |
| 冲突面板 | SwiftUI + 复用 DiffTextView | 列表/选边交互在 SwiftUI, 文件内容预览走 AppKit |
| 提交图彩色曲线 | `Canvas` + 索引层预计算 lane 布局 | 布局计算放后台(见第 6 章), 渲染零计算 |

原则: **SwiftUI 出现性能或能力边界时, 立即下沉 AppKit, 不硬扛**。这正是 MRD 14"原生外壳 + Web 渲染"回退方案的替代——原生栈内部就有降级空间, 不需要引入 Web 层。

### 4.2 macOS 27 UI 属性适配(分层策略)

macOS 27(代号 Golden Gate, 2026 年秋)是 **Liquid Glass 的打磨版本**: 视觉语言延续 macOS 26 引入的玻璃材质体系, 主要变化是系统级透明度控制滑块与可读性修复, SwiftUI 层以 26 的 API 为基座、27 为增量。据此采用三层适配:

| 层 | 可用版本 | 内容 |
|---|---|---|
| **L0 基础层** | macOS 14+ | 全部功能与信息架构, 使用系统标准材质(`Material`), 保证任何系统版本下观感完整 |
| **L1 玻璃层** | macOS 26+(`@available(macOS 26, *)`) | Liquid Glass 材质: 工具栏/侧栏 `glassEffect(.regular)`; 相邻玻璃控件用 `GlassEffectContainer` 合并; 侧栏内容延伸 `backgroundExtensionEffect()`; 顶部"合并进行中"常驻条用玻璃材质悬浮 |
| **L2 打磨层** | macOS 27+(`@available(macOS 27, *)`) | 跟随系统透明度滑块(系统行为, 无需代码); 采用 27 发布的 polish API 与修复; 材质行为回归测试 |

设计落地方式:

- **设计令牌单点收敛**: `GSDesignKit` 内定义 `GS.material(name)` / `GS.tint` / `GS.spacing` 等令牌, 界面代码只引用令牌, 不直接写 `glassEffect`。L1/L2 的启用与降级全部发生在令牌层, 换系统/关特效零改动业务代码。
- **无障碍降级**: 系统"减少透明度(Reduce Transparency)"开启时, 令牌层自动把玻璃材质降级为不透明材质(MRD 12 无障碍要求); "增强对比度"同理。
- **克制原则**: 玻璃材质只用于工具栏、侧栏、悬浮条、批量操作面板等"容器层"; 提交列表、diff、表单等内容区保持实底, 信息密度优先——这是 Fork 式"克制"的工程化表达。

### 4.3 界面 → 组件映射(对照原型 `design/gitspace-prototype/index.html`)

| 界面 | 实现载体 | 备注 |
|---|---|---|
| 三栏骨架(仓库树 / 主视图 / 详情) | `NavigationSplitView` 三栏 | 对应原型的左侧栏 + 时间线 + 提交详情 |
| 跨仓统一时间线 | `List` + `Canvas` 图列 + 行内头像/短 SHA/日期 | 虚拟化; 无障碍: 每行提供聚合 `accessibilityLabel`(作者/仓库/信息) |
| 提交详情与 diff | 详情栏 SwiftUI 壳 + DiffTextView | 统一/并排切换; 并排用双 `NSTextView` 同步滚动 |
| 状态总览 | `Table` + 每仓状态徽标 | "数据截至 X 小时前"标注 fetch 时间 |
| 批量操作面板 | 底部玻璃悬浮条 + `Table` 逐仓进度 | 玻璃层适用点; 可取消/重试 |
| 合并进行中 | 顶部常驻悬浮条(玻璃材质)+ 冲突文件列表置顶 | `@available(macOS 26, *)` 玻璃, 低版本用标准材质 |
| 改动视图(暂存) | 两栏文件树 + DiffTextView + hunk 选择 | hunk 级操作见第 5.3 |
| 多仓标签页 | `Window` + `openWindow` / 标签化窗口 | 对齐 Fork 的多仓标签习惯 |

---

## 5. Git 执行引擎(本方案核心决策)

### 5.1 选型结论: 系统 git CLI 为唯一执行与数据来源

三种候选的对照:

| 方案 | 钩子支持 | 行为一致性 | SSH/代理/自签证书 | 工程复杂度 | 结论 |
|---|---|---|---|---|---|
| **系统 git CLI**(选定) | 原生完整 | **与 git 100% 一致**(验收 10/12/13 条的直接基准) | 继承用户环境(ssh-agent, `~/.ssh/config`, `http.*` 配置) | 低(进程封装 + 解析) | ✅ |
| libgit2(SwiftGit2 绑定) | 历史上薄弱(hook/`merge --abort` 语义需自行补齐) | 部分场景与 git 有差异(gitignore 规则, 传输行为) | 需自实现传输层适配 | 中(C 绑定 + 行为补丁) | ❌ 不作为主引擎 |
| gitoxide(Rust FFI) | 同上 | 较好但非基准 | 需适配 | 中高(Rust 工具链 + FFI) | ⏸ 仅作未来读取层备选(许可 Apache/MIT 双许可, 兼容) |

**决定性理由**: MRD 的验收标准 10/12/13 条(块级暂存 ≡ `git add -p`, 冲突列表 ≡ `git status --porcelain`, ours/theirs ≡ `git checkout --ours/--theirs`)全部以 git 自身行为为基准, 且 10.2-C 已明确"实现为 `git diff` 拆块后 `git apply --cached`"。用 CLI 就等于让 git 替我们背书行为正确性; 用 libgit2 则每条验收都要自证一致。钩子(pre-commit / commit-msg)由 CLI 原生执行, stderr 原样捕获展示, 天然满足"不吞错, 不产生提交"。

### 5.2 进程层设计

```
GitProcessRunner (actor)
├── GitProcessPool        # 全局进程数上限 = 批量并发设置(默认 4, 1–8)
├── RepoExecutor(actor)   # 每仓一个 actor: 同仓命令串行, 跨仓并行
├── StreamingParser       # 逐行/逐字段流式解析(AsyncSequence), 不等全量输出
└── GitError              # 按类别归类: 网络 / 鉴权 / 冲突 / 数据损坏 / 取消
```

- **超时与取消**: 60s 单仓超时(MRD 12)= Task 超时 → SIGTERM → 1s 后 SIGKILL; 用户取消批量操作时, 运行中进程终止, 已完成仓结果保留(MRD 10.6 状态表)。
- **重试**: 仅网络类错误(超时/DNS/连接拒绝)自动重试 1 次; 鉴权/非快进被拒等语义错误绝不重试。
- **环境透传**: 继承用户 shell 环境(PATH/SSH_AUTH_SOCK/HTTP(S)_PROXY); 自签证书通过仓库级 `git config http.sslCAInfo` 配置入口解决, **不提供"忽略证书校验"开关**(安全边界)。
- **大仓读取**: `git log --format=<自定义分隔符格式>` 流式解析; 默认时间窗口近 3 个月(可调, MRD 10.6 超大仓策略), 顶部提示"已按时间窗口截断"。

### 5.3 块级暂存管线(P0 关键路径)

1. `git diff --no-color`(工作区 vs 暂存区)→ 自研 unified diff 解析器拆 hunk(以 `diff --git` / `--- / +++` 头定位, 不依赖行内容猜测);
2. 勾选 hunk → 重组 patch 文件 → `git apply --cached --whitespace=nowarn -`;
3. 取消暂存: `git diff --cached` 拆块 → `git apply --cached --reverse -`;
4. 应用失败(文件已变更)= 索引陈旧 → 重新取 diff 并提示刷新, **绝不静默改写**;
5. 等价性保障: 测试用例直接对比"本产品暂存后 `git diff --cached`"与"`git add -p` 后 `git diff --cached`"(M0 验证项 B)。

### 5.4 合并与冲突

- 冲突检测: `git status --porcelain=v2` 解析 `Unmerged` 段(UU/AA/DD/AU/UA/DU/UD), 列表与 git 逐项一致;
- ours/theirs: `git checkout --ours / --theirs <path>` + `git add <path>`;
- "两者都保留": 直接从 index 读三路 stage(`git show :1/:2/:3:<path>` 分别为 base/ours/theirs), 写入标记化的合并预览, 用户确认后 `git add`;
- 收尾与中止: 全部解决才允许提交(逐文件状态驱动按钮); 随时 `git merge --abort`;
- 外部合并工具: `opendiff`(FileMerge)/ `ksdiff` / `code --wait --merge`, 可配置命令模板, 一键调用(MRD 10.2-E)。

---

## 6. 数据与存储

### 6.1 提交索引(SQLite / GRDB.swift)

50 仓 × 10 万提交 ≈ 500 万条元数据。"过滤 ≤300ms"在实时解析下不可能达成, 必须本地索引:

- 表: `commits`(repo_id, sha, parent_shas, author_name, author_email, author_ts, committer_ts, subject, refs_json, lane_hint), 按时间建索引; `repo_status`(分支/领先落后/未提交数); FTS5 虚表(提交信息全文检索, 支持卡片号如 `TASK-123456` 检索);
- 写入: `git log` 流式输出 → prepared statement 批量事务插入(SQLite 单事务可达约 100 万行/秒量级, 500 万行冷灌库 <60s, 与冷扫描预算同量级);
- 增量: 每次 fetch / commit / merge 后, 仅对受影响仓库执行 `git log <上次游标>..HEAD` 增量灌库(增量刷新 ≤5s 的主保障);
- **索引是派生数据**: 可随时删除重建, 不承载任何唯一真相; 真相永远在 git 仓库与 CLI 输出。

### 6.2 其他存储

| 数据 | 载体 | 说明 |
|---|---|---|
| 工作区配置(仓库列表, 多工作区) | JSON(Codable), `~/Library/Application Support/GitSpace/workspaces/*.json` | 可读可导出可手工备份, 满足"配置本地保存与恢复" |
| 应用设置 | UserDefaults(`AppStorage`) | 含并发度/外部工具/语言/统计开关 |
| 操作日志 | JSONL 按日滚动, 同目录 `logs/` | 每条: 时间/仓库/操作/结果/耗时; 破坏性操作记录确认者(MRD 10.2-G) |
| 提交图 lane 布局 | 内存缓存(索引加载时预计算) | 渲染零计算, 保障 55fps |
| 匿名统计 | 本地聚合计数器 → 每日批量上报 | 见第 11 章 |

---

## 7. 并发模型与文件监听

### 7.1 Swift Concurrency

- 每仓一个 `actor`(RepoExecutor): 同仓写操作天然串行, 杜绝并发 `git add` / `git commit` 互相踩踏;
- 批量操作: `TaskGroup` + 自研 `AsyncSemaphore(4)`, 并发度设置 1–8;
- UI 状态: `@Observable` 模型(依赖 macOS 14, 见第 3 章), 后台写索引 → 主线程仅收聚合后的状态快照;
- Swift 6 语言模式全仓开启: `Sendable` 边界由编译器兜底。

### 7.2 文件监听(50+ 仓的 FSEvents 折中)

- **一个工作区一条 FSEventStream**(监听工作区根目录, 非每仓一条), 避开 50+ 仓触及的上限问题(MRD 12/14);
- 回调内过滤排除目录(`build/`, `DerivedData/`, `Pods/`, `node_modules/` 等配置化名单), 去抖 500ms 合并事件 → 仅对受影响仓库刷新状态;
- **30s 低频轮询兜底**(轮询 `git status --porcelain` 轻量状态), 防止事件丢失导致状态陈旧; 阈值(M0 测定)与排除规则可在设置调整;
- 状态区始终标注"数据截至 fetch 时间"(MRD 10.4-3)。

---

## 8. 安全与凭据

| 项 | 方案 |
|---|---|
| HTTPS token | macOS Keychain(`kSecClassGenericPassword`), 读写走 Security framework 封装, **不落 UserDefaults/JSON, 不写日志** |
| SSH | 进程透传 `SSH_AUTH_SOCK`, 继承 `~/.ssh/config`; 不自实现 SSH 栈 |
| 鉴权失败 | 按仓库定位提示(失败原因 + 凭据配置入口, MRD 10.6 状态表) |
| 自签证书 | 仓库级 `http.sslCAInfo` 配置入口; 不提供跳过校验 |
| 破坏性防护 | 引擎层硬闸: 代码中不存在 `push --force` 调用路径; `reset --hard` / `clean -fd` 仅在显式二次确认对话框路径出现(丢弃改动); 全部写操作进 JSONL 操作日志 |
| 崩溃恢复 | 启动时检测各仓 MERGE_HEAD 等中间态, 呈现"合并进行中"并可中止(MRD 10.2-G"状态可解释") |

---

## 9. 架构分层与工程结构

```
GitSpace/
├── App/                          # 主 target: @main, 窗口/菜单/标签页, 依赖注入
└── Packages/
    ├── GSDesignKit/              # 设计令牌, Liquid Glass 封装(26/27 分层), 主题, 双语, 无障碍
    ├── GSGitEngine/              # GitProcessRunner, porcelain 解析器, diff/blame 模型, hunk 暂存管线
    ├── GSIndex/                  # 扫描器(父目录 50 仓发现), GRDB 索引, FTS5, 图 lane 布局
    ├── GSFeatures/
    │   ├── Timeline/             # 跨仓时间线, 过滤, 提交详情
    │   ├── Sync/                 # fetch/pull/push, 批量面板, 预检
    │   ├── Staging/              # 改动视图, 文件/块级暂存, discard
    │   ├── BranchMerge/          # 分支管理, merge, 冲突列表与选边
    │   └── StashTag/
    ├── GSInfra/                  # KeychainService, 操作日志, TelemetrySink, Sparkle 接入, Settings
    └── GSTestSupport/            # git fixture 仓生成器, 性能基准工具
```

- 依赖方向单向: `App → Features → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra`;
- `GSGitEngine` 与 `GSIndex` 不 import SwiftUI——引擎可测试性优先;
- 模块边界即编译边界, 50 人月级代码量下保住增量编译速度。

---

## 10. 关键技术方案 ↔ MRD 验收映射(MRD 10.4 逐条)

| # | 验收条目 | 技术保障 |
|---|---|---|
| 1 | 50 仓冷扫描 60s / 增量 ≤5s / 重启恢复 | 并行扫描(TaskGroup, 并发 8; 单仓 rev-parse+log-1 约 100ms)+ 流式索引灌库; 配置 JSON 恢复 |
| 2 | 首屏 ≤3s / 过滤 ≤300ms / 55fps / ≤500MB | SQLite 索引 + FTS5(过滤是索引查询)+ `List` 虚拟化 + `Canvas`(滚动零布局计算)+ 索引按窗口截断(内存受控) |
| 3 | 状态准确(与 `git status --porcelain` / `rev-list --count` 一致) | 状态数据**只来自 CLI 输出**, 不自算; 展示 fetch 时间戳 |
| 4 | 数据安全(只读操作零副作用 / 无 force) | 只读命令清单白名单(引擎层校验, 非白名单命令不受理读请求); 安全闸见第 8 章; `git reflog` 交叉校验进自动化测试 |
| 5 | 私有仓库兼容(HTTPS/SSH, GitHub/GitLab/Gerrit, 代理/自签) | CLI 继承全部传输配置; Gerrit 遵循 remote 配置(MRD 10.4-13) |
| 6 | 冷启动 ≤2s / 空载 ≤200MB / 包体 ≤60MB | 启动只恢复工作区配置(异步灌索引); 空载仅常驻引擎与最小索引连接; 纯原生栈 + 系统 git 不内置, universal 二进制约 20–30MB |
| 7 | 崩溃率 <0.5% / 单仓失败不阻塞 | 每仓 actor 隔离, 单仓 panic 只影响自身; 本地崩溃日志留存可导出 |
| 8 | 零门槛 | 无登录无许可, 全功能开放(开源模式决定) |
| 9 | 批量同步准确性 | 批量 = 逐仓 CLI 调用, 与命令行逐条执行天然一致; 抽样比对进 CI |
| 10 | 提交链路(暂存 ≡ `add -p`, 钩子不吞错) | 5.3 管线 + CLI 原生钩子执行 + 等价性测试 |
| 11 | 分支安全(改动阻塞切换, 未合并删除强确认) | 切换前 `git status --porcelain` 非空则走 stash 引导; 删除前 `git branch --merged` 判定 + 强确认 |
| 12 | 合并与冲突(列表/选边/中止与 git 一致) | 5.4 方案; 中止后 `reflog` + `status` 校验进测试 |
| 13 | push 安全(被拒不自动合并, 不 force, 确认数一致) | 非快进被拒原样呈现 git 错误; 确认弹窗数据取自引擎预检结果 |

---

## 11. 第三方依赖与许可兼容(开源前提)

| 依赖 | 版本 | 许可 | 用途 | Apache 2.0 兼容 |
|---|---|---|---|---|
| GRDB.swift | 7.x | MIT | SQLite 索引 + FTS5 | ✅ |
| Sparkle | 2.x | MIT | 自动更新(校验 EdDSA 签名) | ✅ |
| swift-tree-sitter + 语法包 | 按需, P1 引入 | MIT | diff/文件语法高亮 | ✅(逐语法包核查, 均为 MIT/Unlicense 系) |
| gitoxide(备选) | 未引入 | Apache-2.0 OR MIT | 未来读取层优化候选 | ✅ |
| **明确不引入** | — | — | 闭源 SDK(如 Firebase 类统计), GPLv2 无例外库(裸 libgit2 为 GPLv2+linking exception, 可用但本方案不需要) | — |

**匿名统计(对应 MRD 17.2-5, 建议方案)**: **自建最小化收集端**, 客户端自研上报器(约 200 行, `TelemetrySink` 协议抽象, 先落本地文件、远端后接), 不引第三方分析 SDK——开源工具引闭源 SDK 会直接打击"可审计"人设; 事件字段严格按 MRD 10.7 白名单(仓库数区间/功能计数/崩溃堆栈), 随机 UUID 存 Keychain 可重置, 90 天保留。最终是否自建 or 用现成服务, 随 MRD 待定项一并评审。

---

## 12. 构建、签名与分发

| 项 | 方案 |
|---|---|
| CI | GitHub Actions(`macos-26`/`macos-27` runner): PR 构建 + 测试 + 性能基准回归; tag 触发发布 |
| 签名公证 | Developer ID Application 证书 + `notarytool` 公证 + staple(MRD 12: 无签名 Gatekeeper 直接拦截) |
| 产物 | DMG(universal: arm64 + x86_64)+ Sparkle appcast(EdDSA 签名, appcast 托管 GitHub Pages) |
| 渠道 | GitHub Releases + Homebrew Cask(MRD 12) |
| 可复现构建 | CI 记录 Xcode 版本/依赖锁定(SPM `Package.resolved`), 发布产物附构建号 |

---

## 13. 测试与质量保障

- **单测**: Swift Testing(Xcode 27 内置框架)为主; porcelain 解析器/索引/hunk 暂存管线是重点覆盖对象;
- **集成测试**: `GSTestSupport` 提供脚本化 git fixture 仓生成器(可产出指定拓扑/冲突/钩子场景的临时仓库), 用例直接断言"本产品结果 ≡ git 基准"(验收 10/11/12/13 的自动化形态);
- **性能基准**: 模拟 50 仓 × 10 万提交数据集(生成脚本), CI 夜间跑首屏/过滤/滚动帧率/内存四项, 回归即告警;
- **UI 测试**: XCUITest 覆盖关键路径(扫描纳管→过滤→提交→冲突→中止);
- **崩溃率**: 本地 JSONL 崩溃日志, 用户可选随匿名统计上报(MRD 12)。

---

## 14. 性能预算与风险回退

| 风险 | 触发信号 | 回退路径(原生栈内部, 不引入 Web 层) |
|---|---|---|
| CLI 流式读取 50 仓 × 10 万提交不达 60s(M0 验证项 A) | M0 实测超时 | 引入 gitoxide FFI 作为**只读**优化层(索引灌库专用), 写操作仍走 CLI |
| SwiftUI 时间线滚动 <55fps | M0 验证项 D | 时间线整体下沉 AppKit(`NSTableView` + 自绘图列), 结构层不变 |
| TextKit 2 万行 diff 仍卡顿 | M2 实测 | 分页渲染(按 2000 行分块)+ 视口外降级为纯文本行 |
| 玻璃材质在低端机型功耗异常 | M3 实测 | 令牌层降级开关(L1 关闭), L0 基础层兜底 |
| Swift 6 严格并发改造量超预期 | M1 初期 | 对独立模块渐进降级到 Swift 5 模式 + `@preconcurrency`, 不影响架构 |

---

## 15. M0 技术验证清单(对应 MRD M0"一次性脚本验证")

| # | 验证项 | 通过口径 | 产出 |
|---|---|---|---|
| A | 50 仓模拟仓 + CLI 流式解析 + 索引灌库 | 冷扫描登记 + 灌库 ≤60s; 增量 ≤5s | 性能数据 → 决定是否需 gitoxide 读取层 |
| B | 块级暂存等价性 | 100 组随机多文件多 hunk 改动, 与 `git add -p` 的 `git diff --cached` 全量一致 | 解析器定稿 |
| C | FSEvents 阈值 | 50 仓工作区单流 + 排除规则下, 状态刷新延迟与 CPU 占用达标 | 轮询/去抖参数定稿 |
| D | 时间线渲染 | 500 万索引行下首屏 ≤3s, 滚动 ≥55fps(截断策略生效) | SwiftUI vs AppKit 路线定稿 |
| E | 冷启动拆解 | ≤2s(dyld + 配置恢复 + 首屏) | 启动预算分配 |

M0 结论回填本文档, 状态由 Draft 转 Ready。

---

## 16. 与 MRD 待定项的对齐(仅列技术相关)

| MRD 17.2 待定项 | 本文档立场 |
|---|---|
| git 引擎(libgit2 / gitoxide / 系统 git) | **建议系统 git CLI**(5.1), M0 数据确认后转正式决策 |
| 默认并发度 4 | M0/M1 用真实内网 Gerrit 压测后再定; 引擎参数已可配 1–8 |
| 统计后端 | 建议自建最小化收集端(第 11 章), 待评审 |
| 冲突解决深度 | P0 按"列表 + 选边 + 外部工具"; 引擎已直接读取三路 stage(5.4), 为 P1 内置合并编辑器预留了数据基础 |
| 开源许可 Apache 2.0 / MIT | 全部依赖同时兼容两者, 许可决策不阻塞技术栈 |

---

## 变更记录

- **v1.0(2026-10-29)**: 初稿。基于 MRD v2.0 的能力基线与 13 条验收标准制定; 核心决策: Swift 6.4 + Xcode 27, SwiftUI 主导 + AppKit 关键路径, macOS 27 Liquid Glass 分层适配, 系统 git CLI 为唯一执行引擎 + SQLite 索引, Swift Concurrency actor 模型, 全依赖 Apache 2.0 兼容。
