import AVKit
import SwiftUI

/// 社群页。对应设计稿「社群」。
///
/// 好友成就、邀约、旅程来自社群动态（后端可达时拉取，否则用内置种子）；
/// 探店卡片来自店铺数据，评分与「查看路线」都可操作。
struct CommunityView: View {
    @State private var ratingStore = StoreRatingStore.shared
    @State private var communityStore = CommunityStore.shared
    @State private var history = TrainingHistoryStore.shared
    @State private var player: AVPlayer?
    /// 本机是否给旅程点过赞，只存本地
    @AppStorage("walkmate.likedJourney") private var likedJourney = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WMLogoHeader().padding(.top, 8)
                    WMPageTitle(text: "好友成就")
                    achievementCard

                    WMPageTitle(text: "无障碍探店")
                    ForEach(ratingStore.stores) { store in
                        storeCard(store)
                    }
                    ForEach(communityStore.feed.invitations) { invitation in
                        inviteCard(invitation)
                    }

                    if let journey = communityStore.feed.journeys.first {
                        WMPageTitle(text: "我的旅程")
                        journeyCard(journey)
                    }
                }
                .wmPageInset()
                .wmTabBarClearance()
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: StoreSummary.self) { store in
                RouteDetailView(title: "去\(store.name)", route: store.route, store: store)
            }
        }
        .tint(WalkMateTheme.Colors.textPrimary)
        .fullScreenCover(item: $player) { player in
            ReelPlayerView(player: player) { self.player = nil }
        }
        .task {
            await communityStore.refresh()
            await ratingStore.refresh()
        }
    }

    // MARK: - 好友今日成就

    private var achievementCard: some View {
        let items = communityStore.feed.achievements
        return VStack(alignment: .leading, spacing: 18) {
            // 设计稿：金冠居中放大，银、铜分列两侧
            let gold = items.first { $0.crown == "crown_gold" }
            let others = items.filter { $0.crown != "crown_gold" }
            HStack(alignment: .top) {
                if let silver = others.first { friend(silver, size: 64) }
                Spacer()
                if let gold { friend(gold, size: 77) }
                Spacer()
                if others.count > 1 { friend(others[1], size: 64) }
            }
            .padding(.horizontal, 8)
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.communityCard)
    }

    private func friend(_ item: CommunityFeed.Achievement, size: CGFloat) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                WMAvatar(imageName: item.avatarKey, size: size).padding(.top, 10)
                if let crown = item.crown {
                    Image(crown).resizable().scaledToFit().frame(width: 22).accessibilityHidden(true)
                }
            }
            Text(item.user)
                .font(WalkMateTheme.Fonts.caption).tracking(1.3)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            Text(item.note)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.user)，\(item.note)")
    }

    // MARK: - 探店

    private func storeCard(_ store: StoreSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(store.coverKey)
                    .resizable().scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(store.name).font(WalkMateTheme.Fonts.body).tracking(1.6)
                        Spacer()
                        Text(String(format: "%.1fkm", store.distanceKm)).font(.system(size: 10, weight: .medium)).tracking(1)
                    }
                    .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image("icon_star").resizable().scaledToFit().frame(width: 12).foregroundStyle(.white)
                        Text(String(format: "%.1f", store.averageScore))
                        Text("\(store.visitorCount)位视障用户去过")
                    }
                    .font(.system(size: 10, weight: .medium)).tracking(1)
                    .foregroundStyle(.white)
                    chipRows(store.tags)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(store.name)，\(store.category)，距离 \(String(format: "%.1f", store.distanceKm)) 公里，无障碍评分 \(String(format: "%.1f", store.averageScore))，\(store.visitorCount) 位视障用户去过，\(store.tags.joined(separator: "，"))")

            NavigationLink(value: store) {
                Text("查看路线")
            }
            .buttonStyle(WhitePillButtonStyle())
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.storeCard)
    }

    private func chipRows(_ tags: [String]) -> some View {
        let rows = stride(from: 0, to: tags.count, by: 2).map { Array(tags[$0..<min($0 + 2, tags.count)]) }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) { ForEach(row, id: \.self) { WMChip(text: $0) } }
            }
        }
    }

    // MARK: - 邀约

    private func inviteCard(_ invitation: CommunityFeed.Invitation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("好友邀你一起探索")
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            HStack(alignment: .top, spacing: 12) {
                WMAvatar(imageName: invitation.avatarKey, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    (Text("\(invitation.from) ").bold() + Text("想邀请你一起去 ") + Text(invitation.place).bold())
                        .font(WalkMateTheme.Fonts.caption).tracking(1.3)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    Text(invitation.time)
                    if let message = invitation.message { Text("留言：\(message)") }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            switch invitation.status {
            case "accepted":
                Text("已同意，到时候 \(invitation.place) 见")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                    .frame(maxWidth: .infinity, minHeight: 48)
            case "declined":
                Text("已婉拒这次邀约")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            default:
                HStack(spacing: 14) {
                    Button("拒绝") { Task { await communityStore.respond(to: invitation.id, accepted: false) } }
                        .buttonStyle(GhostPillButtonStyle())
                    Button("同意") { Task { await communityStore.respond(to: invitation.id, accepted: true) } }
                        .buttonStyle(GreenPillButtonStyle(opacity: 0.4))
                }
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.communityCard)
    }

    // MARK: - 我的旅程

    private func journeyCard(_ journey: CommunityFeed.Journey) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if let url = history.latestReelURL { player = AVPlayer(url: url) }
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        Image("journey_thumbnail").resizable().scaledToFill()
                        WalkMateTheme.Gradients.coverShade
                        Image("journey_play_badge").resizable().scaledToFit().frame(width: 32).padding(10)
                    }
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(history.latestReelURL == nil)
                .accessibilityLabel("播放旅程视频")

                VStack(alignment: .leading, spacing: 6) {
                    Text(journey.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    Text(journey.duration)
                    Text("步行 \(Int(journey.distanceKm)) km · 解锁新区域")
                    if let note = journey.note {
                        Text(note)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: 0x1B3320))
                            .padding(8)
                            .background(WalkMateTheme.Colors.chipBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            // 作者与互动单独一排，触控目标不小于 48 点
            HStack(spacing: 8) {
                WMAvatar(imageName: journey.avatarKey, size: 28)
                Text(journey.user)
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    likedJourney.toggle()
                } label: {
                    reactionLabel("icon_like", count: journey.likes + (likedJourney ? 1 : 0), highlighted: likedJourney)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(likedJourney ? "已点赞，\(journey.likes + 1)" : "点赞，\(journey.likes)")
                reactionLabel("icon_comment", count: journey.comments, highlighted: false)
                    .accessibilityLabel("评论 \(journey.comments) 条")
                reactionLabel("icon_share", count: journey.shares, highlighted: false)
                    .accessibilityLabel("转发 \(journey.shares) 次")
            }

            // 只有本机已经剪出过集锦，才有东西可分享
            if let latestReel = history.latestReelURL {
                ShareLink(item: latestReel) {
                    Text("分享我的旅程")
                        .font(WalkMateTheme.Fonts.body).tracking(1.6)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 47)
                        .background(WalkMateTheme.Gradients.primaryButton)
                        .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                }
                .accessibilityHint("把最近一次训练的集锦发给同伴")
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.communityCard)
    }
}

