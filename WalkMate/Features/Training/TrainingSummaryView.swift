import AVKit
import SwiftUI

/// 训练总结页。对应设计稿「训练3」，并补上集锦生成、时刻回听与分享。
struct TrainingSummaryView: View {
    let result: TrainingResult
    let onDone: () -> Void
    /// 「查看我的成长」：收起流程并切到进度栏目
    let onViewGrowth: () -> Void

    @State private var reel = HighlightReelBuilder()
    @State private var player: AVPlayer?
    @State private var speech = SpeechRenderer()
    @State private var history = TrainingHistoryStore.shared
    @State private var routeSaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WMLogoHeader().padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    WMPageTitle(text: "今天又前进一步")
                    Text("你完成了\(result.kind.title)训练")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                }

                statGrid
                reelSection
                momentsSection
                achievementSection

                HStack(spacing: 14) {
                    WMButton(title: "查看我的成长", height: 61, action: onViewGrowth)
                    WMButton(title: routeSaved ? "已记录路线" : "记录路线", style: routeSaved ? .subdued : .primary, height: 61, action: saveRoute)
                        .disabled(routeSaved)
                }
                shareButton
            }
            .wmPageInset()
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            routeSaved = currentRecord?.savedAsRoute ?? false
            await reel.build(from: result.moments)
            if case .ready(let url) = reel.state { TrainingHistoryStore.keepAsLatestReel(url) }
        }
        .fullScreenCover(item: $player) { player in
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button("关闭") { self.player = nil }
                        .font(WalkMateTheme.Fonts.body)
                        .foregroundStyle(.white)
                        .frame(minWidth: 72, minHeight: 48)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding()
                }
                .onAppear { player.play() }
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
            ZStack(alignment: .bottomLeading) {
                if let cover = result.moments.first?.frameURL, let image = UIImage(contentsOfFile: cover.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image("journey_thumbnail").resizable().scaledToFill()
                }
                WalkMateTheme.Gradients.coverShade
                reelOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
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
                    Text("第一步 · FIRST STEP")
                        .font(WalkMateTheme.Fonts.body)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.7))
                    Text("首次完成任务")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .wmCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("新成就，第一步，首次完成任务")
        }
    }

    // MARK: - 分享

    @ViewBuilder private var shareButton: some View {
        if case .ready(let url) = reel.state {
            ShareLink(item: url) {
                Text("分享到同伴社群")
                    .font(WalkMateTheme.Fonts.body).tracking(1.6)
                    .foregroundStyle(Color(hex: 0xD9D9D9))
                    .frame(maxWidth: .infinity, minHeight: 61)
                    .wmCard(WalkMateTheme.Gradients.card, radius: WalkMateTheme.Radius.button, dimmed: true)
            }
            .accessibilityHint("把带语音朗读的集锦发给同伴")
        } else {
            WMButton(title: "分享到同伴社群", style: .subdued, height: 61) {}
                .disabled(true)
                .opacity(0.6)
        }
    }

    /// 训练结束时已写入的记录，按结束时间对上
    private var currentRecord: TrainingRecord? {
        history.records.first { $0.finishedAt == result.finishedAt }
    }

    /// 把这次训练标记为一条路线记录，进度页「室内训练路线」会列出
    private func saveRoute() {
        guard let record = currentRecord else { return }
        history.markAsRoute(record.id)
        routeSaved = true
        Log.info("已把训练记录为路线", category: .ui)
    }

    private static func dateText(_ date: Date, style: DateFormatter.Style = .long) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = style == .short ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

extension AVPlayer: @retroactive Identifiable {}
