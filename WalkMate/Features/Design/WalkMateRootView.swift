import SwiftUI

/// 根视图：黑色底 + 五个栏目 + 自定义底栏。
///
/// 底栏悬浮在内容之上，各页面滚动内容用 `wmTabBarClearance()` 留出底部空间，
/// 保证最后一个按钮能完整滚出底栏。训练流程在训练栏内以导航栈推进，底栏保持可见。
struct WalkMateRootView: View {
    @State private var selection: WalkMateTab = .home
    @State private var settings = AppSettings.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            WalkMateTheme.Colors.background.ignoresSafeArea()

            Group {
                switch selection {
                case .home:
                    HomeView(onStartTraining: { selection = .training }, onOpenCommunity: { selection = .community })
                case .training:
                    TrainingFlowView(onViewGrowth: { selection = .progress })
                case .progress: GrowthView()
                case .community: CommunityView()
                case .profile: ProfileView()
                }
            }

            WalkMateTabBar(selection: $selection)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        // 字体大小设置改动时，环境变化会让整棵视图树重新求值，主题字体的缩放随之生效
        .dynamicTypeSize(settings.dynamicTypeSize)
    }
}
