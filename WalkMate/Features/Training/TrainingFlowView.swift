import SwiftUI

/// 训练栏目：列表 → 训练中 → 总结，在同一导航栈内推进
struct TrainingFlowView: View {
    @State private var path: [TrainingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            TrainingListView { path.append(.session) }
                .navigationDestination(for: TrainingRoute.self) { route in
                    switch route {
                    case .session:
                        TrainingSessionView { result in path.append(.summary(result)) }
                    case .summary(let result):
                        TrainingSummaryView(result: result) { path.removeAll() }
                    }
                }
        }
        .tint(WalkMateTheme.Colors.textPrimary)
    }
}

enum TrainingRoute: Hashable {
    case session
    case summary(TrainingResult)
}

/// 渐进式训练列表。对应设计稿「训练1」。
struct TrainingListView: View {
    let onStartIndoor: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                WMLogoHeader().padding(.top, 8)
                WMPageTitle(text: "渐进式训练")
                levelCard(title: "室内适应", subtitle: "indoor", detail: "静态障碍、方向判断、基础距离感", locked: false)
                levelCard(title: "半开放环境", subtitle: "Semi-open", detail: "小区、校园等相对可控的内部路线", locked: true)
                levelCard(title: "户外独立出行", subtitle: "Outdoor", detail: "真实步行环境中的动态风险与路线练习", locked: true)
            }
            .wmPageInset()
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func levelCard(title: String, subtitle: String, detail: String, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                Text("·")
                Text(subtitle)
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

            if locked {
                WMButton(title: "查看要求", style: .subdued, height: 47) {}
                    .padding(.top, 12)
            } else {
                WMButton(title: "开始训练", style: .white, height: 47, action: onStartIndoor)
                    .padding(.top, 12)
            }
        }
        .padding(WalkMateTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .leading)
        .wmCard(locked ? WalkMateTheme.Gradients.card : WalkMateTheme.Gradients.activeLevel, dimmed: locked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)，\(subtitle)，\(detail)\(locked ? "，尚未解锁" : "")")
    }
}
