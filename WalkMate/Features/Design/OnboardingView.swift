import SwiftUI

/// 首次启动的使用引导：三页，只有「下一步」和「跳过」两个按钮。读屏交给系统旁白。
/// 设置里的「帮助」可以重新打开。
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var index = 0

    private let pages: [(title: String, body: String)] = [
        ("你好，我是伴行",
         "先在家里练避障，再走小区，最后走上街道。手机连上全景相机，它就是你的眼睛。"),
        ("训练时怎么用",
         "训练页按「开始训练」，再按「连接相机」。停下三秒，它会问「要我说说这儿吗」。答「好」就听，答「不用」就安静。"),
        ("用旁白读屏",
         "打开系统旁白，每页第一个就是主要按钮。语音、语速、字体、目标都在「个人」页。"),
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
    }

    private func next() {
        if index < pages.count - 1 { index += 1 } else { finish() }
    }

    private func finish() {
        AppSettings.shared.hasSeenGuide = true
        onFinish()
    }
}
