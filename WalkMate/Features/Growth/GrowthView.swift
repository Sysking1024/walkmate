import SwiftUI

/// 进度页占位，下一批按设计稿「进度」完整实现
struct GrowthView: View {
    var body: some View {
        VStack(spacing: 22) {
            WMLogoHeader().padding(.top, 8)
            WMPageTitle(text: "你的康复成长")
            Spacer()
        }
        .wmPageInset()
    }
}
