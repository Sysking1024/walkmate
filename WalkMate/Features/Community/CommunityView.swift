import SwiftUI

/// 社群页。对应设计稿「社群」。
///
/// 好友成就、探店、邀约、旅程均为演示数据：产品决定社群首期为静态展示。
/// 探店卡片上新增「去评分」入口，通往店铺无障碍打分页。
struct CommunityView: View {
    @State private var storeCategory = 2
    @State private var showRating = false
    @State private var ratingStore = StoreRatingStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WMLogoHeader().padding(.top, 8)
                WMPageTitle(text: "好友今日成就榜")
                achievementCard

                WMPageTitle(text: "无障碍探店")
                storeCard
                inviteCard

                WMPageTitle(text: "今日旅程")
                journeyCard
            }
            .wmPageInset()
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showRating) {
            StoreRatingView(storeName: "影石Insta360", isPresented: $showRating)
        }
    }

    // MARK: - 好友今日成就

    private var achievementCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("今日成就"); Text("·"); Text("Today’s  Achievement")
            }
            .font(WalkMateTheme.Fonts.body)
            .foregroundStyle(WalkMateTheme.Colors.textPrimary)

            HStack(alignment: .top) {
                friend("avatar_momo", crown: "crown_silver", name: "Momo", note: "完成 Level 4 户外训练", size: 64)
                Spacer()
                friend("avatar_zixuan", crown: "crown_gold", name: "子璇爸爸", note: "独立出行 3.2 km\n探索 2 个新地点", size: 77)
                Spacer()
                friend("avatar_liujiajia", crown: "crown_bronze", name: "刘佳佳", note: "第一次独立乘坐地铁", size: 64)
            }
            .padding(.horizontal, 8)

            WMButton(title: "查看更多好友进展", height: 47) {}
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.communityCard)
    }

    private func friend(_ avatar: String, crown: String, name: String, note: String, size: CGFloat) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                WMAvatar(imageName: avatar, size: size).padding(.top, 10)
                Image(crown).resizable().scaledToFit().frame(width: 22).accessibilityHidden(true)
            }
            Text(name)
                .font(WalkMateTheme.Fonts.caption).tracking(1.3)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            Text(note)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(note.replacingOccurrences(of: "\n", with: "，"))")
    }

    // MARK: - 探店

    private var storeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(["美食", "娱乐", "购物"].enumerated()), id: \.offset) { index, title in
                    Button { storeCategory = index } label: {
                        Text(title)
                            .font(WalkMateTheme.Fonts.body).tracking(1.6)
                            .foregroundStyle(storeCategory == index ? .white : WalkMateTheme.Colors.segmentText)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(storeCategory == index ? WalkMateTheme.Colors.segmentSelected : WalkMateTheme.Colors.segmentUnselected)
                            .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(storeCategory == index ? .isSelected : [])
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Image("store_insta360")
                    .resizable().scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("影石Insta360").font(WalkMateTheme.Fonts.body).tracking(1.6)
                        Spacer()
                        Text("2.2km").font(.system(size: 10, weight: .medium)).tracking(1)
                    }
                    .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image("icon_star").resizable().scaledToFit().frame(width: 12).foregroundStyle(.white)
                        Text(String(format: "%.1f", ratingStore.averageScore(for: "影石Insta360", fallback: 4.8)))
                        Text("\(ratingStore.visitorCount(for: "影石Insta360", fallback: 36))位视障用户去过")
                    }
                    .font(.system(size: 10, weight: .medium)).tracking(1)
                    .foregroundStyle(.white)
                    chipRows(ratingStore.topTags(for: "影石Insta360", fallback: ["无障碍入口", "方便独立前往", "店内安静", "无障碍卫生间"]))
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 14) {
                Button("查看路线") {}
                    .buttonStyle(WhitePillButtonStyle())
                Button("去评分") { showRating = true }
                    .buttonStyle(GreenPillButtonStyle())
            }
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

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("好友邀你一起探索")
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            HStack(alignment: .top, spacing: 12) {
                WMAvatar(imageName: "avatar_momo", size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    (Text("Momo ").bold() + Text("想邀请你一起去 ") + Text("上野公园").bold())
                        .font(WalkMateTheme.Fonts.caption).tracking(1.3)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    Text("9月25日 星期六 早上9:30出发")
                    Text("留言：想去感受秋天。")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 14) {
                Button("拒绝") {}.buttonStyle(GhostPillButtonStyle())
                Button("同意") {}.buttonStyle(GreenPillButtonStyle(opacity: 0.4))
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.communityCard)
    }

    // MARK: - 今日旅程

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    Image("journey_thumbnail").resizable().scaledToFill()
                    WalkMateTheme.Gradients.coverShade
                    Image("journey_play_badge").resizable().scaledToFit().frame(width: 32).padding(10)
                }
                .frame(width: 130, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("第一次独立去购物")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                        Spacer()
                        Text("查看全部").font(.system(size: 9, weight: .medium)).foregroundStyle(WalkMateTheme.Colors.textSecondary)
                    }
                    Text("360 旅程 · 4:28")
                    Text("步行15km     解锁新区域")
                    Text("第一次独自去商业中心，有点紧张！\n但是去了之后发现真的很有趣！")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(hex: 0x1B3320))
                        .padding(8)
                        .background(WalkMateTheme.Colors.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    HStack(spacing: 10) {
                        WMAvatar(imageName: "avatar_doris_small", size: 22)
                        Text("Doris")
                        Spacer()
                        Label("52", image: "icon_like")
                        Label("12", image: "icon_comment")
                        Label("5", image: "icon_share")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    .labelStyle(TinyIconLabelStyle())
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            WMButton(title: "分享我的旅程", height: 47) {}
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .wmCard(WalkMateTheme.Gradients.communityCard)
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

/// 小图标在前、数字在后的紧凑标签
struct TinyIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.frame(width: 14, height: 14)
            configuration.title
        }
    }
}
