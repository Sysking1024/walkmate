import SwiftUI

/// 伙伴页：实时对谈的临时界面，待 UI 设计稿确定后替换。
///
/// 无障碍要点：控件均为原生 `Button`，触控目标不小于 48 点；
/// 对话记录每条合并为单一语义元素，按「说话人，内容」朗读。
struct CompanionView: View {

    @State private var session = CompanionSession()
    @State private var question = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(statusText).font(.headline)
                    if !session.hasFrames {
                        Text("还没有相机画面。先在「出行」页连接相机。").foregroundStyle(.secondary)
                    } else {
                        Text("已静止 \(session.standstillMs / 1_000) 秒").foregroundStyle(.secondary)
                    }
                }

                if !session.transcript.isEmpty {
                    Section("对话") {
                        ForEach(session.transcript) { turn in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(turn.speaker == .companion ? "伙伴" : "我")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(turn.text)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("调试") {
                    Button("保存当前帧") { session.saveCurrentFrameForDebug() }
                        .frame(minHeight: 48)
                    if let note = session.savedFrameNote {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("伙伴")
            .safeAreaInset(edge: .bottom) { controls }
        }
        .onAppear { session.start() }
    }

    private var statusText: String {
        if session.isBusy { return "伙伴正在看……" }
        switch session.stage {
        case .silent: return "安静陪伴中"
        case .awaitingConsent: return "伙伴在问：要我说说这儿吗？"
        case .describing: return "伙伴正在描述"
        case .awaitingFollowUp: return "可以继续问"
        case .answering: return "伙伴正在回答"
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            switch session.stage {
            case .awaitingConsent:
                HStack(spacing: 12) {
                    Button("好") { session.accept() }
                        .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.borderedProminent)
                    Button("不用") { session.decline() }
                        .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.bordered)
                }
            case .awaitingFollowUp:
                HStack(spacing: 8) {
                    TextField("想问什么", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 48)
                        .onSubmit(submitQuestion)
                    Button("问") { submitQuestion() }
                        .frame(minHeight: 48).buttonStyle(.borderedProminent)
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("够了") { session.dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.bordered)
            case .describing, .answering:
                Button("停下") { session.dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.bordered)
            case .silent:
                Button("说说这儿") { session.describeNow() }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.borderedProminent)
                    .disabled(!session.hasFrames)
            }
        }
        .padding()
        .background(.bar)
    }

    private func submitQuestion() {
        session.ask(question)
        question = ""
    }
}
