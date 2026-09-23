import SwiftUI

/// 根视图：黑色底 + 五个栏目 + 自定义底栏。
///
/// 训练流程（列表 → 训练中 → 总结）在训练栏内以导航栈推进，底栏保持可见，与设计稿一致。
struct WalkMateRootView: View {
    @State private var selection: WalkMateTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            WalkMateTheme.Colors.background.ignoresSafeArea()

            Group {
                switch selection {
                case .home: HomeView(onStartTraining: { selection = .training })
                case .training: TrainingFlowView()
                case .progress: GrowthView()
                case .community: CommunityView()
                case .profile: ProfileView()
                }
            }
            // 给底栏留出空间，避免内容被遮挡
            .safeAreaPadding(.bottom, WalkMateTheme.Layout.tabBarHeight + 12)

            WalkMateTabBar(selection: $selection)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
    }
}
