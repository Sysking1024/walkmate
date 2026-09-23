import SwiftUI

/// 个人与设置页。对应设计稿「Frame 7」。
struct ProfileView: View {
    @State private var guidance: Double = 0.5
    @State private var speed: Double = 0.75
    @State private var textSize: Double = 0.58

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WMLogoHeader().padding(.top, 8)
                WMSectionHeader(title: "个人")
                profileCard
                WMSectionHeader(title: "设置").padding(.top, 8)
                settingsCard
            }
            .wmPageInset()
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var profileCard: some View {
        HStack(spacing: 20) {
            WMAvatar(imageName: "avatar_doris", size: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text("Doris").font(.system(size: 20, weight: .medium))
                Text("喜欢探索户外").font(WalkMateTheme.Fonts.caption)
            }
            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 107, alignment: .leading)
        .wmCard(WalkMateTheme.Gradients.activeLevel)
        .accessibilityElement(children: .combine)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sliderRow("语音引导", value: $guidance, labels: ["详细", "简洁", "静音"], hint: "简洁：减少语言，强化方向声音")
            divider
            sliderRow("语速", value: $speed)
            divider
            sliderRow("字体大小", value: $textSize)
            divider
            navRow("音量键设置")
            divider
            navRow("联系客服")
            divider
            navRow("帮助")
            divider
            navRow("关于我们")
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .wmCard(WalkMateTheme.Gradients.card, dimmed: true)
    }

    private var divider: some View { Divider().overlay(WalkMateTheme.Colors.divider) }

    private func sliderRow(_ title: String, value: Binding<Double>, labels: [String]? = nil, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(WalkMateTheme.Fonts.body).foregroundStyle(.white)
            Slider(value: value)
                .tint(WalkMateTheme.Colors.sliderFill)
                .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
                .accessibilityLabel(title)
            if let labels {
                HStack {
                    ForEach(labels, id: \.self) { label in
                        Text(label).frame(maxWidth: .infinity, alignment: label == labels.first ? .leading : (label == labels.last ? .trailing : .center))
                    }
                }
                .font(WalkMateTheme.Fonts.caption)
                .foregroundStyle(.white)
            }
            if let hint {
                Text(hint).font(WalkMateTheme.Fonts.chip).foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(.vertical, 14)
    }

    private func navRow(_ title: String) -> some View {
        Button {} label: {
            HStack {
                Text(title).font(WalkMateTheme.Fonts.body).foregroundStyle(.white)
                Spacer()
                Image("icon_chevron").resizable().scaledToFit().frame(height: 14).foregroundStyle(.white)
            }
            .frame(minHeight: WalkMateTheme.Layout.minimumTapTarget)
        }
        .buttonStyle(.plain)
    }
}
