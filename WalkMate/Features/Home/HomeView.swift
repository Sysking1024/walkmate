import SwiftUI

/// 首页。对应设计稿「home」画面。
///
/// 康复闭环来自本机训练记录；徽章与同伴进程为演示数据（社群首期用静态数据）。
struct HomeView: View {
    /// 点击「开始今天的训练」时切换到训练栏目
    let onStartTraining: () -> Void
    /// 点击「进入社群」时切换到社群栏目
    let onOpenCommunity: () -> Void

    @State private var history = TrainingHistoryStore.shared
    @State private var settings = AppSettings.shared
    @State private var showGrowth = false
    @State private var showGoals = false

    private var dailyGoalMinutes: Int { settings.dailyGoalMinutes }
    private var dailyGoalObstacles: Int { settings.dailyGoalObstacles }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    WMLogoHeader().padding(.top, 8)
                    heroCard
                    loopSection
                    badgeSection
                    peerSection
                }
                .wmPageInset()
                .wmTabBarClearance()
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showGrowth) { GrowthDetailView() }
            .navigationDestination(isPresented: $showGoals) { TrainingGoalView() }
        }
        .tint(WalkMateTheme.Colors.textPrimary)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("TODAY")
                Circle().fill(WalkMateTheme.Colors.textTint).frame(width: 3, height: 3)
                Text("今日训练")
            }
            .font(.system(size: 13.5))
            .foregroundStyle(WalkMateTheme.Colors.textTint)

            Text("从容迈步，探索随心。")
                .font(WalkMateTheme.Fonts.pageTitle)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)

            WMButton(title: "开始今天的训练", style: .hero, action: onStartTraining)
                .padding(.top, 8)
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard(WalkMateTheme.Gradients.hero)
        .overlay(alignment: .topTrailing) {
            Image("home_hero_glow")
                .resizable().scaledToFit()
                .frame(width: 120)
                .padding(.trailing, 20)
                .opacity(0.9)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 今日康复闭环

    private var todayMinutes: Int { history.minutesPerDay.last?.minutes ?? 0 }
    private var todayObstacles: Int {
        history.records.filter { Calendar.current.isDateInToday($0.finishedAt) }.reduce(0) { $0 + $1.obstaclesAvoided }
    }
    private var minutesProgress: Double { min(1, Double(todayMinutes) / Double(dailyGoalMinutes)) }
    private var obstaclesProgress: Double { min(1, Double(todayObstacles) / Double(dailyGoalObstacles)) }
    /// 今日完成度：时长与避障两项目标的平均
    private var todayProgress: Double { (minutesProgress + obstaclesProgress) / 2 }

    private var loopSection: some View {
        VStack(spacing: 12) {
            WMSectionHeader(title: "今日康复闭环", action: "查看成长") { showGrowth = true }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    WMRing(progress: minutesProgress, value: "\(todayMinutes)", caption: "分钟")
                    Spacer()
                    WMRing(progress: obstaclesProgress, value: "\(todayObstacles)", caption: "避障")
                    Spacer()
                    WMRing(progress: todayProgress, value: "\(Int(todayProgress * 100))%", caption: "完成")
                }
                Text(encouragement)
                    .font(WalkMateTheme.Fonts.body)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                Button { showGoals = true } label: {
                    HStack(spacing: 6) {
                        Text("今日目标：\(dailyGoalMinutes) 分钟 · 避障 \(dailyGoalObstacles) 次")
                        Spacer()
                        Text("调整")
                        Image("icon_chevron").resizable().scaledToFit().frame(height: 10)
                    }
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("今日目标，\(dailyGoalMinutes) 分钟，避障 \(dailyGoalObstacles) 次")
                .accessibilityHint("轻点两下调整目标")
            }
            .padding(WalkMateTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wmCard()
        }
    }

    private var encouragement: String {
        if todayMinutes == 0 { return "今天还没开始，先来一次室内训练吧" }
        if todayProgress >= 1 { return "今日目标已完成，明天继续" }
        if todayProgress >= 0.5 { return "加油~  已经快完成今日训练项目啦" }
        return "已经开始了，再练 \(dailyGoalMinutes - todayMinutes) 分钟就完成今日目标"
    }

    private var badgeSection: some View {
        VStack(spacing: 12) {
            WMSectionHeader(title: "我的徽章")
            HStack(spacing: 8) {
                badgeTile("badge_obstacles_10", "成功避障十次")
                badgeTile("badge_first_step", "首次完成训练")
                badgeTile("badge_meet_friend", "成功和朋友会面")
            }
        }
    }

    private func badgeTile(_ image: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(image).resizable().scaledToFit().frame(height: 66)
            Text(title)
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 110)
        .wmCard(WalkMateTheme.Gradients.badgeTile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("徽章，\(title)")
    }

    private var peerSection: some View {
        VStack(spacing: 12) {
            WMSectionHeader(title: "同伴进程", action: "进入社群", onAction: onOpenCommunity)
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.25))
                    Text("M").font(.system(size: 28, weight: .medium)).foregroundStyle(.white)
                }
                .frame(width: 57, height: 57)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ming  解锁了").font(WalkMateTheme.Fonts.body)
                    (Text("「第100次」").font(.system(size: 18, weight: .medium)) + Text("避障成功").font(WalkMateTheme.Fonts.body))
                }
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                Spacer()
            }
            .padding(WalkMateTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .wmCard()
            .accessibilityElement(children: .combine)
        }
    }
}
