// 语音意图解析检查。运行：cat WalkMate/Core/Conversation/VoiceIntent.swift Tests/NarrationTests/VoiceIntentChecks.swift | xcrun swift -
var failures = 0
func check(_ raw: String, _ window: VoiceIntent.Window, _ expected: VoiceIntent?) {
    let got = VoiceIntent.parse(raw, window: window)
    if got != expected { failures += 1; print("✗ 「\(raw)」\(window) → \(String(describing: got))，期望 \(String(describing: expected))") }
    else { print("✓ 「\(raw)」→ \(String(describing: got))") }
}
check("walkmate，告诉我周围有什么", .idle, .describe(question: nil))
check("Walk mate 说说周围", .idle, .describe(question: nil))
check("伴行，左手边是什么", .idle, .describe(question: "左手边是什么"))
check("今天天气不错", .idle, nil)
check("好", .awaitingConsent, .yes)
check("好的说吧", .awaitingConsent, .yes)
check("不用了", .awaitingConsent, .no)
check("不好", .awaitingConsent, .no)
check("右边有台阶吗", .awaitingFollowUp, .ask("右边有台阶吗"))
check("够了", .awaitingFollowUp, .stop)
check("walkmate 停", .idle, .stop)
check("停", .idle, nil)
check("随便聊聊", .busy, nil)
print(failures == 0 ? "全部通过" : "\(failures) 项失败")
