import Foundation
import Observation

/// 社群动态，离线优先：内置种子兜底，后端可达时覆盖；邀约响应本地先生效再同步
@MainActor
@Observable
final class CommunityStore {

    static let shared = CommunityStore()

    private(set) var feed: CommunityFeed = SeedData.feed
    private let backend = BackendClient.shared
    private let responsesKey = "walkmate.invitationResponses"

    private init() {
        // 恢复本地已作出的邀约响应，避免刷新前显示成未处理
        if let saved = UserDefaults.standard.dictionary(forKey: responsesKey) as? [String: String] {
            for (id, status) in saved { setStatus(status, for: id) }
        }
    }

    func refresh() async {
        guard backend.isConfigured else { return }
        do {
            feed = try await backend.fetchFeed()
            Log.info("已拉取社群动态", category: .general)
        } catch {
            Log.warning("拉取社群动态失败，沿用本地数据：\(error)", category: .general)
        }
    }

    func respond(to invitationID: String, accepted: Bool) async {
        let status = accepted ? "accepted" : "declined"
        setStatus(status, for: invitationID)
        var saved = UserDefaults.standard.dictionary(forKey: responsesKey) as? [String: String] ?? [:]
        saved[invitationID] = status
        UserDefaults.standard.set(saved, forKey: responsesKey)
        Log.info("邀约 \(invitationID) 已\(accepted ? "同意" : "拒绝")", category: .ui)
        do { try await backend.respond(invitationID: invitationID, accepted: accepted) }
        catch { Log.warning("邀约响应同步失败：\(error)", category: .general) }
    }

    private func setStatus(_ status: String, for id: String) {
        guard let index = feed.invitations.firstIndex(where: { $0.id == id }) else { return }
        feed.invitations[index].status = status
    }
}

/// 内置种子数据，与后端 seed.py 保持一致，用于后端不可达时展示
enum SeedData {
    static let stores: [StoreSummary] = [
        StoreSummary(
            id: "s_insta360", name: "影石Insta360 仙林金鹰店", category: "购物", distanceKm: 2.2, coverKey: "store_insta360",
            averageScore: 4.8, visitorCount: 36, tags: ["无障碍入口", "方便独立前往", "店内安静", "无障碍卫生间"],
            route: RouteInfo(start: "小区南门", end: "影石Insta360 仙林金鹰店", distanceMeters: 2200, averageObstacles: 28,
                             points: [[0.08, 0.85], [0.3, 0.8], [0.35, 0.55], [0.6, 0.5], [0.65, 0.25], [0.9, 0.15]],
                             obstacles: [[0.14, 0.83], [0.22, 0.81], [0.3, 0.8], [0.33, 0.68], [0.36, 0.55], [0.48, 0.52], [0.6, 0.5], [0.62, 0.38], [0.65, 0.25], [0.78, 0.2], [0.9, 0.15]],
                             steps: ["出小区南门右转，沿人行道直行约 400 米", "路口有过街音响提示，直行过马路", "沿商场外墙走到玻璃门入口，门口有两级台阶"],
                             destination: RouteInfo.Destination(name: "影石Insta360南京仙林金鹰店", address: "栖霞区仙林街道学海路1号仙林金鹰HB01-F1111", latitude: 32.103141, longitude: 118.926546))),
        StoreSummary(
            id: "s_duck_soup", name: "回味鸭血粉丝汤 九霄梦天地店", category: "美食", distanceKm: 1.4, coverKey: "store_duck_soup",
            averageScore: 4.5, visitorCount: 21, tags: ["店员友善", "菜单可朗读", "有盲道", "店内安静"],
            route: RouteInfo(start: "小区南门", end: "回味鸭血粉丝汤 九霄梦天地店", distanceMeters: 1400, averageObstacles: 18,
                             points: [[0.1, 0.8], [0.4, 0.78], [0.45, 0.45], [0.8, 0.4], [0.85, 0.2]],
                             obstacles: [[0.2, 0.79], [0.3, 0.78], [0.4, 0.78], [0.43, 0.6], [0.45, 0.45], [0.62, 0.42], [0.8, 0.4], [0.83, 0.28]],
                             steps: ["出小区南门左转，沿盲道走约 300 米", "菜市场门口常有电动车停放，靠右侧行走", "店门口无台阶，推门进入"],
                             destination: RouteInfo.Destination(name: "回味鸭血粉丝汤(九霄梦天地店)", address: "栖霞区仙林街道学衡路1号九霄梦天地B1层01号101号商铺", latitude: 32.092324, longitude: 118.917132))),
    ]

    /// 小区路线演示数据
    static let neighborhoodRoute = RouteInfo(
        start: "家门口", end: "小区南门", distanceMeters: 650, averageObstacles: 3,
        points: [[0.12, 0.9], [0.15, 0.6], [0.4, 0.55], [0.45, 0.3], [0.75, 0.28], [0.88, 0.1]],
        obstacles: [[0.15, 0.6], [0.45, 0.3]],
        steps: ["出单元门右转，沿楼间小路直行", "健身区旁常有停放的自行车，靠左通过", "花坛尽头左转即到南门"])

    static let feed = CommunityFeed(
        achievements: [
            .init(user: "子璇爸爸", avatarKey: "avatar_zixuan", crown: "crown_gold", note: "独立出行 3.2 km，探索 2 个新地点"),
            .init(user: "Momo", avatarKey: "avatar_momo", crown: "crown_silver", note: "完成 Level 4 户外训练"),
            .init(user: "刘佳佳", avatarKey: "avatar_liujiajia", crown: "crown_bronze", note: "第一次独立乘坐地铁"),
        ],
        invitations: [.init(id: "inv_1", from: "Momo", avatarKey: "avatar_momo", place: "上野公园", time: "9月25日 星期六 早上9:30出发", message: "想去感受秋天。", status: nil)],
        journeys: [.init(title: "第一次独立去购物", duration: "4:28", distanceKm: 15, note: "第一次独自去商业中心，有点紧张！但是去了之后发现真的很有趣！", likes: 52, comments: 12, shares: 5, user: "Doris", avatarKey: "avatar_doris_small")]
    )
}
