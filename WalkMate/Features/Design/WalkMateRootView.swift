import SwiftUI

/// 根视图：黑色底 + 五个栏目 + 自定义底栏。
///
/// 底栏悬浮在内容之上，各页面滚动内容用 `wmTabBarClearance()` 留出底部空间，
/// 保证最后一个按钮能完整滚出底栏。训练流程在训练栏内以导航栈推进，底栏保持可见。
struct WalkMateRootView: View {
    @State private var selection: WalkMateTab = .home
    @State private var settings = AppSettings.shared
    @State private var showGuide = !AppSettings.shared.hasSeenGuide

    var body: some View {
        ZStack(alignment: .bottom) {
            WalkMateTheme.Colors.background.ignoresSafeArea()

            Group {
                switch selection {
                case .home: HomeView(onStartTraining: { selection = .training })
                case .training: TrainingFlowView()
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
        .fullScreenCover(isPresented: $showGuide) {
            OnboardingView { showGuide = false; announceCurrentTab() }
                .preferredColorScheme(.dark)
        }
        .onAppear { if !showGuide { announceCurrentTab() } }
        .onChange(of: selection) { _, _ in announceCurrentTab() }
    }

    // MARK: - 页面朗读

    private func announceCurrentTab() {
        PageNarrator.shared.announce(summary(for: selection))
    }

    /// 每个栏目进入时只说页名和第一个动作，让人马上知道往哪里按
    private func summary(for tab: WalkMateTab) -> String {
        switch tab {
        case .home: return "首页，开始今天的训练。"
        case .training: return "训练，室内适应，开始训练。"
        case .community: return "社群，查看路线。"
        case .profile: return "个人，设置。"
        }
    }
}
