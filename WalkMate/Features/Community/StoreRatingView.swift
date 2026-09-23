import SwiftUI

/// 店铺无障碍打分页。设计稿未包含此页，按同一视觉语言补充。
///
/// 无障碍要点：五颗星对读屏是一个可调节元素（上下滑动改分数），
/// 而不是五个零散按钮；标签是原生切换按钮；所有控件触控目标不小于 48 点。
struct StoreRatingView: View {
    let store: StoreSummary
    /// 提交成功或点关闭时调用，由外层收起弹层
    let onClose: () -> Void

    @State private var score = 0
    @State private var selectedTags: Set<String> = []
    @State private var comment = ""
    @State private var submitted = false
    @State private var ratingStore = StoreRatingStore.shared
    /// 是否在修改已有评分
    private var isUpdating: Bool { ratingStore.myRating(for: store.id) != nil }

    /// 可选的无障碍特性，沿用探店卡片上的标签体系并扩充
    private let tags = ["无障碍入口", "方便独立前往", "店内安静", "无障碍卫生间", "店员友善", "有盲道", "菜单可朗读", "允许导盲犬"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        WMPageTitle(text: isUpdating ? "修改对\(store.name)的评分" : "为\(store.name)打分")
                        Text("你的体验会帮到下一位独立前往的同伴")
                            .font(WalkMateTheme.Fonts.caption)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                    }
                    scoreCard
                    tagCard
                    commentCard
                    WMButton(title: submitted ? "已提交，谢谢你" : (isUpdating ? "更新评分" : "提交评分"), height: 61, action: submit)
                        .disabled(score == 0 || submitted)
                        .opacity(score == 0 && !submitted ? 0.5 : 1)
                }
                .wmPageInset()
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(WalkMateTheme.Colors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onClose() }
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                        .frame(minWidth: 48, minHeight: 48)
                }
            }
            .toolbarBackground(WalkMateTheme.Colors.background, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            AccessibilityFeedback.screenChanged(isUpdating ? "修改评分" : "为\(store.name)打分")
            if let mine = ratingStore.myRating(for: store.id), score == 0 {
                score = mine.score
                selectedTags = Set(mine.tags)
                comment = mine.comment
            }
        }
    }

    // MARK: - 总体评分

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("总体无障碍评分")
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button { score = star } label: {
                        Image("icon_star")
                            .resizable().scaledToFit()
                            .frame(width: 34, height: 34)
                            .foregroundStyle(star <= score ? WalkMateTheme.Colors.accentSoft : Color.white.opacity(0.25))
                            .frame(maxWidth: .infinity, minHeight: WalkMateTheme.Layout.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("总体无障碍评分")
            .accessibilityValue(score == 0 ? "尚未评分" : "\(score) 星，共 5 星")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: score = min(5, score + 1)
                case .decrement: score = max(1, score - 1)
                @unknown default: break
                }
            }
            Text(scoreHint)
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard(WalkMateTheme.Gradients.storeCard)
    }

    private var scoreHint: String {
        switch score {
        case 0: return "点一颗星，或在读屏模式下上下滑动调整"
        case 1: return "很难独立前往"
        case 2: return "需要不少帮助"
        case 3: return "基本可以应付"
        case 4: return "比较顺利"
        default: return "非常友好，推荐给同伴"
        }
    }

    // MARK: - 无障碍标签

    private var tagCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("这家店做得好的地方")
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            let rows = stride(from: 0, to: tags.count, by: 2).map { Array(tags[$0..<min($0 + 2, tags.count)]) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { tag in
                        let selected = selectedTags.contains(tag)
                        Button {
                            if selected { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                        } label: {
                            HStack(spacing: 6) {
                                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                                Text(tag)
                            }
                            .font(WalkMateTheme.Fonts.caption)
                            .foregroundStyle(selected ? WalkMateTheme.Colors.chipText : WalkMateTheme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: WalkMateTheme.Layout.minimumTapTarget)
                            .background(selected ? WalkMateTheme.Colors.chipBackground : Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard()
    }

    // MARK: - 一句话评价

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("一句话评价（可选）")
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            HStack(spacing: 10) {
                TextField("比如：门口有两级台阶，店员会主动引导", text: $comment, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                // 语音输入留待接入语音识别，先保留入口位置
                Button {} label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("语音输入")
                .disabled(true)
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wmCard()
    }

    private func submit() {
        let rating = StoreRating(
            storeID: store.id,
            score: score,
            tags: Array(selectedTags),
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )
        submitted = true
        AccessibilityFeedback.done("已提交 \(score) 星评分")
        Task {
            await ratingStore.submit(rating)
            try? await Task.sleep(nanoseconds: 700_000_000)
            onClose()
        }
    }
}
