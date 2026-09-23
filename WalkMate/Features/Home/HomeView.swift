import SwiftUI

/// 首页：开始训练、今日任务清单、本周、我的路线、徽章。进度页已并入这里。
///
/// 读屏顺序：开始训练按钮排第一；任务清单一行一项；本周一个元素；路线两行。
struct HomeView: View {
    /// 点击「开始今天的训练」时切换到训练栏目
    let onStartTraining: () -> Void

    @State private var history = TrainingHistoryStore.shared
    @State private var settings = AppSettings.shared
    @State private var community = CommunityStore.shared
    @State private var ratingStore = StoreRatingStore.shared
    @State private var showGrowth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    WMLogoHeader().padding(.top, 8)
                    heroCard
                    todayCard
                    weekCard
                    routeSection
                    badgeSection
                }
                .wmPageInset()
                .wmTabBarClearance()
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showGrowth) { GrowthDetailView() }
        }
        .tint(WalkMateTheme.Colors.textPrimary)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今日训练")
                .font(WalkMateTheme.Fonts.pageTitle)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                .accessibilityHidden(true)
            WMButton(title: "开始今天的训练", style: .hero, action: onStartTraining)
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 弧形光晕放在内容之下、卡片渐变之上，贴齐右上角且不挡按钮
        .background(alignment: .topTrailing) {
            Image("home_hero_glow")
                .resizable().scaledToFit()
                .frame(width: 120)
                .opacity(0.9)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .wmCard(WalkMateTheme.Gradients.hero)
    }

    // MARK: - 今日任务

    private var todayMinutes: Int { history.minutesPerDay.last?.minutes ?? 0 }
    private var todayObstacles: Int {
        history.records.filter { Calendar.current.isDateInToday($0.finishedAt) }.reduce(0) { $0 + $1.obstaclesAvoided }
    }

    private var minutesProgress: Double { min(1, Double(todayMinutes) / Double(settings.dailyGoalMinutes)) }
    private var obstaclesProgress: Double { min(1, Double(todayObstacles) / Double(settings.dailyGoalObstacles)) }
    /// 今日完成度：时长与避障两项目标的平均
    private var todayProgress: Double { (minutesProgress + obstaclesProgress) / 2 }

    private struct TaskItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let done: Bool
        /// 有店铺的任务可以点进路线页
        var store: StoreSummary? = nil
    }

    /// 每日目标两项 + 已同意的好友邀约
    private var tasks: [TaskItem] {
        var items = [
            TaskItem(id: "minutes", title: "训练 \(settings.dailyGoalMinutes) 分钟",
                     detail: "已 \(todayMinutes) 分钟", done: todayMinutes >= settings.dailyGoalMinutes),
            TaskItem(id: "obstacles", title: "成功避障 \(settings.dailyGoalObstacles) 次",
                     detail: "已 \(todayObstacles) 次", done: todayObstacles >= settings.dailyGoalObstacles),
        ]
        for invitation in community.feed.invitations where invitation.status == "accepted" {
            items.append(TaskItem(id: invitation.id, title: "和 \(invitation.from) 去\(invitation.place)", detail: invitation.time, done: false,
                                  store: invitation.storeId.flatMap { ratingStore.store(id: $0) }))
        }
        return items
    }

    private var todayCard: some View {
        VStack(spacing: 12) {
            WMSectionHeader(title: "今日任务", action: "查看成长") { showGrowth = true }
            VStack(spacing: 0) {
                HStack {
                    WMRing(progress: minutesProgress, value: "\(todayMinutes)", caption: "分钟")
                    Spacer()
                    WMRing(progress: obstaclesProgress, value: "\(todayObstacles)", caption: "避障")
                    Spacer()
                    WMRing(progress: todayProgress, value: "\(Int(todayProgress * 100))%", caption: "完成")
                }
                .padding(.vertical, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日，训练 \(todayMinutes) 分钟，避障 \(todayObstacles) 次，完成 \(Int(todayProgress * 100))%")
                Divider().overlay(WalkMateTheme.Colors.divider)
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    if let store = task.store {
                        NavigationLink {
                            RouteDetailView(title: "去\(store.name)", route: store.route, store: store)
                        } label: {
                            taskRow(task)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("轻点两下查看路线")
                    } else {
                        taskRow(task)
                    }
                    if index < tasks.count - 1 {
                        Divider().overlay(WalkMateTheme.Colors.divider)
                    }
                }
            }
            .padding(.horizontal, WalkMateTheme.Layout.cardPadding)
            .padding(.vertical, 6)
            .wmCard()
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
                    HStack(spacing: 14) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(task.done ? WalkMateTheme.Colors.accent : Color.white.opacity(0.4))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(WalkMateTheme.Fonts.body)
                                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                                .strikethrough(task.done, color: WalkMateTheme.Colors.textSecondary)
                            Text(task.detail)
                                .font(WalkMateTheme.Fonts.caption)
                                .foregroundStyle(task.done ? WalkMateTheme.Colors.accentSoft : WalkMateTheme.Colors.textSecondary)
                        }
                        Spacer()
                        if task.store != nil {
                            Image("icon_chevron").resizable().scaledToFit().frame(height: 12).foregroundStyle(WalkMateTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(task.done ? "已完成" : "未完成")，\(task.title)，\(task.detail)")
    }

    // MARK: - 本周

    private var weekCard: some View {
        let goal = history.nextGoalText
        return VStack(spacing: 12) {
            WMSectionHeader(title: "本周")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    WMRing(progress: Double(history.trainingDaysThisWeek) / 7, value: "\(history.trainingDaysThisWeek)", caption: "训练天")
                    Spacer()
                    WMRing(progress: min(1, Double(history.obstaclesThisWeek) / 80), value: "\(history.obstaclesThisWeek)", caption: "避障")
                    Spacer()
                    WMRing(progress: history.independentRate, value: "\(Int(history.independentRate * 100))%", caption: "独立完成")
                }
                Text("下一目标：\(goal.title)，\(goal.detail)")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WalkMateTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wmCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本周，训练 \(history.trainingDaysThisWeek) 天，避障 \(history.obstaclesThisWeek) 次，独立完成 \(Int(history.independentRate * 100))%。下一目标：\(goal.title)，\(goal.detail)")
        }
    }

    // MARK: - 我的路线

    private var routeSection: some View {
        VStack(spacing: 12) {
            WMSectionHeader(title: "我的路线")
            NavigationLink {
                RouteDetailView(title: "小区路线", route: SeedData.neighborhoodRoute, completedCount: history.records(of: .neighborhood).count)
            } label: {
                routeRow(icon: "route_neighborhood", title: "小区路线", detail: "已完成 \(history.records(of: .neighborhood).count) 次")
            }
            .buttonStyle(.plain)
            NavigationLink {
                IndoorRouteView()
            } label: {
                routeRow(icon: "route_home", title: "室内训练路线", detail: "已完成 \(history.records(of: .indoor).count) 次")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 徽章

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

    /// 徽章是一个按钮：点一下播放它的专属旋律并报名字
    private func badgeTile(_ image: String, _ title: String) -> some View {
        Button {
            BadgePlayer.shared.play(soundName: image, title: title)
        } label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("徽章，\(title)")
        .accessibilityHint("轻点两下听它的旋律")
    }

    private func routeRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 16) {
            Image(icon).resizable().scaledToFit().frame(width: 57, height: 55)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(WalkMateTheme.Fonts.body).foregroundStyle(WalkMateTheme.Colors.textPrimary)
                Text(detail).font(WalkMateTheme.Fonts.caption).foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.7))
            }
            Spacer()
            Image("icon_chevron_large").resizable().scaledToFit().frame(height: 30).foregroundStyle(WalkMateTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .wmCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(detail)")
    }
}
