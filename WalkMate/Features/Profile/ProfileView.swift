import SwiftUI

/// 个人与设置页。对应设计稿「Frame 7」。三个滑杆直接作用于伙伴对谈、朗读与字体。
struct ProfileView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WMLogoHeader().padding(.top, 8)
                    WMSectionHeader(title: "个人")
                    profileCard
                    WMSectionHeader(title: "设置").padding(.top, 8)
                    settingsCard
                }
                .wmPageInset()
                .wmTabBarClearance()
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(WalkMateTheme.Colors.textPrimary)
    }

    private var profileCard: some View {
        HStack(spacing: 20) {
            WMAvatar(imageName: "avatar_doris", size: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text("Doris").font(.system(size: 20, weight: .medium))
                Text("喜欢探索户外").font(WalkMateTheme.Fonts.caption)
            }
            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 107, alignment: .leading)
        .wmCard(WalkMateTheme.Gradients.activeLevel)
        .accessibilityElement(children: .combine)
    }

    private var settingsCard: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            sliderRow("语音引导", value: $settings.guidance, labels: ["详细", "简洁", "静音"], hint: guidanceHint)
            divider
            sliderRow("语速", value: $settings.speechRate)
            divider
            sliderRow("字体大小", value: $settings.textScale)
            divider
            NavigationLink { TrainingGoalView() } label: { navLabel("训练目标") }
                .buttonStyle(.plain)
            divider
            navRow("联系客服", page: .support)
            divider
            navRow("帮助", page: .help)
            divider
            navRow("关于我们", page: .about)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .wmCard(WalkMateTheme.Gradients.card, dimmed: true)
    }

    private var guidanceHint: String {
        switch settings.guidanceLevel {
        case .detailed: return "详细：驻足时伙伴主动询问，描述更完整"
        case .brief: return "简洁：驻足时伙伴主动询问，描述只说要点"
        case .muted: return "静音：伙伴不主动开口，只在你按「说说这儿」时描述"
        }
    }

    private var divider: some View { Divider().overlay(WalkMateTheme.Colors.divider) }

    private func sliderRow(_ title: String, value: Binding<Double>, labels: [String]? = nil, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(WalkMateTheme.Fonts.body).foregroundStyle(.white)
            Slider(value: value)
                .tint(WalkMateTheme.Colors.sliderFill)
                .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                .accessibilityLabel(title)
            if let labels {
                HStack {
                    ForEach(labels, id: \.self) { label in
                        Text(label).frame(maxWidth: .infinity, alignment: label == labels.first ? .leading : (label == labels.last ? .trailing : .center))
                    }
                }
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(.white)
            }
            if let hint {
                Text(hint).font(WalkMateTheme.Fonts.chip).foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(.vertical, 14)
    }

    private func navRow(_ title: String, page: InfoPage) -> some View {
        NavigationLink { InfoPageView(page: page) } label: { navLabel(title) }
            .buttonStyle(.plain)
    }

    private func navLabel(_ title: String) -> some View {
        HStack {
            Text(title).font(WalkMateTheme.Fonts.body).foregroundStyle(.white)
            Spacer()
            Image("icon_chevron").resizable().scaledToFit().frame(height: 14).foregroundStyle(.white)
        }
        .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
    }
}

/// 个人页里的三个文字页面
enum InfoPage {
    case support, help, about

    var title: String {
        switch self {
        case .support: return "联系客服"
        case .help: return "帮助"
        case .about: return "关于我们"
        }
    }

    /// 段落列表：标题与正文
    var sections: [(String, String)] {
        switch self {
        case .support:
            return [
                ("现场版本", "伴行目前是比赛原型，还没有客服热线。有任何问题，直接找现场的伴行团队成员就好。"),
                ("反馈建议", "训练里哪句描述没听懂、哪个按钮不好找，都欢迎告诉我们，这些会直接影响下一版。"),
            ]
        case .help:
            return [
                ("怎么连相机", "先在手机的无线局域网里连上相机热点，再回到训练页点「连接相机」。连上后画面右上角会显示帧率。"),
                ("伙伴什么时候开口", "训练中停下来大约 3 秒，伙伴会问「要我说说这儿吗」。答「好」就描述，答「不用」它会安静一会儿。也可以随时按「说说这儿」。"),
                ("描述之后还能问", "描述完可以追问，比如「左手边是什么」。说「够了」就结束这轮。"),
                ("集锦和分享", "训练结束后，留下的时刻会自动剪成带语音和字幕的短片，可以在总结页播放，也能分享给同伴。"),
                ("设置里能调什么", "语音引导分详细、简洁、静音三档；语速与字体大小拖动滑杆即可，改动立即生效。"),
            ]
        case .about:
            return [
                ("伴行 WalkMate", "为后天失明的朋友做的渐进式独立出行康复训练。从室内避障开始，一步步走到户外。"),
                ("我们相信", "独立不是一个人硬撑，而是身边有可靠的伙伴。伴行用全景相机当眼睛，用 AI 当那个陪你说话的人。"),
                ("团队", "影石 Insta360 黑客松参赛作品，2026 年 9 月于南京。"),
            ]
        }
    }
}

struct InfoPageView: View {
    let page: InfoPage

    @State private var showGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WMPageTitle(text: page.title)
                ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.0)
                            .font(WalkMateTheme.Fonts.body)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.1)
                            .font(WalkMateTheme.Fonts.caption)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(WalkMateTheme.Layout.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wmCard()
                }
                if page == .help {
                    WMButton(title: "重新听一遍使用引导", height: 61) { showGuide = true }
                }
            }
            .wmPageInset()
            .padding(.top, 12)
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showGuide) {
            OnboardingView { showGuide = false }.preferredColorScheme(.dark)
        }
        .wmDetailNavigationBar(title: page.title)
        .wmAnnounce(page.title)
    }
}
