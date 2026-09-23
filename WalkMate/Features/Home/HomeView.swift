import SwiftUI

/// 首页。对应设计稿「home」画面。
///
/// 康复闭环、徽章、同伴进程目前为演示数据（产品决定社群类内容首期用静态数据）。
struct HomeView: View {
    /// 点击「开始今天的训练」时切换到训练栏目
    let onStartTraining: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                WMLogoHeader().padding(.top, 8)
                heroCard
                loopSection
                badgeSection
                peerSection
            }
            .wmPageInset()
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
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

    private var loopSection: some View {
        VStack(spacing: 12) {
            WMSectionHeader(title: "今日康复闭环", action: "查看成长")
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    WMRing(progress: 0.8, value: "18", caption: "分钟")
                    Spacer()
                    WMRing(progress: 0.68, value: "12", caption: "避障")
                    Spacer()
                    WMRing(progress: 0.84, value: "84%", caption: "完成")
                }
                Text("加油~  已经快完成今日训练项目啦")
                    .font(WalkMateTheme.Fonts.body)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            }
            .padding(WalkMateTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wmCard()
        }
    }

    private var badgeSection: some View {
        VStack(spacing: 12) {
            WMSectionHeader(title: "我的徽章", action: "查看全部")
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
            WMSectionHeader(title: "同伴进程", action: "进入社群")
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
