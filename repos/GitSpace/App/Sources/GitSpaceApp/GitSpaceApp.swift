import SwiftUI
import GSFeatures
import GSMCP
import GSInfra

/// 进程入口（Story-1031-mcp）：
/// - `GitSpaceApp mcp-serve` → 以 stdio 运行 MCP server（GUI 不启动，stdout 为协议通道）；
/// - 其余 → 正常 GUI 启动，并后台安装/更新 git-spece skill。
@main
struct MainEntry {
    static func main() async {
        if CommandLine.arguments.contains("mcp-serve") {
            let server = MCPServer()
            do {
                try await server.run()
            } catch {
                FileHandle.standardError.write(Data("GitSpace MCP server 异常退出：\(error)\n".utf8))
                exit(1)
            }
            return
        }

        // GUI 模式：后台安装/更新 git-spece skill 到 ~/.agents/skills（失败不打断启动）。
        Task.detached(priority: .utility) {
            Self.installSkillIfNeeded()
        }
        await GitSpaceApp.main()
    }

    private static func installSkillIfNeeded() {
        guard let source = MCPSkillInstaller.bundleSkillDirectory() else { return }
        _ = try? MCPSkillInstaller.installIfNeeded(
            sourceDirectory: source,
            targetDirectory: MCPSkillInstaller.defaultTargetDirectory,
            manifestFile: GSPaths.skillInstallManifest
        )
    }
}

struct GitSpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup("GitSpace") {
            RootView()
                .environment(appModel)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 1180, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("操作") {
                Button("打开命令面板") { appModel.isPaletteOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("切换深浅色主题") { cycleAppearance() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()
                Button("添加仓库…") { appModel.activeSheet = .addRepo }
                    .keyboardShortcut("o", modifiers: .command)
                Button("扫描父目录…") { appModel.activeSheet = .scan }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("导入 mgit 清单…") { appModel.activeSheet = .importManifest }

                Divider()
                Button("新建 / 管理分支") { appModel.openRepoSheet(.branch) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("合并分支") { appModel.openRepoSheet(.merge) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("打开 Stash") { appModel.openRepoSheet(.stash) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("打开 Tag 管理") { appModel.openRepoSheet(.tag) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()
                Button("全部仓库 Fetch") { appModel.runBatch(.fetch, repos: appModel.repos) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("批量 Pull（选中待同步仓库）") { appModel.bulkPull() }
                Button("批量 Push（选中未推送仓库）") { appModel.bulkPush() }

                Divider()
                Button("查看统一时间线") { appModel.requestedTab = .timeline }
                    .keyboardShortcut("1", modifiers: .command)
                Button("查看提交") { appModel.requestedTab = .commit }
                    .keyboardShortcut("2", modifiers: .command)
                Button("查看多仓状态") { appModel.requestedTab = .status }
                    .keyboardShortcut("3", modifiers: .command)
                Button("查看变更集") { appModel.requestedTab = .changeset }
                    .keyboardShortcut("4", modifiers: .command)
                Button("查看聚合检索") { appModel.requestedTab = .search }
                    .keyboardShortcut("5", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(appModel)
                .preferredColorScheme(colorScheme)
                .frame(width: 460)
        }
    }
    private var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private func cycleAppearance() {
        switch appearance {
        case "system": appearance = "light"
        case "light": appearance = "dark"
        default: appearance = "system"
        }
    }
}

/// SPM 可执行 target 直接运行时，把进程提升为常规 GUI 应用（Dock / 菜单栏）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
