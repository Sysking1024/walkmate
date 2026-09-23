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
        // 字体大小只通过主题字体的缩放系数生效；切换栏目时页面重建即可拿到新字号
        .id(settings.textScale)
        .fullScreenCover(isPresented: $showGuide) {
            OnboardingView { showGuide = false }
                .preferredColorScheme(.dark)
        }
    }
}
