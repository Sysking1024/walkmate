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
    @State private var liked: Set<String> = JourneyReactionStore.loadLikes()
    @State private var commentTarget: CommunityFeed.Journey?
    @State private var deleteTarget: CommunityFeed.Journey?
    @State private var routeTarget: StoreSummary?
    @State private var inviteTarget: StoreSummary?

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

                    WMPageTitle(text: "大家的旅程")
                    ForEach(communityStore.journeys) { journey in
                        journeyCard(journey)
                    }
                }
                .wmPageInset()
                .wmTabBarClearance()
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $routeTarget) { store in
                RouteDetailView(title: "去\(store.name)", route: store.route, store: store)
            }
        }
        .tint(WalkMateTheme.Colors.textPrimary)
        .fullScreenCover(item: $player) { player in
            ReelPlayerView(player: player) { self.player = nil }
        }
        .sheet(item: $commentTarget) { journey in
            JourneyCommentSheet(journey: journey) { commentTarget = nil }
        }
        .sheet(item: $inviteTarget) { store in
            InviteFriendSheet(store: store) { inviteTarget = nil }
        }
        .alert("删除这条旅程？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("删除", role: .destructive) {
                if let journey = deleteTarget {
                    Task { await communityStore.deleteJourney(journey); AccessibilityFeedback.done("旅程已删除") }
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget.map { "「\($0.title)」会从大家的旅程里移除。" } ?? "")
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(store.name)，\(store.category)，距离 \(String(format: "%.1f", store.distanceKm)) 公里，无障碍评分 \(String(format: "%.1f", store.averageScore))，\(store.visitorCount) 位视障用户去过，\(store.tags.joined(separator: "，"))")

            Text("查看路线")
                .font(WalkMateTheme.Fonts.body).tracking(1.6)
                .foregroundStyle(Color(hex: 0x2C823D))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    Log.info("点了查看路线：\(store.name)", category: .ui)
                    routeTarget = store
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("查看路线，\(store.name)")

            // 邀好友一起去；已发出的邀约在卡片上列出来
            let sent = communityStore.sentInvitations(for: store.id)
            if !sent.isEmpty {
                Text("已邀请 " + sent.map(\.friend).joined(separator: "、") + "，等待回复")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.85))
            }
            Text("邀请好友一起去")
                .font(WalkMateTheme.Fonts.body).tracking(1.6)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { inviteTarget = store }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("邀请好友一起去\(store.name)")
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.storeCard)
        .contentShape(Rectangle())
        .zIndex(1)
    }

    private func chipRows(_ tags: [String]) -> some View {
        WMFlowLayout(spacing: 4) {
            ForEach(tags, id: \.self) { WMChip(text: $0) }
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
                    Button("拒绝") { Task { await communityStore.respond(to: invitation.id, accepted: false); AccessibilityFeedback.done("已拒绝邀约") } }
                        .buttonStyle(GhostPillButtonStyle())
                    Button("同意") { Task { await communityStore.respond(to: invitation.id, accepted: true); AccessibilityFeedback.done("已同意，任务已加到首页") } }
                        .buttonStyle(GreenPillButtonStyle(opacity: 0.4))
                }
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.communityCard)
    }

    // MARK: - 大家的旅程

    private func journeyCard(_ journey: CommunityFeed.Journey) -> some View {
        let video = CommunityStore.videoURL(for: journey)
        let isLiked = liked.contains(journey.id)
        let commentCount = journey.comments + JourneyReactionStore.loadComments(for: journey.id).count
        return VStack(alignment: .leading, spacing: 14) {
            // 封面通栏，点了就播；标题在封面下方
            Button {
                if let video { player = AVPlayer(url: video) }
            } label: {
                WMCoverImage(image: CommunityStore.coverImage(for: journey), fallback: "journey_thumbnail", height: 190)
                    .overlay { WalkMateTheme.Gradients.coverShade }
                    .overlay(alignment: .bottomLeading) {
                        Image("journey_play_badge").resizable().scaledToFit().frame(width: 40).padding(14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(video == nil)
            .accessibilityLabel("播放旅程视频，\(journey.title)，\(journey.user) 分享")

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
                    if isLiked { liked.remove(journey.id) } else { liked.insert(journey.id) }
                    JourneyReactionStore.saveLikes(liked)
                    AccessibilityFeedback.done(isLiked ? "已取消点赞" : "已点赞")
                } label: {
                    reactionLabel("icon_like", count: journey.likes + (isLiked ? 1 : 0), highlighted: isLiked)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isLiked ? "取消点赞，\(journey.likes + 1) 个赞" : "点赞，\(journey.likes) 个赞")

                Button {
                    commentTarget = journey
                } label: {
                    reactionLabel("icon_comment", count: commentCount, highlighted: commentCount > journey.comments)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("评论，\(commentCount) 条")
            }

            // 自己的旅程：可以转发到别的应用，也可以删除
            if communityStore.isMine(journey) {
                HStack(spacing: 14) {
                    if let video {
                        ShareLink(item: video) {
                            Text("分享我的旅程")
                                .font(WalkMateTheme.Fonts.body).tracking(1.6)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 47)
                                .background(WalkMateTheme.Gradients.primaryButton)
                                .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                        }
                        .accessibilityHint("把这段集锦发给同伴")
                    }
                    Button("删除") { deleteTarget = journey }
                        .buttonStyle(GhostPillButtonStyle())
                        .frame(maxWidth: 110)
                        .accessibilityLabel("删除这条旅程")
                }
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

/// 本机的点赞与评论，按旅程 ID 存在本地
enum JourneyReactionStore {
    private static let likesKey = "walkmate.likedJourneys"
    private static let commentsKey = "walkmate.journeyComments."

    static func loadLikes() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: likesKey) ?? []) }
    static func saveLikes(_ likes: Set<String>) { UserDefaults.standard.set(Array(likes), forKey: likesKey) }
    static func loadComments(for journeyID: String) -> [String] { UserDefaults.standard.stringArray(forKey: commentsKey + journeyID) ?? [] }
    static func saveComments(_ comments: [String], for journeyID: String) { UserDefaults.standard.set(comments, forKey: commentsKey + journeyID) }

    /// 演示用的好友评论，与各旅程的评论数对应
    static func seeded(for journeyID: String) -> [(String, String)] {
        switch journeyID {
        case "j_1": return [("Momo", "第一次半开放就走得这么稳，太棒了！下次一起去金鹰。")]
        case "j_2": return [("Doris", "湖边栈道那段听得我也想去走走，太美了！")]
        default: return []
        }
    }
}

/// 评论弹层：好友评论 + 本机写的评论 + 一个输入框
struct JourneyCommentSheet: View {
    let journey: CommunityFeed.Journey
    let onClose: () -> Void

    @State private var comments: [String] = []
    @State private var draft = ""

    private var seeded: [(String, String)] { JourneyReactionStore.seeded(for: journey.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WMPageTitle(text: "评论")
                    Text(journey.title).font(WalkMateTheme.Fonts.caption).foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                    // 好友留下的评论（演示数据）在前，本机写的在后
                    ForEach(Array((seeded + comments.map { ("我", $0) }).enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.0)
                                .font(WalkMateTheme.Fonts.caption)
                                .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                            Text(entry.1)
                                .font(WalkMateTheme.Fonts.body)
                                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(WalkMateTheme.Layout.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wmCard()
                        .accessibilityElement(children: .combine)
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
        .onAppear {
            comments = JourneyReactionStore.loadComments(for: journey.id)
            AccessibilityFeedback.screenChanged("评论")
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        comments.append(text)
        JourneyReactionStore.saveComments(comments, for: journey.id)
        draft = ""
        AccessibilityFeedback.done("评论已发送")
        Log.info("已写下一条旅程评论", category: .ui)
    }
}

/// 邀请好友去某家店：选一个人发出即可，时间到时候再约
struct InviteFriendSheet: View {
    let store: StoreSummary
    let onClose: () -> Void

    @State private var community = CommunityStore.shared
    @State private var friend: String = CommunityStore.friends.first?.name ?? ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WMPageTitle(text: "邀请好友一起去")
                    Text(store.name)
                        .font(WalkMateTheme.Fonts.body)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.85))

                    WMSectionHeader(title: "邀请谁")
                    VStack(spacing: 0) {
                        ForEach(Array(CommunityStore.friends.enumerated()), id: \.offset) { index, item in
                            Button {
                                friend = item.name
                            } label: {
                                HStack(spacing: 14) {
                                    WMAvatar(imageName: item.avatarKey, size: 44)
                                    Text(item.name).font(WalkMateTheme.Fonts.body).foregroundStyle(WalkMateTheme.Colors.textPrimary)
                                    Spacer()
                                    Image(systemName: friend == item.name ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 24))
                                        .foregroundStyle(friend == item.name ? WalkMateTheme.Colors.accent : Color.white.opacity(0.4))
                                }
                                .padding(.vertical, 10)
                                .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(friend == item.name ? [.isButton, .isSelected] : .isButton)
                            if index < CommunityStore.friends.count - 1 { Divider().overlay(WalkMateTheme.Colors.divider) }
                        }
                    }
                    .padding(.horizontal, WalkMateTheme.Layout.cardPadding)
                    .padding(.vertical, 6)
                    .wmCard()

                    WMButton(title: sent ? "已发出邀请" : "发出邀请", height: 61) { send() }
                        .disabled(sent)
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
        .onAppear { AccessibilityFeedback.screenChanged("邀请好友") }
    }

    private func send() {
        community.invite(friend: friend, to: store, time: "时间待定")
        sent = true
        AccessibilityFeedback.done("已邀请 \(friend)")
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            onClose()
        }
    }
}
