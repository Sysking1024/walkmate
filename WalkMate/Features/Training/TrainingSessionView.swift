import SwiftUI

/// 训练中页面。对应设计稿「训练2」，并在相机画面与结束按钮之间加入伙伴对谈卡。
///
/// 相机预览与障碍数据来自避障线的 `CameraViewModel`；计时、距离、避障计数与伙伴会话由 `TrainingSessionModel` 托管。
struct TrainingSessionView: View {
    let kind: TrainingKind
    let onFinish: (TrainingResult) -> Void

    @StateObject private var camera = CameraViewModel()
    @State private var session: TrainingSessionModel

    init(kind: TrainingKind, onFinish: @escaping (TrainingResult) -> Void) {
        self.kind = kind
        self.onFinish = onFinish
        _session = State(initialValue: TrainingSessionModel(kind: kind))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                WMLogoHeader().padding(.top, 8)
                WMPageTitle(text: kind.title)

                HStack(spacing: 14) {
                    WMStatTile(label: "训练时间", value: session.elapsedText)
                    WMStatTile(label: "成功避障", value: "\(session.obstaclesAvoided)")
                }

                cameraCard
                CompanionPanel(session: session.companion)

                WMButton(title: "结束训练", height: 61) {
                    let result = session.finish()
                    if camera.connectionState == .connected { camera.toggleConnection() }
                    TrainingHistoryStore.shared.record(result)
                    onFinish(result)
                }
            }
            .wmPageInset()
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            session.start()
            AccessibilityFeedback.screenChanged("\(kind.title)训练")
        }
        .onChange(of: camera.latestObstacles?.obstacles.count ?? 0) { _, count in
            session.updateObstacleCount(count)
        }
        // 相机一连上就开启队友的空间感知与避障提示音，训练里不用再多按一个键
        .onChange(of: camera.connectionState) { _, state in
            if state == .connected { camera.startPerception() }
        }
    }

    /// 相机画面卡。未连接时显示示意图与连接按钮，连接后显示实时预览。
    private var cameraCard: some View {
        ZStack {
            if camera.connectionState == .connected, let preview = camera.previewView {
                CameraPreviewRepresentable(previewView: preview)
            } else {
                Image("training_camera_sample")
                    .resizable().scaledToFill()
                    .overlay(Color.black.opacity(0.35))
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text(cameraStatusText)
                        .font(WalkMateTheme.Fonts.body)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    WMButton(title: camera.connectionState == .connecting ? "正在连接" : "连接相机", height: 48) {
                        camera.toggleConnection()
                    }
                    .frame(width: 200)
                    .disabled(camera.connectionState == .connecting)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.card, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if camera.connectionState == .connected {
                Text(camera.isPerceiving ? "已连接 · 避障中" : "已连接")
                    .font(WalkMateTheme.Fonts.chip)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(camera.connectionState == .connected ? "相机画面，已连接" : "相机画面，\(cameraStatusText)")
    }

    private var cameraStatusText: String {
        switch camera.connectionState {
        case .noConnection: return "先把手机连上相机热点，再连接相机"
        case .connecting: return "正在连接相机"
        case .failed: return camera.latestError ?? "连接失败，检查是否已连上相机热点"
        case .connected: return "已连接"
        }
    }
}

/// 伙伴对谈卡：随对谈阶段切换内容与操作
struct CompanionPanel: View {
    @Bindable var session: CompanionSession
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("伙伴")
                    .font(WalkMateTheme.Fonts.body)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                Spacer()
                if !session.moments.isEmpty {
                    Text("已留下 \(session.moments.count) 个时刻")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                }
            }

            Text(statusText)
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            controls
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard()
    }

    private var statusText: String {
        if session.isBusy { return "伙伴正在看周围……" }
        switch session.stage {
        case .silent:
            return session.hasFrames
                ? "伙伴在旁。停下来 3 秒，它会问你要不要听听周围。"
                : "相机连上后，伙伴会陪着你。"
        case .awaitingConsent: return "要我说说这儿吗？"
        case .describing, .answering, .awaitingFollowUp:
            return session.transcript.last(where: { $0.speaker == .companion })?.text ?? ""
        }
    }

    @ViewBuilder private var controls: some View {
        switch session.stage {
        case .silent:
            WMButton(title: "说说这儿", height: 48) { session.describeNow() }
                .disabled(!session.hasFrames)
                .opacity(session.hasFrames ? 1 : 0.5)
        case .awaitingConsent:
            HStack(spacing: 12) {
                WMButton(title: "好", height: 48) { session.accept() }
                WMButton(title: "不用", style: .subdued, height: 48) { session.decline() }
            }
        case .describing, .answering:
            WMButton(title: "停下", style: .subdued, height: 48) { session.dismiss() }
        case .awaitingFollowUp:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("想问什么", text: $question)
                        .textFieldStyle(.plain)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                        .onSubmit(submit)
                    WMButton(title: "问", height: 48, action: submit)
                        .frame(width: 72)
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                WMButton(title: "够了", style: .subdued, height: 48) { session.dismiss() }
            }
        }
    }

    private func submit() {
        session.ask(question)
        question = ""
    }
}
