import SwiftUI

/// 进度页。对应设计稿「进度」。本周记录、里程碑与路线为演示数据。
struct GrowthView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WMLogoHeader().padding(.top, 8)
                WMPageTitle(text: "你的康复成长")
                weeklyCard
                WMSectionHeader(title: "我的路线")
                routeRow(icon: "route_home", title: "家庭路线", detail: "已完成12次")
                routeRow(icon: "route_neighborhood", title: "小区路线", detail: "已完成2次")
            }
            .wmPageInset()
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("本周记录").font(WalkMateTheme.Fonts.body).foregroundStyle(WalkMateTheme.Colors.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text("更多")
                    Image("icon_chevron").resizable().scaledToFit().frame(height: 10)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.54))
            }
            HStack {
                WMRing(progress: 5 / 7, value: "5", caption: "训练天")
                Spacer()
                WMRing(progress: 0.83, value: "68", caption: "避障")
                Spacer()
                WMRing(progress: 0.5, value: "50%", caption: "独立完成")
            }
            Text("里程碑").font(WalkMateTheme.Fonts.body).foregroundStyle(WalkMateTheme.Colors.textPrimary)
            milestones
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard()
    }

    /// 里程碑时间线：左侧竖线串起三个节点，当前节点用强调绿
    private var milestones: some View {
        VStack(alignment: .leading, spacing: 0) {
            milestone(dot: 7, lineBelow: true, dimmed: true, time: "昨天", title: "训练大进步", detail: "室内 320m ·成功避障20次")
            milestone(dot: 14, lineBelow: true, highlight: true, time: "9月20日", title: "连续训练5天", detail: "解锁「KEEP GOING」徽章")
            milestone(dot: 11, lineBelow: false, dimmed: false, time: "下一目标", title: "半开放路线", detail: "再完成2次室内训练即可解锁")
        }
    }

    private func milestone(dot: CGFloat, lineBelow: Bool, dimmed: Bool = false, highlight: Bool = false, time: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(highlight ? WalkMateTheme.Colors.accent : Color(hex: 0x88E59B).opacity(0.6))
                    .frame(width: dot, height: dot)
                if lineBelow {
                    Rectangle().fill(Color(hex: 0x88E59B).opacity(0.25)).frame(width: 6, height: 44)
                }
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) { Text(time); Text("·"); Text(title).font(.system(size: 14, weight: .medium)) }
                    .font(WalkMateTheme.Fonts.body)
                    .foregroundStyle(highlight ? WalkMateTheme.Colors.accent : WalkMateTheme.Colors.textPrimary.opacity(dimmed ? 0.71 : 1))
                Text(detail)
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(highlight ? WalkMateTheme.Colors.accentSoft : WalkMateTheme.Colors.textPrimary.opacity(0.72))
            }
            .padding(.bottom, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private func routeRow(icon: String, title: String, detail: String) -> some View {
        Button {} label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(detail)")
    }
}
