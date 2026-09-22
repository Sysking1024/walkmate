import SwiftUI

/// 场景描述首页：展示本次训练的图文时间线。
///
/// 无障碍要点（宪章原则四）：
/// - 按钮使用原生 `Button` 并直接携带文本，不额外嵌套语义包装（原生内聚）；
/// - 每条描述合并为单一语义容器，用中文逗号平铺朗读，防止焦点碎片化（边界阻断）；
/// - 交互控件触控目标不小于 48 点。
struct NarrationHomeView: View {

    /// 本次训练已生成的描述列表
    @State private var narrations: [SceneNarration] = []
    /// 是否正在生成描述
    @State private var isGenerating = false

    /// 当前采用的描述器。优先走多模态模型，异常时自动退回离线兜底文案。
    private let narrator: SceneNarrator = ResilientSceneNarrator()

    var body: some View {
        NavigationStack {
            List {
                if narrations.isEmpty {
                    Text("还没有记录。点击下方按钮生成本次训练的描述。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(narrations) { narration in
                        narrationRow(narration)
                    }
                }
            }
            .navigationTitle("训练记录")
            .safeAreaInset(edge: .bottom) {
                Button(isGenerating ? "正在生成描述" : "生成本次训练描述") {
                    Task { await generateNarrations() }
                }
                .disabled(isGenerating)
                .frame(maxWidth: .infinity, minHeight: 48)
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }

    /// 单条描述行。整行合并为一个无障碍元素，按「时间，正文」的顺序平铺朗读。
    private func narrationRow(_ narration: SceneNarration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedOffset(narration.offsetMs))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(narration.text)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formattedOffset(narration.offsetMs))，\(narration.text)")
    }

    /// 把毫秒偏移格式化为「第 X 分 Y 秒」，便于读屏顺畅朗读
    private func formattedOffset(_ offsetMs: Int) -> String {
        let totalSeconds = offsetMs / 1_000
        return "第 \(totalSeconds / 60) 分 \(totalSeconds % 60) 秒"
    }

    /// 生成描述。
    ///
    /// 相机管线接通前，先用工程内置的全景样张验证全链路。
    /// 单次模型调用实测约 11 至 13 秒，因此多帧并发请求，避免串行等待。
    private func generateNarrations() async {
        isGenerating = true
        defer { isGenerating = false }

        guard let frameData = loadSampleFrameData() else {
            Log.error(.narration, "未找到内置全景样张，无法生成描述")
            return
        }

        // 并发发起各帧请求，再按时间偏移归位，总耗时约等于单帧耗时
        let produced = await withTaskGroup(of: SceneNarration?.self) { group in
            for index in 0..<2 {
                group.addTask {
                    do {
                        return try await narrator.describe(
                            frameData: frameData,
                            offsetMs: index * 8_000,
                            frameFileName: "frame_\(index).jpg"
                        )
                    } catch {
                        Log.error(.narration, "生成第 \(index) 条描述失败：\(error)")
                        return nil
                    }
                }
            }
            var collected: [SceneNarration] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected.sorted { $0.offsetMs < $1.offsetMs }
        }

        narrations = produced
        Log.info(.narration, "本次训练共生成 \(produced.count) 条描述")
    }

    /// 读取工程内置的全景样张，用于相机接通前的链路验证
    private func loadSampleFrameData() -> Data? {
        guard let url = Bundle.main.url(forResource: "pano_sample", withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: url)
    }
}
