import SwiftUI

/// 室内训练路线：没有地图，只有从本机训练记录汇总的基础数据与逐次记录
struct IndoorRouteView: View {
    @State private var history = TrainingHistoryStore.shared

    var body: some View {
        let records = history.records
        let totalSeconds = records.reduce(0) { $0 + $1.durationSeconds }
        let obstacles = records.reduce(0) { $0 + $1.obstaclesAvoided }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    WMPageTitle(text: "室内训练路线")
                    Text("室内基础避障，在家里就能练")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                }
                HStack(spacing: 14) {
                    WMStatTile(label: "完成次数", value: "\(records.count) 次")
                    WMStatTile(label: "累计时长", value: Self.durationText(totalSeconds))
                }
                HStack(spacing: 14) {
                    WMStatTile(label: "累计避障", value: "\(obstacles) 次")
                    WMStatTile(label: "平均每次避障", value: records.isEmpty ? "0 次" : "\(obstacles / records.count) 次")
                }
                WMSectionHeader(title: "每次记录")
                if records.isEmpty {
                    Text("还没有记录。去训练栏目完成一次室内训练吧。")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                        .padding(WalkMateTheme.Layout.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wmCard()
                } else {
                    TrainingRecordList(records: records)
                }
            }
            .wmPageInset()
            .padding(.top, 12)
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .wmDetailNavigationBar(title: "室内训练路线")
    }

    private static func durationText(_ seconds: Int) -> String {
        seconds >= 3600 ? "\(seconds / 3600) 时 \(seconds % 3600 / 60) 分" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}
