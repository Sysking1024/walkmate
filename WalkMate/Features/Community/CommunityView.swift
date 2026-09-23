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
    @State private var showComments = false
    @State private var myComments = JourneyCommentStore.load()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WMLogoHeader().padding(.top, 8)
                    HStack(alignment: .firstTextBaseline) {
                        WMPageTitle(text: "好友成就")
                        Spacer()
                        NavigationLink { AddFriendView() } label: {
                            Text("添加好友")
                                .font(WalkMateTheme.Fonts.body)
                                .foregroundStyle(Color.white.opacity(0.54))
                                .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                        }
                        .buttonStyle(.plain)
                    }
                    achievementCard

                    WMPageTitle(text: "无障碍探店")
                    // 好友邀约排在最前，店铺卡就嵌在邀约里；下面只列没被邀约的店
                    ForEach(communityStore.feed.invitations) { invitation in
                        inviteCard(invitation)
                    }
                    ForEach(ratingStore.stores.filter { store in !invitedStoreIDs.contains(store.id) }) { store in
                        storeCard(store)
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
        .sheet(isPresented: $showComments) {
            JourneyCommentSheet(comments: $myComments) { showComments = false }
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.8))
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
                        Text(String(format: "%.1fkm", store.distanceKm)).font(WalkMateTheme.Fonts.caption)
                    }
                    .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image("icon_star").resizable().scaledToFit().frame(width: 12).foregroundStyle(.white)
                        Text(String(format: "%.1f", store.averageScore))
                        Text("\(store.visitorCount)位视障用户去过")
                    }
                    .font(WalkMateTheme.Fonts.caption)
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

    private var invitedStoreIDs: Set<String> {
        Set(communityStore.feed.invitations.compactMap(\.storeId))
    }

    private func inviteCard(_ invitation: CommunityFeed.Invitation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WMAvatar(imageName: invitation.avatarKey, size: 48)
                Text("\(invitation.from) 想邀请你一起去")
                    .font(WalkMateTheme.Fonts.body)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let store = invitation.storeId.flatMap({ ratingStore.store(id: $0) }) {
                storeCard(store)
            } else {
                Text(invitation.place)
                    .font(WalkMateTheme.Fonts.body)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            }

            switch invitation.status {
            case "accepted":
                Text("已同意，\(invitation.time)")
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
            // 封面通栏，点了就播；标题在封面下方
            Button {
                if let url = history.latestReelURL { player = AVPlayer(url: url) }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Image("journey_thumbnail").resizable().scaledToFill()
                    WalkMateTheme.Gradients.coverShade
                    Image("journey_play_badge").resizable().scaledToFit().frame(width: 40).padding(14)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(history.latestReelURL == nil)
            .accessibilityLabel("播放旅程视频，\(journey.title)")

            Text(journey.title)
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)

            // 作者与互动一排，触控目标不小于 48 点
            HStack(spacing: 8) {
                WMAvatar(imageName: journey.avatarKey, size: 28)
                Text(journey.user)
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 8)
                Button {
                    likedJourney.toggle()
                } label: {
                    reactionLabel("icon_like", count: journey.likes + (likedJourney ? 1 : 0), highlighted: likedJourney)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(likedJourney ? "取消点赞，\(journey.likes + 1) 个赞" : "点赞，\(journey.likes) 个赞")

                Button {
                    showComments = true
                } label: {
                    reactionLabel("icon_comment", count: journey.comments + myComments.count, highlighted: !myComments.isEmpty)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("评论，\(journey.comments + myComments.count) 条")

                if let reel = history.latestReelURL {
                    ShareLink(item: reel) {
                        reactionLabel("icon_share", count: journey.shares, highlighted: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("转发，\(journey.shares) 次")
                }
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
                .lineLimit(1)
                .fixedSize()
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

/// 本机写下的旅程评论，只存本地
enum JourneyCommentStore {
    private static let key = "walkmate.journeyComments"
    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func save(_ comments: [String]) { UserDefaults.standard.set(comments, forKey: key) }
}

/// 评论弹层：已有评论列表 + 一个输入框
struct JourneyCommentSheet: View {
    @Binding var comments: [String]
    let onClose: () -> Void

    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WMPageTitle(text: "评论")
                    if comments.isEmpty {
                        Text("还没有评论，说点什么吧")
                            .font(WalkMateTheme.Fonts.caption)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                    } else {
                        ForEach(Array(comments.enumerated()), id: \.offset) { _, comment in
                            Text(comment)
                                .font(WalkMateTheme.Fonts.body)
                                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                                .padding(WalkMateTheme.Layout.cardPadding)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .wmCard()
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("写评论", text: $draft)
                            .textFieldStyle(.plain)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                            .onSubmit(send)
                        WMButton(title: "发送", height: 48, action: send)
                            .frame(width: 88)
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .wmPageInset()
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(WalkMateTheme.Colors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onClose)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                        .frame(minWidth: 48, minHeight: 48)
                }
            }
            .toolbarBackground(WalkMateTheme.Colors.background, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        comments.append(text)
        JourneyCommentStore.save(comments)
        draft = ""
        Log.info("已写下一条旅程评论", category: .ui)
    }
}
