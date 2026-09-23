import SwiftUI

/// 训练栏目：列表 → 训练中 → 总结，在同一导航栈内推进
struct TrainingFlowView: View {
    /// 总结页「查看我的成长」：收起训练流程并切到进度栏目
    let onViewGrowth: () -> Void

    @State private var path: [TrainingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            TrainingListView { path.append(.session) }
                .navigationDestination(for: TrainingRoute.self) { route in
                    switch route {
                    case .session:
                        TrainingSessionView { result in path.append(.summary(result)) }
                    case .summary(let result):
                        TrainingSummaryView(result: result, onDone: { path.removeAll() }, onViewGrowth: {
                            path.removeAll()
                            onViewGrowth()
                        })
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

    /// 正在查看要求的档位
    @State private var requirementLevel: LockedLevel?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                WMLogoHeader().padding(.top, 8)
                WMPageTitle(text: "渐进式训练")
                levelCard(title: "室内适应", subtitle: "indoor", detail: "静态障碍、方向判断、基础距离感", locked: false)
                levelCard(title: "半开放环境", subtitle: "Semi-open", detail: "小区、校园等相对可控的内部路线", locked: true, level: .semiOpen)
                levelCard(title: "户外独立出行", subtitle: "Outdoor", detail: "真实步行环境中的动态风险与路线练习", locked: true, level: .outdoor)
            }
            .wmPageInset()
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .alert(item: $requirementLevel) { level in
            Alert(title: Text("\(level.title) · 解锁要求"), message: Text(level.requirement), dismissButton: .default(Text("知道了")))
        }
    }

    private func levelCard(title: String, subtitle: String, detail: String, locked: Bool, level: LockedLevel? = nil) -> some View {
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
                WMButton(title: "查看要求", style: .subdued, height: 47) { requirementLevel = level }
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

/// 尚未解锁的训练档位及其解锁要求
enum LockedLevel: Identifiable {
    case semiOpen, outdoor

    var id: Self { self }

    var title: String {
        switch self {
        case .semiOpen: return "半开放环境"
        case .outdoor: return "户外独立出行"
        }
    }

    var requirement: String {
        switch self {
        case .semiOpen: return "完成 5 次室内训练，其中至少 3 次成功避障不少于 10 次。"
        case .outdoor: return "完成 5 次半开放环境训练，并在小区路线上独立走完 3 次。"
        }
    }
}
