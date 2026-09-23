import SwiftUI

/// 路线页：示意地图、距离与平均障碍数、分步说明。
/// 进度页的「小区路线」与社群探店的「查看路线」共用。
struct RouteDetailView: View {
    let title: String
    let route: RouteInfo
    /// 本人走过的次数，探店路线没有这个数据
    var completedCount: Int? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    WMPageTitle(text: title)
                    Text("\(route.start) → \(route.end)")
                        .font(WalkMateTheme.Fonts.caption)
                        .foregroundStyle(WalkMateTheme.Colors.textPrimary.opacity(0.72))
                }
                RouteMapView(route: route)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: WalkMateTheme.Radius.card, style: .continuous))
                HStack(spacing: 14) {
                    WMStatTile(label: "距离", value: distanceText)
                    WMStatTile(label: "平均障碍数", value: "\(route.averageObstacles) 处")
                }
                if let completedCount {
                    WMStatTile(label: "已完成", value: "\(completedCount) 次")
                }
                stepsSection
            }
            .wmPageInset()
            .padding(.top, 12)
            .wmTabBarClearance()
        }
        .scrollIndicators(.hidden)
        .background(WalkMateTheme.Colors.background.ignoresSafeArea())
        .wmDetailNavigationBar(title: title)
    }

    private var distanceText: String {
        route.distanceMeters >= 1000
            ? String(format: "%.1f km", Double(route.distanceMeters) / 1000)
            : "\(route.distanceMeters) m"
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WMSectionHeader(title: "怎么走")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(WalkMateTheme.Fonts.statValue)
                            .foregroundStyle(WalkMateTheme.Colors.accentSoft)
                            .frame(width: 24, alignment: .leading)
                        Text(step)
                            .font(WalkMateTheme.Fonts.body)
                            .foregroundStyle(WalkMateTheme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(WalkMateTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wmCard()
        }
    }
}

/// 路线示意图：折线、起终点、常见障碍位置。
///
/// 无障碍：整张图是一个元素，朗读起终点与障碍数量；细节由页面上的分步说明承担。
struct RouteMapView: View {
    let route: RouteInfo

    private let obstacleColor = Color(hex: 0xFFB020)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                WalkMateTheme.Gradients.card
                Canvas { context, _ in
                    drawGrid(in: &context, size: size)
                    drawPath(in: &context, size: size)
                    for obstacle in route.obstacles {
                        dot(at: point(obstacle, size), radius: 9, fill: obstacleColor, in: &context)
                    }
                    if let first = route.points.first {
                        dot(at: point(first, size), radius: 8, fill: .white, in: &context)
                    }
                    if let last = route.points.last {
                        dot(at: point(last, size), radius: 8, fill: WalkMateTheme.Colors.accentSoft, in: &context)
                    }
                }
                if let first = route.points.first {
                    label("起点", at: point(first, size), size: size)
                }
                if let last = route.points.last {
                    label("终点", at: point(last, size), size: size)
                }
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("路线示意图，从\(route.start)到\(route.end)，沿途 \(route.obstacles.count) 处常见障碍")
    }

    private func point(_ pair: [Double], _ size: CGSize) -> CGPoint {
        let inset: CGFloat = 24
        return CGPoint(x: inset + pair[0] * (size.width - inset * 2), y: inset + pair[1] * (size.height - inset * 2))
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        for index in 1..<6 {
            let x = size.width * CGFloat(index) / 6
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for index in 1..<4 {
            let y = size.height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
    }

    private func drawPath(in context: inout GraphicsContext, size: CGSize) {
        guard let first = route.points.first else { return }
        var path = Path()
        path.move(to: point(first, size))
        for pair in route.points.dropFirst() { path.addLine(to: point(pair, size)) }
        context.stroke(path, with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(WalkMateTheme.Colors.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private func dot(at center: CGPoint, radius: CGFloat, fill: Color, in context: inout GraphicsContext) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(fill))
        context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)), lineWidth: 2)
    }

    private func label(_ text: String, at center: CGPoint, size: CGSize) -> some View {
        // 标签放在点的上方；靠近顶边时放到下方
        let below = center.y < 40
        return Text(text)
            .font(WalkMateTheme.Fonts.chip)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .position(x: min(max(center.x, 28), size.width - 28), y: below ? center.y + 24 : center.y - 22)
    }

    private var legend: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                legendItem(color: WalkMateTheme.Colors.accent, text: "路线")
                legendItem(color: obstacleColor, text: "常见障碍")
                Spacer()
            }
            .padding(12)
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(WalkMateTheme.Fonts.chip).foregroundStyle(.white.opacity(0.9))
        }
    }
}
