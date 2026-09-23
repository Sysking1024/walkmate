import AVKit
import SwiftUI

/// 训练总结页。对应设计稿「训练3」，并补上集锦生成、时刻回听与分享。
struct TrainingSummaryView: View {
    let result: TrainingResult
    let onDone: () -> Void

    @State private var reel = HighlightReelBuilder()
    @State private var player: AVPlayer?
    @State private var speech = SpeechRenderer()
    @State private var history = TrainingHistoryStore.shared
    @State private var community = CommunityStore.shared
    @State private var sharing = false
    /// 集锦去留：nil 未决定
    @State private var reelKept: Bool?
    @State private var confirmLeave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WMLogoHeader(pageName: "训练总结").padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    WMPageTitle(text: "今天又前进一步")
                    Text("你完成了\(result.kind.title)训练")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                }

                statGrid
                reelSection
                momentsSection
                if history.records(of: result.kind).count == 1 { achievementSection }

                shareButton
                WMButton(title: "完成", height: 61, action: finish)
            }
            .wmPageInset()
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { AccessibilityFeedback.pageSwitched() }
        .task {
            await reel.build(from: result.moments)
            if case .ready = reel.state, currentRecord?.reelFileName != nil { reelKept = true }
        }
        .alert("这段集锦要留下吗？", isPresented: $confirmLeave) {
            Button("保存并分享到社群") { if case .ready(let url) = reel.state { keepAndShare(url) }; onDone() }
            Button("不要了，删掉", role: .destructive) { discardReel(); onDone() }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("不保存的话视频会直接删除。")
        }
        .fullScreenCover(item: $player) { player in
            ReelPlayerView(player: player) { self.player = nil }
        }
    }

    private var statGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                WMStatTile(label: "训练时间", value: String(format: "%02d:%02d", result.durationSeconds / 60, result.durationSeconds % 60))
                WMStatTile(label: "行走距离", value: "\(result.distanceMeters)m")
            }
            HStack(spacing: 14) {
                WMStatTile(label: "成功避障", value: "\(result.obstaclesAvoided)")
                WMStatTile(label: "独立完成指数", value: "\(Int(history.independentRate * 100))%")
            }
        }
    }

    // MARK: - 视频集锦

    private var reelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WMSectionHeader(title: "视频集锦")
            WMCoverImage(image: result.moments.first.flatMap { UIImage(contentsOfFile: $0.frameURL.path) }, fallback: "journey_thumbnail", height: 200)
                .overlay { WalkMateTheme.Gradients.coverShade }
                .overlay(alignment: .bottomLeading) { reelOverlay }
                .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private var reelOverlay: some View {
        switch reel.state {
        case .idle where result.moments.isEmpty:
            caption(title: "这次没停下来听描述", subtitle: "下次驻足时试试，伙伴会把那一刻留下来")
        case .idle, .rendering:
            VStack(alignment: .leading, spacing: 8) {
                caption(title: "正在把 \(result.moments.count) 个时刻剪成短片", subtitle: reelStepText)
                ProgressView().tint(WalkMateTheme.Colors.accentSoft).padding(.leading, 20).padding(.bottom, 16)
            }
        case .ready(let url):
            HStack(alignment: .bottom) {
                caption(title: reelTitle, subtitle: Self.dateText(result.finishedAt))
                Spacer()
                Button {
                    player = AVPlayer(url: url)
                } label: {
                    Image("icon_play").resizable().scaledToFit().frame(width: 41, height: 41)
                        .frame(minWidth: 48, minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放集锦")
                .padding(.trailing, 16).padding(.bottom, 12)
            }
        case .failed(let message):
            caption(title: message, subtitle: "时刻已经留下，可以在下面逐条回听")
        }
    }

    private func caption(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(WalkMateTheme.Fonts.body).foregroundStyle(.white)
            Text(subtitle).font(WalkMateTheme.Fonts.caption).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.leading, 20).padding(.bottom, 16)
    }

    private var reelStepText: String {
        if case .rendering(let step) = reel.state { return step }
        return "准备中"
    }

    private var reelTitle: String { "\(Self.dateText(result.finishedAt, style: .short)) · \(result.kind.title)" }

    // MARK: - 本次的时刻（回听）

    @ViewBuilder private var momentsSection: some View {
        if !result.moments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WMSectionHeader(title: "本次的时刻")
                VStack(spacing: 0) {
                    ForEach(Array(result.moments.enumerated()), id: \.element.id) { index, moment in
                        Button {
                            speech.speak(moment.narration.text)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(WalkMateTheme.Fonts.statValue)
                                    .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                                    .frame(width: 24, alignment: .leading)
                                Text(moment.narration.text)
                                    .font(WalkMateTheme.Fonts.caption)
                                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("轻点两下重新朗读")
                        if index < result.moments.count - 1 {
                            Divider().overlay(WalkMateTheme.Colors.divider)
                        }
                    }
                }
                .padding(.horizontal, WalkMateTheme.Layout.cardPadding)
                .padding(.vertical, 6)
                .wmCard()
            }
        }
    }

    // MARK: - 新成就

    private var achievementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WMSectionHeader(title: "新成就")
            HStack(spacing: 16) {
                Image("badge_first_step").resizable().scaledToFit().frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text("第一步")
                        .font(WalkMateTheme.Fonts.body)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.7))
                    Text("首次完成\(result.kind.title)")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .wmCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("新成就，第一步，首次完成\(result.kind.title)")
        }
    }

    // MARK: - 分享

    /// 集锦剪好后先问要不要留：留下就保存并分享到社群，不留就删掉
    @ViewBuilder private var shareButton: some View {
        if case .ready(let url) = reel.state {
            switch reelKept {
            case nil:
                VStack(spacing: 10) {
                    Text("这段集锦要留下吗？")
                        .font(WalkMateTheme.Fonts.body)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 14) {
                        WMButton(title: sharing ? "正在保存" : "保存并分享到社群", height: 61) { keepAndShare(url) }
                            .disabled(sharing)
                        WMButton(title: "不要了", style: .subdued, height: 61, action: discardReel)
                    }
                }
            case true?:
                Text("已保存并分享到社群")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                    .frame(maxWidth: .infinity, minHeight: 48)
                ShareLink(item: url) {
                    Text("发给朋友")
                        .font(WalkMateTheme.Fonts.body).tracking(1.6)
                        .foregroundStyle(Color(hex: 0xD9D9D9))
                        .frame(maxWidth: .infinity, minHeight: 61)
                        .wmCard(WalkMateTheme.Gradients.card, radius: WalkMateTheme.Radius.button, dimmed: true)
                }
                .accessibilityHint("用系统分享把集锦发给同伴")
            case false?:
                Text("集锦已删除")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
    }

    /// 点「完成」：集锦还没决定去留就先问一句
    private func finish() {
        if case .ready = reel.state, reelKept == nil { confirmLeave = true } else { onDone() }
    }

    /// 保存到记录、分享到社群
    private func keepAndShare(_ reelURL: URL) {
        guard let record = currentRecord else { return }
        sharing = true
        history.attachReel(reelURL, toRecordFinishedAt: result.finishedAt)
        Task {
            let saved = history.records.first { $0.id == record.id } ?? record
            let url = TrainingHistoryStore.reelURL(for: saved) ?? reelURL
            await community.shareJourney(record: saved, reelURL: url)
            sharing = false
            reelKept = true
            AccessibilityFeedback.done("已保存并分享到社群")
        }
    }

    /// 不要这段集锦：删掉临时文件
    private func discardReel() {
        if case .ready(let url) = reel.state { try? FileManager.default.removeItem(at: url) }
        reelKept = false
        AccessibilityFeedback.done("集锦已删除")
        Log.info("使用者放弃了这次的集锦", category: .recording)
    }

    private var currentRecord: TrainingRecord? {
        history.records.first { $0.finishedAt == result.finishedAt }
    }

    private static func dateText(_ date: Date, style: DateFormatter.Style = .long) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = style == .short ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

extension AVPlayer: @retroactive Identifiable {}

/// 全屏集锦播放，右上角一个关闭按钮
struct ReelPlayerView: View {
    let player: AVPlayer
    let onClose: () -> Void

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("关闭", action: onClose)
                    .font(WalkMateTheme.Fonts.body)
                    .foregroundStyle(.white)
                    .frame(minWidth: 72, minHeight: 48)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding()
            }
            .task {
                SpeechRenderer.activatePlaybackSession()
                // 开着读屏时，读屏会先播报页面，等它说完再开始，免得盖住视频里的声音
                let delay: UInt64 = UIAccessibility.isVoiceOverRunning ? 3_000_000_000 : 300_000_000
                try? await Task.sleep(nanoseconds: delay)
                player.play()
            }
            .onAppear { AccessibilityFeedback.screenChanged("视频播放") }
            .onDisappear { player.pause() }
    }
}
