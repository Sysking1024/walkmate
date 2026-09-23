import SwiftUI

/// 首次启动的使用引导：三页，每页自动朗读，只有「下一步」和「跳过」两个按钮。
/// 设置里的「帮助」可以重新打开。
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var index = 0

    private let pages: [(title: String, body: String)] = [
        ("你好，我是伴行",
         "伴行帮你一步步找回独立出行的信心。先在家里练避障，再走小区，最后走上真实的街道。手机连上全景相机，它就是你的眼睛。"),
        ("训练时怎么用",
         "在训练页按「开始训练」，再按「连接相机」。走动时它安静陪着你；停下来三秒，它会问「要我说说这儿吗」。答「好」就听描述，答「不用」它就不打扰。"),
        ("听得懂每一页",
         "每进入一页，伴行会先说这页有什么。开了旁白读屏就交给旁白。在「个人」页可以调语音引导、语速、字体大小和训练目标。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            WMLogoHeader().padding(.top, 20)
            Spacer()
            Text("\(index + 1) / \(pages.count)")
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
            Text(pages[index].title)
                .font(WalkMateTheme.Fonts.pageTitle)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(pages[index].body)
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(6)
                .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            WMButton(title: index == pages.count - 1 ? "开始使用" : "下一步", height: 61, action: next)
            Button("跳过引导", action: finish)
                .font(WalkMateTheme.Fonts.body)
                .foregroundStyle(WalkMateTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: WalkMateTheme.Layout.minimumTapTarget)
                .padding(.bottom, 12)
        }
        .wmPageInset()
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .onAppear(perform: speakCurrent)
        .onChange(of: index) { _, _ in speakCurrent() }
    }

    private func speakCurrent() {
        PageNarrator.shared.announce("\(pages[index].title)。\(pages[index].body)", force: true)
    }

    private func next() {
        if index < pages.count - 1 { index += 1 } else { finish() }
    }

    private func finish() {
        PageNarrator.shared.stop()
        AppSettings.shared.hasSeenGuide = true
        onFinish()
    }
}

extension View {
    /// 页面出现时朗读一段说明
    func wmAnnounce(_ text: @escaping @autoclosure () -> String) -> some View {
        onAppear { PageNarrator.shared.announce(text()) }
    }
}
