import SwiftUI

/// 应用的五个主栏目
enum WalkMateTab: CaseIterable, Identifiable {
    case home, training, community, profile

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "首页"
        case .training: return "训练"
        case .community: return "社群"
        case .profile: return "个人"
        }
    }
}

/// 自定义底栏，复刻设计稿：深色底板、选中项带绿色胶囊。
///
/// 无障碍：每个栏目是一个原生按钮，带「已选中」特征；胶囊与图标对读屏隐藏。
struct WalkMateTabBar: View {
    @Binding var selection: WalkMateTab

    var body: some View {
        let tabs = WalkMateTab.allCases
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        icon(for: tab)
                            .frame(height: 20)
                        Text(tab.title)
                            .font(WalkMateTheme.Fonts.small)
                    }
                    .foregroundStyle(selection == tab ? Color.white : WalkMateTheme.Colors.textSecondary)
                    .frame(width: 61, height: 56)
                    // 选中胶囊用透明度切换而不是增删视图：视图结构一变，读屏元素会被重建，
                    // VoiceOver 丢了焦点就会跳回容器里的第一个（首页）并念一遍
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(WalkMateTheme.Gradients.tabPill)
                            .opacity(selection == tab ? 1 : 0)
                    }
                    // 整个栏目列都是触控与读屏选中区域，不只是中间的胶囊
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(tab)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tab.title)
                // 仿系统标签栏的播报：「四之三」
                .accessibilityValue("\(Self.chineseNumber(tabs.count))之\(Self.chineseNumber(index + 1))")
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: WalkMateTheme.Layout.tabBarHeight)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(WalkMateTheme.Colors.tabBar)
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1))
        )
        .padding(.horizontal, 10)
    }

    private static func chineseNumber(_ value: Int) -> String {
        ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"][min(9, max(0, value))]
    }

    /// 设计稿里训练栏用的是字符图形，其余为矢量图标
    @ViewBuilder
    private func icon(for tab: WalkMateTab) -> some View {
        switch tab {
        case .home:
            Image("tab_home").resizable().scaledToFit()
        case .training:
            Text("◎").font(.system(size: 18, weight: .bold))
        case .community:
            Image("tab_community").resizable().scaledToFit()
        case .profile:
            Image("tab_settings").resizable().scaledToFit()
        }
    }
}
