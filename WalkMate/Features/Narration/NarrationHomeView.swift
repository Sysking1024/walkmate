import SwiftUI

/// 训练记录首页：走完「识别环境 → 朗读 → 生成短片 → 分享」的完整流程。
///
/// 无障碍要点（宪章原则四）：
/// - 按钮使用原生 `Button` 并直接携带文本，不额外嵌套语义包装（原生内聚）；
/// - 每条描述合并为单一语义容器，用中文逗号平铺朗读，防止焦点碎片化（边界阻断）；
/// - 交互控件触控目标不小于 48 点；
/// - 状态变化只更新文本内容，不做会打断读屏焦点的结构重排。
struct NarrationHomeView: View {

    @State private var model = TrainingRecordViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(model.phase.statusText)
                        .font(.headline)
                        .foregroundStyle(model.phase.isBusy ? .secondary : .primary)
                }

                if model.narrations.isEmpty {
                    Text("点击下方按钮，识别本次训练走过的环境并生成可分享的记录。")
                        .foregroundStyle(.secondary)
                } else {
                    Section("环境描述") {
                        ForEach(model.narrations) { narration in
                            narrationRow(narration)
                        }
                    }
                }
            }
            .navigationTitle("训练记录")
            .safeAreaInset(edge: .bottom) { bottomControls }
        }
    }

    /// 底部操作区。生成完成后才出现朗读与分享入口，避免无效控件占据读屏焦点。
    private var bottomControls: some View {
        VStack(spacing: 12) {
            Button(model.phase.isBusy ? model.phase.statusText : "生成训练记录") {
                Task { await model.generateRecord() }
            }
            .disabled(model.phase.isBusy)
            .frame(maxWidth: .infinity, minHeight: 48)
            .buttonStyle(.borderedProminent)

            if !model.narrations.isEmpty {
                Button("朗读全部描述") { model.speakAll() }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.bordered)
            }

            if let clipURL = model.clipURL {
                ShareLink(item: clipURL) {
                    Text("分享这段记录")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("把带语音朗读的短片分享给朋友")
            }
        }
        .padding()
        .background(.bar)
    }

    /// 单条描述行。整行合并为一个无障碍元素，按「序号，正文」的顺序平铺朗读。
    private func narrationRow(_ narration: SceneNarration) -> some View {
        Button {
            model.speak(narration)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(narration.source == .fallback ? "离线文案" : "环境描述")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(narration.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 48)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点两下朗读这段描述")
    }
}
