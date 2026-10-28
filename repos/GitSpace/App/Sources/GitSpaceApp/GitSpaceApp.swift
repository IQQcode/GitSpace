import SwiftUI
import GSFeatures

@main
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
}

/// SPM 可执行 target 直接运行时，把进程提升为常规 GUI 应用（Dock / 菜单栏）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
