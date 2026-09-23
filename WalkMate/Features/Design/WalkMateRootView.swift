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
        // 底栏和页面上下排布，而不是盖在页面上：导航栈推入二级页时，
        // 推入的页面由 UIKit 承载，会盖住 ZStack 里「在上面」的底栏，导致底栏点不动
        VStack(spacing: 0) {
            Group {
                switch selection {
                case .home: HomeView(onStartTraining: { selection = .training })
                case .training: TrainingFlowView()
                case .community: CommunityView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            WalkMateTabBar(selection: $selection)
                .padding(.top, 6)
                .padding(.bottom, 8)
                // 读屏顺序上底栏排在页面内容之后：切换栏目后焦点会落到新页面的页头，而不是底栏第一个按钮
                .accessibilitySortPriority(-1)
        }
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // 字体大小只通过主题字体的缩放系数生效；切换栏目时页面重建即可拿到新字号
        .id(settings.textScale)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onChange(of: selection) { _, _ in AccessibilityFeedback.pageSwitched() }
        .fullScreenCover(isPresented: $showGuide) {
            OnboardingView { showGuide = false }
                .preferredColorScheme(.dark)
        }
    }
}
