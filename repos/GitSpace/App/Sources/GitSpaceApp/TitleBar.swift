import SwiftUI
import GSFeatures
import GSDesignKit

/// 顶部标题栏（对齐原型 titlebar）：品牌、工作区 pill、快速操作、主题、设置。
/// 横跨左右两栏顶部，macOS 红绿灯仍由系统标题栏提供。
struct TitleBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        HStack(spacing: GSSpacing.s) {
            brand
            workspacePill
            Spacer()
            paletteChip
            themeButton
            settingsButton
        }
        .padding(.horizontal, GSSpacing.m)
        .frame(height: 44)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.gs(.panelBorder)).frame(height: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.gs(.accent))
            Text("GitSpace").font(.headline)
        }
    }

    private var workspacePill: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.gs(.green)).frame(width: 7, height: 7)
            Text(app.workspace?.name ?? "GitSpace").font(.callout.weight(.medium))
            Text("\(app.repoCount) 个仓库").font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .help("当前工作区（本版本单工作区）")
    }

    private var paletteChip: some View {
        Button {
            app.isPaletteOpen = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                Text("快速操作").font(.callout)
                Text("⌘K")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("打开命令面板 (⌘K)")
    }

    private var themeButton: some View {
        Button(action: cycleTheme) {
            Image(systemName: themeIcon).font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .help("切换深浅色主题 (⌘⇧L)")
    }

    private var settingsButton: some View {
        Button { openSettings() } label: {
            Image(systemName: "gearshape").font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .help("设置")
    }

    private var themeIcon: String {
        switch appearance {
        case "light": return "sun.max"
        case "dark": return "moon"
        default: return "circle.lefthalf.filled"
        }
    }

    func cycleTheme() {
        switch appearance {
        case "system": appearance = "light"
        case "light": appearance = "dark"
        default: appearance = "system"
        }
    }
}
