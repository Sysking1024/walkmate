import Foundation

/// 后端接口客户端。
///
/// 地址来自 Secrets.plist 的 `BackendBaseURL`；没有配置时所有调用直接抛出 `notConfigured`，
/// 由各存储层退回本地数据，保证离线可用。请求超时压到 5 秒：现场网络不稳时不能让界面卡住。
struct BackendClient {

    enum ClientError: Error { case notConfigured, badStatus(Int) }

    static let shared = BackendClient()

    private let baseURL: URL?
    private let session: URLSession

    /// 设备标识，首次生成后固定，作为后端区分用户的依据
    static let deviceID: String = {
        let key = "walkmate.deviceId"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    private init() {
        var url: URL?
        if let plist = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: plist),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
           let base = dict["BackendBaseURL"] {
            url = URL(string: base)
        }
        baseURL = url
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        configuration.allowsCellularAccess = true
        session = URLSession(configuration: configuration)
        if url == nil { Log.warning("未配置后端地址，社群与评分将只用本地数据", category: .general) }
    }

    var isConfigured: Bool { baseURL != nil }

    // MARK: - 接口

    func fetchStores() async throws -> [StoreSummary] {
        try await get("stores")
    }

    func submitReview(storeID: String, review: StoreRating) async throws -> StoreSummary {
        try await post("stores/\(storeID)/reviews", body: [
            "id": review.id.uuidString, "score": review.score, "tags": review.tags,
            "comment": review.comment, "createdAt": Int(review.createdAt.timeIntervalSince1970),
        ])
    }

    func fetchFeed() async throws -> CommunityFeed {
        try await get("feed")
    }

    func respond(invitationID: String, accepted: Bool) async throws {
        let _: InvitationResponse = try await post("invitations/\(invitationID)/respond", body: ["accepted": accepted])
    }

    func uploadSession(_ record: TrainingRecord) async throws {
        let _: UploadReceipt = try await post("sessions", body: [
            "id": record.id.uuidString, "durationSeconds": record.durationSeconds, "distanceMeters": record.distanceMeters,
            "obstaclesAvoided": record.obstaclesAvoided, "momentsCount": record.moments.count,
            "finishedAt": Int(record.finishedAt.timeIntervalSince1970),
        ])
    }

    // MARK: - 通用请求

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(request(path: path, method: "GET", body: nil))
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await send(request(path: path, method: "POST", body: try JSONSerialization.data(withJSONObject: body)))
    }

    private func request(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let baseURL else { throw ClientError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.deviceID, forHTTPHeaderField: "X-Device-Id")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.error("后端返回异常状态码 \(code)：\(request.url?.path ?? "")", category: .general)
            throw ClientError.badStatus(code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct InvitationResponse: Decodable { let id: String; let status: String }
private struct UploadReceipt: Decodable { let id: String }

// MARK: - 后端数据模型

/// 店铺概要，含路线
struct StoreSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let distanceKm: Double
    let coverKey: String
    var averageScore: Double
    var visitorCount: Int
    var tags: [String]
    let route: RouteInfo
}

/// 一条路线：起终点、示意折线、障碍标记、平均障碍数与分步说明
struct RouteInfo: Codable, Equatable, Hashable {
    let start: String
    let end: String
    let distanceMeters: Int
    let averageObstacles: Int
    /// 折线各点，0 到 1 的相对坐标
    let points: [[Double]]
    let obstacles: [[Double]]
    let steps: [String]
}

struct CommunityFeed: Codable, Equatable {
    struct Achievement: Codable, Equatable { let user: String; let avatarKey: String; let crown: String?; let note: String }
    struct Invitation: Codable, Equatable, Identifiable {
        let id: String; let from: String; let avatarKey: String; let place: String; let time: String; let message: String?
        var status: String?
    }
    struct Journey: Codable, Equatable {
        let title: String; let duration: String; let distanceKm: Double; let note: String?
        let likes: Int; let comments: Int; let shares: Int; let user: String; let avatarKey: String
    }
    var achievements: [Achievement]
    var invitations: [Invitation]
    var journeys: [Journey]
}
