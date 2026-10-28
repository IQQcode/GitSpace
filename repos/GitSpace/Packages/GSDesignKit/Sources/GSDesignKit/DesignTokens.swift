import SwiftUI

/// 设计令牌单点收敛（TechStack §4.2）：界面代码只引用令牌，不直接写颜色/材质字面量。
/// 取色基准来自交互原型 `design/gitspace-prototype/index-origin.html` 的深浅两套主题。
public enum GSColor {
    case accent
    case green
    case amber
    case red
    case purple
    case textMuted
    case textFaint
    case panelBorder
}

public extension Color {
    static func gs(_ role: GSColor, dark: Bool = true) -> Color {
        switch role {
        case .accent: dark ? Color(red: 0.435, green: 0.553, blue: 1.0) : Color(red: 0.247, green: 0.388, blue: 0.941)
        case .green: dark ? Color(red: 0.239, green: 0.863, blue: 0.592) : Color(red: 0.059, green: 0.616, blue: 0.420)
        case .amber: dark ? Color(red: 0.957, green: 0.698, blue: 0.361) : Color(red: 0.761, green: 0.486, blue: 0.090)
        case .red: dark ? Color(red: 1.0, green: 0.420, blue: 0.506) : Color(red: 0.839, green: 0.227, blue: 0.318)
        case .purple: dark ? Color(red: 0.780, green: 0.553, blue: 1.0) : Color(red: 0.545, green: 0.310, blue: 0.847)
        case .textMuted: dark ? Color(red: 0.545, green: 0.592, blue: 0.663) : Color(red: 0.388, green: 0.439, blue: 0.541)
        case .textFaint: dark ? Color(red: 0.357, green: 0.400, blue: 0.471) : Color(red: 0.596, green: 0.639, blue: 0.714)
        case .panelBorder: dark ? Color(red: 0.133, green: 0.169, blue: 0.216) : Color(red: 0.867, green: 0.894, blue: 0.933)
        }
    }

    static func gs(_ role: GSColor, scheme: ColorScheme) -> Color {
        gs(role, dark: scheme == .dark)
    }
}

/// 仓库与提交图的固定色板（原型 lane 色系）。
public enum GSPalette {
    /// 原型中的仓库/作者配色槽位，按索引循环取用。
    public static let palette: [Color] = [
        Color(red: 0.435, green: 0.553, blue: 1.0),   // 蓝
        Color(red: 0.239, green: 0.863, blue: 0.592), // 绿
        Color(red: 0.957, green: 0.698, blue: 0.361), // 琥珀
        Color(red: 0.780, green: 0.553, blue: 1.0),   // 紫
        Color(red: 0.361, green: 0.788, blue: 0.910), // 青
        Color(red: 1.0, green: 0.561, blue: 0.639),   // 粉
        Color(red: 0.910, green: 0.769, blue: 0.416), // 黄
        Color(red: 0.561, green: 0.827, blue: 0.659)  // 薄荷
    ]

    public static func color(forSlot index: Int) -> Color {
        palette[abs(index) % palette.count]
    }

    /// 按名称稳定散列到色板，保证同一仓库每次启动颜色一致。
    public static func color(forName name: String) -> Color {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return color(forSlot: Int(hash % UInt64(palette.count)))
    }
}

public extension Font {
    /// 等宽字体：SHA / 路径 / diff 使用。
    static let gsMono = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let gsMonoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
}

public enum GSSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum GSGraph {
    public static let laneWidth: CGFloat = 12
    public static let laneOffset: CGFloat = 14
    public static let nodeRadius: CGFloat = 4.2
    public static let rowHeight: CGFloat = 54
}
