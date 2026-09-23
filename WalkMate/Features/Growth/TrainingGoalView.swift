import SwiftUI

/// 训练目标页：每日时长与避障目标，首页「今日康复闭环」的完成度按这两项计算。
/// 首页闭环卡与设置页都能进来。
struct TrainingGoalView: View {
    @State private var settings = AppSettings.shared
    @State private var history = TrainingHistoryStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    WMPageTitle(text: "训练目标")
                    Text("每天完成这两项，首页的「完成」环就会走满")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                }
                goalCard(title: "每日训练时长", unit: "分钟", value: settings.dailyGoalMinutes, range: 5...60, step: 5,
                         today: todayMinutes) { settings.dailyGoalMinutes = $0 }
                goalCard(title: "每日成功避障", unit: "次", value: settings.dailyGoalObstacles, range: 5...50, step: 5,
                         today: todayObstacles) { settings.dailyGoalObstacles = $0 }
                explanation
            }
            .wmPageInset()
            .padding(.top, 12)
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .wmDetailNavigationBar(title: "训练目标")
        .wmAnnounce("训练目标，每项左减右加。")
    }

    private var todayMinutes: Int { history.minutesPerDay.last?.minutes ?? 0 }
    private var todayObstacles: Int {
        history.records.filter { Calendar.current.isDateInToday($0.finishedAt) }.reduce(0) { $0 + $1.obstaclesAvoided }
    }

    /// 一项目标：减、数值、加，对读屏是一个可调节元素
    private func goalCard(title: String, unit: String, value: Int, range: ClosedRange<Int>, step: Int,
                          today: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(WalkMateTheme.Fonts.body).foregroundStyle(WalkMateTheme.Colors.textPrimary)
            HStack(spacing: 18) {
                stepButton("－", enabled: value > range.lowerBound) { onChange(max(range.lowerBound, value - step)) }
                Text("\(value) \(unit)")
                    .font(WalkMateTheme.Fonts.statValueLarge)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                stepButton("＋", enabled: value < range.upperBound) { onChange(min(range.upperBound, value + step)) }
            }
            Text("今天已完成 \(today) \(unit)")
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(WalkMateTheme.Colors.accentSoft)
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(unit)，今天已完成 \(today) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(range.upperBound, value + step))
            case .decrement: onChange(max(range.lowerBound, value - step))
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(WalkMateTheme.Gradients.primaryButton)
                .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("完成度怎么算")
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            Text("时长与避障各算一个百分比，取两者平均就是首页的「完成」。超出目标不会超过 100%。半开放环境与户外档位的解锁另有规则，在训练页「查看要求」里。")
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard()
    }
}
