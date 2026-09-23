import SwiftUI

/// 设计 token，来源为 Figma「WalkMate UI」文件。
///
/// 所有颜色、渐变、圆角、字号均直接取自设计稿，页面代码只引用此处的常量，
/// 不在各处散写十六进制值，设计调整时只改这一个文件。
enum WalkMateTheme {

    // MARK: - 颜色

    enum Colors {
        /// 全局底色
        static let background = Color.black
        /// 正文
        static let textPrimary = Color(hex: 0xF5F7F6)
        /// 次要文字（说明、单位、未选中的标签）
        static let textSecondary = Color(hex: 0x8F9A95)
        /// 锁定项文字
        static let textMuted = Color(hex: 0xB3B3B3)
        /// 首页顶部小标签
        static let textTint = Color(hex: 0xC9E2D7)
        /// 白色按钮上的深绿文字
        static let onWhiteAccent = Color(hex: 0x113719)
        /// 强调绿（里程碑已达成、正向变化）
        static let accent = Color(hex: 0x10E47A)
        /// 柔和强调绿（徽章解锁提示）
        static let accentSoft = Color(hex: 0x76FFBB)
        /// 环形统计与进度条的绿
        static let ringFill = Color(hex: 0x3DA85A)
        /// 环形统计轨道
        static let ringTrack = Color.white.opacity(0.15)
        /// 滑杆轨道与滑块
        static let sliderTrack = Color(hex: 0x176E29)
        static let sliderFill = Color(hex: 0xE3E7E4)
        /// 底栏底板
        static let tabBar = Color(hex: 0x151616)
        /// 标签 chip 底色与文字
        static let chipBackground = Color(hex: 0xCBE8D1).opacity(0.75)
        static let chipText = Color(hex: 0x0F381B)
        /// 分段选择：选中 / 未选中
        static let segmentSelected = Color(red: 73 / 255, green: 178 / 255, blue: 94 / 255).opacity(0.6)
        static let segmentUnselected = Color(red: 162 / 255, green: 175 / 255, blue: 165 / 255).opacity(0.4)
        static let segmentText = Color(hex: 0xCCCCCC)
        /// 分隔线
        static let divider = Color.white.opacity(0.12)
    }

    // MARK: - 渐变

    enum Gradients {
        /// 首页顶部欢迎卡
        static let hero = vertical((27, 113, 44, 0.2), (115, 115, 115, 0.2))
        /// 通用内容卡
        static let card = vertical((41, 106, 54, 0.2), (231, 231, 231, 0.2))
        /// 当前可进行的训练档位
        static let activeLevel = vertical((31, 125, 50, 0.5), (153, 240, 170, 0.46))
        /// 主按钮
        static let primaryButton = vertical((73, 178, 94, 0.4), (64, 222, 96, 0.4))
        /// 首页欢迎卡内的按钮
        static let heroButton = vertical((52, 171, 76, 0.4), (96, 199, 116, 0.4))
        /// 徽章方块
        static let badgeTile = vertical((217, 217, 217, 0.2), (39, 106, 52, 0.2))
        /// 社群卡
        static let communityCard = vertical((134, 255, 158, 0.2), (196, 196, 196, 0.2))
        /// 探店卡（更亮）
        static let storeCard = vertical((126, 215, 144, 0.4), (255, 255, 255, 0.4))
        /// 底栏高亮胶囊
        static let tabPill = LinearGradient(
            colors: [Color(hex: 0x62B674), Color(hex: 0x2E8C41)],
            startPoint: .top, endPoint: .bottom
        )
        /// 统计块：三段渐变
        static let statTile = LinearGradient(
            stops: [
                .init(color: Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255).opacity(0.2), location: 0),
                .init(color: Color(red: 125 / 255, green: 160 / 255, blue: 132 / 255).opacity(0.17), location: 0.77),
                .init(color: Color(red: 91 / 255, green: 122 / 255, blue: 97 / 255).opacity(0.2), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        /// 视频封面底部压暗
        static let coverShade = LinearGradient(
            stops: [.init(color: .clear, location: 0.48), .init(color: .black.opacity(0.3), location: 0.79)],
            startPoint: .top, endPoint: .bottom
        )

        private static func vertical(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double)) -> LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: a.0 / 255, green: a.1 / 255, blue: a.2 / 255).opacity(a.3),
                    Color(red: b.0 / 255, green: b.1 / 255, blue: b.2 / 255).opacity(b.3),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - 圆角与尺寸

    enum Radius {
        static let card: CGFloat = 25
        static let tile: CGFloat = 18
        static let button: CGFloat = 15
        static let chip: CGFloat = 8
    }

    enum Layout {
        /// 页面左右留白
        static let horizontalInset: CGFloat = 22
        /// 卡片内边距
        static let cardPadding: CGFloat = 21
        /// 触控目标下限（宪章原则四）
        static let minimumTapTarget: CGFloat = 48
        /// 环形统计直径
        static let ringDiameter: CGFloat = 86
        /// 底栏尺寸
        static let tabBarHeight: CGFloat = 73
    }

    // MARK: - 字体

    enum Fonts {
        /// 由设置页「字体大小」调整的整体缩放系数
        static var scale: CGFloat = 1

        private static func scaled(_ size: CGFloat, _ weight: Font.Weight) -> Font {
            .system(size: (size * scale).rounded(), weight: weight)
        }

        static var pageTitle: Font { scaled(24, .bold) }
        static var sectionTitle: Font { scaled(20, .bold) }
        static var statValue: Font { scaled(18, .bold) }
        static var statValueLarge: Font { scaled(20, .bold) }
        static var body: Font { scaled(16, .medium) }
        static var caption: Font { scaled(13, .medium) }
        static var small: Font { scaled(11, .bold) }
        static var ringCaption: Font { scaled(10, .medium) }
        static var chip: Font { scaled(11, .medium) }
    }
}

extension Color {
    /// 用十六进制整数建色，便于逐一对照设计稿
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
