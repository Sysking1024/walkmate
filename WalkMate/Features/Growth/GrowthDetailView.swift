import SwiftUI

/// 成长详情：本周每日训练时长、累计数据与最近记录，全部来自本机训练记录。
/// 首页「查看成长」与进度页「更多」都进到这里。
struct GrowthDetailView: View {
    @State private var history = TrainingHistoryStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WMPageTitle(text: "成长详情")
                weeklyChart
                totals
                recentSection
            }
            .wmPageInset()
            .padding(.top, 12)
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .wmDetailNavigationBar(title: "成长详情")
    }

    // MARK: - 本周每日训练分钟

    private var weeklyChart: some View {
        let days = history.minutesPerDay
        let peak = max(days.map(\.minutes).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 16) {
            Text("本周每日训练").font(WalkMateTheme.Fonts.body).foregroundStyle(WalkMateTheme.Colors.textPrimary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        Text(day.minutes > 0 ? "\(day.minutes)" : "")
                            .font(WalkMateTheme.Fonts.ringCaption)
                            .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(day.minutes > 0 ? WalkMateTheme.Colors.ringFill : WalkMateTheme.Colors.ringTrack)
                            .frame(height: max(6, 120 * CGFloat(day.minutes) / CGFloat(peak)))
                        Text(Self.weekday(day.date))
                            .font(WalkMateTheme.Fonts.ringCaption)
                            .foregroundStyle(WalkMateTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Self.weekday(day.date))，\(day.minutes) 分钟")
                }
            }
            .frame(height: 170, alignment: .bottom)
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard()
    }

    // MARK: - 累计

    private var totals: some View {
        let records = history.records
        let minutes = records.reduce(0) { $0 + $1.durationSeconds } / 60
        let obstacles = records.reduce(0) { $0 + $1.obstaclesAvoided }
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                WMStatTile(label: "累计训练", value: "\(records.count) 次")
                WMStatTile(label: "累计时长", value: "\(minutes) 分钟")
            }
            HStack(spacing: 14) {
                WMStatTile(label: "累计避障", value: "\(obstacles)")
                WMStatTile(label: "独立完成指数", value: "\(Int(history.independentRate * 100))%")
            }
        }
    }

    // MARK: - 最近记录

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WMSectionHeader(title: "最近训练")
            if history.records.isEmpty {
                Text("还没有训练记录。完成一次室内训练后，这里会记下时长、避障与留下的时刻。")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                    .padding(WalkMateTheme.Layout.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wmCard()
            } else {
                TrainingRecordList(records: Array(history.records.prefix(10)))
            }
        }
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

/// 训练记录列表，成长详情与室内训练路线共用
struct TrainingRecordList: View {
    let records: [TrainingRecord]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.dateText(record.finishedAt))
                            .font(WalkMateTheme.Fonts.body)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                        Text("\(record.kind.title) · \(record.durationSeconds / 60) 分 \(record.durationSeconds % 60) 秒 · 避障 \(record.obstaclesAvoided) 次 · \(record.distanceMeters) 米")
                            .font(WalkMateTheme.Fonts.caption)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                    }
                    Spacer()
                    if !record.moments.isEmpty {
                        Text("\(record.moments.count) 个时刻")
                            .font(WalkMateTheme.Fonts.chip)
                            .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                    }
                }
                .padding(.vertical, 12)
                .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                .accessibilityElement(children: .combine)
                if index < records.count - 1 {
                    Divider().overlay(WalkMateTheme.Colors.divider)
                }
            }
        }
        .padding(.horizontal, WalkMateTheme.Layout.cardPadding)
        .padding(.vertical, 6)
        .wmCard()
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

extension View {
    /// 二级页面的导航栏：黑底、居中标题、系统返回按钮
    func wmDetailNavigationBar(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(WalkMateTheme.Colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
