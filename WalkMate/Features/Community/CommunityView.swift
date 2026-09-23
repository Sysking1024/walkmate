import SwiftUI

/// 社群页占位，下一批按设计稿「社群」完整实现
struct CommunityView: View {
    var body: some View {
        VStack(spacing: 22) {
            WMLogoHeader().padding(.top, 8)
            WMPageTitle(text: "好友今日成就榜")
            Spacer()
        }
        .wmPageInset()
    }
}
