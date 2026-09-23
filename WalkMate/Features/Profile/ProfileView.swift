import SwiftUI

/// 个人页占位，下一批按设计稿「Frame 7」完整实现
struct ProfileView: View {
    var body: some View {
        VStack(spacing: 22) {
            WMLogoHeader().padding(.top, 8)
            WMPageTitle(text: "个人")
            Spacer()
        }
        .wmPageInset()
    }
}