extension CommunityView {
    /// 图标加数字的互动项，高度 48 点
    fileprivate func reactionLabel(_ icon: String, count: Int, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(icon).resizable().scaledToFit().frame(width: 22, height: 22)
            Text("\(count)")
                .font(WalkMateTheme.Fonts.body)
                .monospacedDigit()
        }
        .foregroundStyle(highlighted ? WalkMateTheme.Colors.accentSoft : WalkMateTheme.Colors.textPrimary)
        .padding(.horizontal, 10)
        .frame(minWidth: 56, minHeight: WalkMateTheme.Layout.minimumTapTarget)
        .background(Color.white.opacity(highlighted ? 0.18 : 0.08))
        .clipShape(Capsule())
    }
}

/// 白底深绿字的半宽按钮
struct WhitePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WalkMateTheme.Fonts.body).tracking(1.6)
            .foregroundStyle(Color(hex: 0x2C823D))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
    }
}

/// 绿色半透明的半宽按钮
struct GreenPillButtonStyle: ButtonStyle {
    var opacity: Double = 0.6
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WalkMateTheme.Fonts.body).tracking(1.6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(red: 73 / 255, green: 178 / 255, blue: 94 / 255).opacity(configuration.isPressed ? opacity * 0.7 : opacity))
            .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
    }
}

/// 白色半透明的次要按钮
struct GhostPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WalkMateTheme.Fonts.body).tracking(1.6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.2))
            .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
    }
}
