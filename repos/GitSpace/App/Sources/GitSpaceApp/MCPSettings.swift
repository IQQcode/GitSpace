import SwiftUI
import GSMCP
import GSInfra

/// 设置页「MCP 与 Agent」区块（Story-1031-mcp；范围待评审，口径见 specs/Story-1031-mcp-git-skill/doc.md §3.8）。
struct MCPSettingsSection: View {
    @State private var writesEnabled: Bool
    @State private var skillVersionText: String = "…"
    @State private var copied = false
    @State private var lastActionMessage: String?

    init() {
        _writesEnabled = State(initialValue: MCPAppConfig.load().mcpWritesEnabled)
    }

    var body: some View {
        Section("MCP 与 Agent（待评审）") {
            LabeledContent("MCP server", value: "GitSpaceApp mcp-serve（随装可用）")

            HStack {
                Text("MCP 配置")
                Spacer()
                Button(copied ? "已复制" : "复制") {
                    copyMCPConfig()
                    copied = true
                }
                .disabled(copied)
            }

            Toggle("允许 MCP 写操作", isOn: $writesEnabled)
                .onChange(of: writesEnabled) { _, newValue in
                    var config = MCPAppConfig.load()
                    config.mcpWritesEnabled = newValue
                    try? config.save()
                }

            LabeledContent("git-spece skill", value: skillVersionText)
            HStack {
                Button("安装 / 更新 skill") {
                    installSkill()
                }
                Button("打开 skill 目录") {
                    NSWorkspace.shared.open(MCPSkillInstaller.defaultTargetDirectory)
                }
            }

            if let message = lastActionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("skill 安装到 ~/.agents/skills/git-spece（Agent 平台通用 SSOT）；启动时自动随版本更新。其他平台私有目录（如 ~/.claude/skills）可用 skill-unify sync 一次性链接同步。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshSkillState)
    }

    private func refreshSkillState() {
        if let manifest = MCPSkillInstaller.installedManifest(at: GSPaths.skillInstallManifest) {
            skillVersionText = "已装 v\(manifest.version)"
        } else {
            skillVersionText = "未安装"
        }
    }

    private func installSkill() {
        guard let source = MCPSkillInstaller.bundleSkillDirectory() else {
            lastActionMessage = "Bundle 内未找到 skill 资源"
            return
        }
        do {
            let installed = try MCPSkillInstaller.installIfNeeded(
                sourceDirectory: source,
                targetDirectory: MCPSkillInstaller.defaultTargetDirectory,
                manifestFile: GSPaths.skillInstallManifest,
                force: true
            )
            refreshSkillState()
            lastActionMessage = installed ? "已安装 / 更新" : "已是最新版本"
        } catch {
            lastActionMessage = "安装失败：\(error.localizedDescription)"
        }
    }

    private func copyMCPConfig() {
        let executablePath = Bundle.main.executableURL?.path
            ?? CommandLine.arguments.first
            ?? "GitSpaceApp"
        let json = """
        {
          "mcpServers": {
            "gitspace": {
              "command": "\(executablePath)",
              "args": ["mcp-serve"]
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }
}