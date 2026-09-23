import SwiftUI

// 通用组件。全部从 Figma「WalkMate UI」的重复元素里提炼，页面只做拼装。

/// 渐变卡片背景
struct WMCardBackground: ViewModifier {
    var gradient: LinearGradient = WalkMateTheme.Gradients.card
    var radius: CGFloat = WalkMateTheme.Radius.card
    var dimmed = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    gradient
                    // 锁定态整体压暗，对应设计稿里叠加的灰色层
                    if dimmed { Color(hex: 0x636363).opacity(0.2) }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func wmCard(_ gradient: LinearGradient = WalkMateTheme.Gradients.card,
                radius: CGFloat = WalkMateTheme.Radius.card,
                dimmed: Bool = false) -> some View {
        modifier(WMCardBackground(gradient: gradient, radius: radius, dimmed: dimmed))
    }

    /// 页面统一左右留白
    func wmPageInset() -> some View {
        padding(.horizontal, WalkMateTheme.Layout.horizontalInset)
    }

    /// 页面滚动内容的底部留白：底栏悬浮在内容之上，最后一个控件要能完整滚出底栏
    func wmTabBarClearance() -> some View {
        padding(.bottom, WalkMateTheme.Layout.tabBarHeight + 36)
    }
}

/// 页面顶部的 logo
struct WMLogoHeader: View {
    var body: some View {
        Image("logo_wordmark")
            .resizable()
            .scaledToFit()
            .frame(width: 172, height: 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 29)
            .accessibilityLabel("伴行 WalkMate")
            .accessibilityAddTraits(.isHeader)
    }
}

/// 页面大标题
struct WMPageTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(WalkMateTheme.Fonts.pageTitle)
            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 区块标题，右侧可带一个文字动作
struct WMSectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(WalkMateTheme.Fonts.sectionTitle)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action: { onAction?() }) {
                    Text(action)
                        .font(WalkMateTheme.Fonts.body)
                        .foregroundStyle(Color.white.opacity(0.54))
                        .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 主按钮。三种样式覆盖设计稿里出现的全部按钮。
struct WMButton: View {
    enum Style {
        /// 绿色渐变（大部分动作）
        case primary
        /// 首页欢迎卡内的按钮
        case hero
        /// 白底深绿字（当前档位的「开始训练」）
        case white
        /// 灰底浅灰字（锁定档位的「查看要求」、次要动作）
        case subdued
    }

    let title: String
    var style: Style = .primary
    var height: CGFloat = 59
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WalkMateTheme.Fonts.body)
                .tracking(1.6)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: max(height, WalkMateTheme.Layout.minimumTapTarget))
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary, .hero: return WalkMateTheme.Colors.textPrimary
        case .white: return WalkMateTheme.Colors.onWhiteAccent
        case .subdued: return WalkMateTheme.Colors.textMuted
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary: WalkMateTheme.Gradients.primaryButton
        case .hero: WalkMateTheme.Gradients.heroButton
        case .white: Color.white.opacity(0.8)
        case .subdued: Color.black.opacity(0.2)
        }
    }
}

/// 环形统计：中间数值，下方小字说明
struct WMRing: View {
    /// 进度 0 到 1
    let progress: Double
    let value: String
    let caption: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(WalkMateTheme.Colors.ringTrack, lineWidth: 11)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(WalkMateTheme.Colors.ringFill, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(value)
                    .font(WalkMateTheme.Fonts.statValue)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                Text(caption)
                    .font(WalkMateTheme.Fonts.ringCaption)
                    .foregroundStyle(WalkMateTheme.Colors.textSecondary)
            }
        }
        .frame(width: WalkMateTheme.Layout.ringDiameter, height: WalkMateTheme.Layout.ringDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption)，\(value)")
    }
}

/// 统计块：小字标题在上，大字数值在下，可选右侧附注（如涨幅）
struct WMStatTile: View {
    let label: String
    let value: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textSecondary)
                Text(value)
                    .font(WalkMateTheme.Fonts.statValueLarge)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if let trailing {
                HStack(spacing: 4) {
                    Image("icon_trend_up").resizable().scaledToFit().frame(width: 15, height: 16)
                    Text(trailing)
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 79, alignment: .leading)
        .wmCard(WalkMateTheme.Gradients.statTile, radius: WalkMateTheme.Radius.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)，\(value)\(trailing.map { "，较上次 \($0)" } ?? "")")
    }
}

/// 从左到右排列、放不下就换行的布局，用于标签组
struct WMFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard let width = proposal.width, width.isFinite else {
            // 未给宽度时：理想宽度取最宽的一枚，高度按每枚一行估算
            let widest = sizes.map(\.width).max() ?? 0
            let height = sizes.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(0, sizes.count - 1))
            return CGSize(width: widest, height: height)
        }
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 浅绿小标签（探店特性等）
struct WMChip: View {
    let text: String
    var selected = true

    var body: some View {
        Text(text)
            .font(WalkMateTheme.Fonts.chip)
            .tracking(0.7)
            .lineLimit(1)
            .foregroundStyle(selected ? WalkMateTheme.Colors.chipText : WalkMateTheme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? WalkMateTheme.Colors.chipBackground : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.chip, style: .continuous))
    }
}

/// 圆形头像
struct WMAvatar: View {
    let imageName: String
    var size: CGFloat = 64

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}
