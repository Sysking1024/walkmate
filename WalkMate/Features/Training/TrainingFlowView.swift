import SwiftUI

/// 训练栏目：列表 → 训练中 → 总结，在同一导航栈内推进
struct TrainingFlowView: View {
    @State private var path: [TrainingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            TrainingListView { kind in path.append(.session(kind)) }
                .navigationDestination(for: TrainingRoute.self) { route in
                    switch route {
                    case .session(let kind):
                        TrainingSessionView(kind: kind) { result in path.append(.summary(result)) }
                    case .summary(let result):
                        TrainingSummaryView(result: result) { path.removeAll() }
                    }
                }
        }
        .tint(WalkMateTheme.Colors.textPrimary)
    }
}

enum TrainingRoute: Hashable {
    case session(TrainingKind)
    case summary(TrainingResult)
}

/// 渐进式训练列表。已解锁的档位有「开始训练」按钮；未解锁的只写一行解锁条件，不放按钮。
struct TrainingListView: View {
    let onStart: (TrainingKind) -> Void

    @State private var history = TrainingHistoryStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                WMLogoHeader().padding(.top, 8)
                WMPageTitle(text: "渐进式训练")
                levelCard(title: "室内适应", detail: "静态障碍、方向判断、基础距离感", kind: .indoor, unlockHint: nil)
                levelCard(title: "半开放环境", detail: "小区、校园等相对可控的路线",
                          kind: history.isSemiOpenUnlocked ? .neighborhood : nil,
                          unlockHint: "完成 5 次室内训练，其中 3 次避障不少于 10 次")
                levelCard(title: "户外独立出行", detail: "真实街道上的动态风险与路线练习",
                          kind: nil,
                          unlockHint: "完成 5 次小区路线")
            }
            .wmPageInset()
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// `kind` 为 nil 表示未解锁
    private func levelCard(title: String, detail: String, kind: TrainingKind?, unlockHint: String?) -> some View {
        let locked = kind == nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                if locked {
                    Image("icon_lock").resizable().scaledToFit().frame(width: 18)
                        .foregroundStyle(WalkMateTheme.Colors.textMuted)
                }
            }
            .font(WalkMateTheme.Fonts.body)
            .foregroundStyle(locked ? WalkMateTheme.Colors.textMuted : WalkMateTheme.Colors.textPrimary)

            Text(detail)
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle((locked ? WalkMateTheme.Colors.textMuted : WalkMateTheme.Colors.textPrimary).opacity(0.72))

            if let kind {
                WMButton(title: "开始训练", style: .white, height: 47) { onStart(kind) }
                    .padding(.top, 12)
            } else if let unlockHint {
                Text("解锁条件：\(unlockHint)")
                    .font(WalkMateTheme.Fonts.caption)
                    .foregroundStyle(WalkMateTheme.Colors.textMuted)
                    .padding(.top, 8)
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .wmCard(locked ? WalkMateTheme.Gradients.card : WalkMateTheme.Gradients.activeLevel, dimmed: locked)
        .accessibilityElement(children: locked ? .ignore : .contain)
        .accessibilityLabel(locked ? "\(title)，未解锁。解锁条件：\(unlockHint ?? "")" : "\(title)，\(detail)")
    }
}
