import SwiftUI

/// 添加好友（演示）：搜索框 + 推荐列表，点「添加」记为已发送请求，只存本地
struct AddFriendView: View {
    @State private var query = ""
    @State private var sent: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "walkmate.friendRequests") ?? [])

    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let note: String
        let avatarKey: String?
    }

    /// 演示用的推荐名单
    private let candidates = [
        Candidate(id: "u_ming", name: "Ming", note: "刚解锁第 100 次避障", avatarKey: nil),
        Candidate(id: "u_xiaoyu", name: "小雨", note: "同在仙林，常去金鹰", avatarKey: nil),
        Candidate(id: "u_ajie", name: "阿杰", note: "户外独立出行 Level 5", avatarKey: nil),
        Candidate(id: "u_lin", name: "林姐", note: "康复训练师", avatarKey: nil),
    ]

    private var filtered: [Candidate] {
        let key = query.trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? candidates : candidates.filter { $0.name.localizedCaseInsensitiveContains(key) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WMPageTitle(text: "添加好友")
                TextField("输入昵称或手机号", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.button, style: .continuous))
                    .accessibilityLabel("搜索好友")

                WMSectionHeader(title: "可能认识的人")
                if filtered.isEmpty {
                    Text("没有找到「\(query)」，检查一下昵称或手机号")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                        .padding(WalkMateTheme.Layout.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wmCard()
                }
                ForEach(filtered) { candidate in
                    row(candidate)
                }
            }
            .wmPageInset()
            .padding(.top, 12)
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .wmDetailNavigationBar(title: "添加好友")
    }

    private func row(_ candidate: Candidate) -> some View {
        let isSent = sent.contains(candidate.id)
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.25))
                Text(String(candidate.name.prefix(1))).font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.name).font(WalkMateTheme.Fonts.body).foregroundStyle(WalkMateTheme.Colors.textPrimary)
                Text(candidate.note).font(WalkMateTheme.Fonts.caption).foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
            }
            Spacer()
            Button(isSent ? "已发送" : "添加") { send(candidate) }
                .buttonStyle(GreenPillButtonStyle(opacity: isSent ? 0.25 : 0.6))
                .frame(width: 96)
                .disabled(isSent)
                .accessibilityLabel(isSent ? "已向 \(candidate.name) 发送好友请求" : "添加 \(candidate.name) 为好友")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 80)
        .wmCard()
    }

    private func send(_ candidate: Candidate) {
        sent.insert(candidate.id)
        UserDefaults.standard.set(Array(sent), forKey: "walkmate.friendRequests")
        AccessibilityFeedback.done("已向 \(candidate.name) 发送好友请求")
        Log.info("已发送好友请求：\(candidate.name)", category: .ui)
    }
}
