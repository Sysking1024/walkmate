import SwiftUI

/// 根视图：黑色底 + 五个栏目 + 自定义底栏。
///
/// 底栏悬浮在内容之上，各页面滚动内容用 `wmTabBarClearance()` 留出底部空间，
/// 保证最后一个按钮能完整滚出底栏。训练流程在训练栏内以导航栈推进，底栏保持可见。
struct WalkMateRootView: View {
    @State private var selection: WalkMateTab = .home
    @State private var settings = AppSettings.shared
    @State private var history = TrainingHistoryStore.shared
    @State private var community = CommunityStore.shared
    @State private var showGuide = !AppSettings.shared.hasSeenGuide

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

    /// 每个栏目进入时说的话：这页是什么、现在的数据、能做什么
    private func summary(for tab: WalkMateTab) -> String {
        switch tab {
        case .home:
            let minutes = history.minutesPerDay.last?.minutes ?? 0
            let obstacles = history.records.filter { Calendar.current.isDateInToday($0.finishedAt) }.reduce(0) { $0 + $1.obstaclesAvoided }
            let progress = min(1, (min(1, Double(minutes) / Double(settings.dailyGoalMinutes)) + min(1, Double(obstacles) / Double(settings.dailyGoalObstacles))) / 2)
            return "首页。今天已训练 \(minutes) 分钟，避障 \(obstacles) 次，完成 \(Int(progress * 100))%。最上面是「开始今天的训练」按钮。"
        case .training:
            let semi = history.isSemiOpenUnlocked ? "半开放环境已解锁" : "半开放环境还没解锁"
            return "训练。室内适应可以开始，\(semi)，户外独立出行还没解锁。每个档位一个按钮。"
        case .progress:
            return "进度。本周训练 \(history.trainingDaysThisWeek) 天，避障 \(history.obstaclesThisWeek) 次，独立完成 \(Int(history.independentRate * 100))%。下面是小区路线和室内训练路线。"
        case .community:
            let invite = community.feed.invitations.first { $0.status == nil }.map { "\($0.from) 邀你一起去\($0.place)，可以同意或拒绝。" } ?? ""
            return "社群。好友今日成就，两家无障碍探店可以查看路线和评分。\(invite)"
        case .profile:
            return "个人与设置。可以调语音引导、语速、字体大小和训练目标，还有帮助和关于我们。"
        }
    }
}
