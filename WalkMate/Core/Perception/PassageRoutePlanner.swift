//
//  PassageRoutePlanner.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - BEV 栅格与可通行路线规划器

/// 负责将 360° 障碍物投影至 300x300 鸟瞰 (BEV) 空间栅格，
/// 通过欧氏距离变换 (EDT) 计算障碍物距离场，施加 0.6m 人体宽度约束与滞后门限，
/// 采用 A* 全局路径寻优沿通行走廊提取连续航路点序列 (Waypoints)、通道瓶颈物理净宽、安全纵深与起步推荐偏航角
public final class PassageRoutePlanner: Sendable {
    
    /// BEV 栅格宽度与高度规格 (300 x 300 单元格)
    public static let gridWidth: Int = 300
    public static let gridHeight: Int = 300
    
    /// 栅格空间物理分辨率 (米/格, 0.02m 即 2cm)
    public static let resolution: Float = 0.02
    
    /// 横向覆盖宽度 (米, 左右各 3.0m, 总计 6.0m)
    public static let halfWidthMeters: Float = 3.0
    
    /// 前向最大探测纵深 (米, 0 ~ 6.0m)
    public static let maxDepthMeters: Float = 6.0
    
    /// 人体标准通行宽度基准约束 (米, 默认 0.6m)
    private let bodyWidthThreshold: Float
    
    /// 航路点前向采样期望步长 (米, 默认 0.4m)
    private let waypointStepMeters: Float
    
    /// 通道开通判定门限 (米, 规范设定 0.65m)
    public static let openHysteresisThreshold: Float = 0.65
    /// 通道关闭判定门限 (米, 规范设定 0.55m)
    public static let closeHysteresisThreshold: Float = 0.55
    
    private let stateLock = NSLock()
    /// 上一帧通道是否处于可用开通状态 (供滞后区间判定)
    private var isPreviouslyPassable: Bool = false
    
    /// 初始化路线规划器
    /// - Parameters:
    ///   - bodyWidthThreshold: 人体通行净宽门限
    ///   - waypointStepMeters: 航路折线点间距
    public init(
        bodyWidthThreshold: Float = 0.60,
        waypointStepMeters: Float = 0.40
    ) {
        self.bodyWidthThreshold = bodyWidthThreshold
        self.waypointStepMeters = waypointStepMeters
    }
    
    /// 重置路线规划器内部滞后状态
    public func reset() {
        stateLock.lock()
        isPreviouslyPassable = false
        stateLock.unlock()
    }
    
    // MARK: - 核心规划方法
    
    /// 从当前帧障碍物列表中解算可通行路线数据
    /// - Parameters:
    ///   - obstacles: 当前帧检出的所有 360° 障碍物列表
    ///   - cameraHeight: 相机当前离地高度 (米)
    /// - Returns: 可通行路线数据实体 (PassableRouteData)
    public func planRoute(
        obstacles: [ObstacleItem],
        cameraHeight: Float
    ) -> PassableRouteData {
        let width = PassageRoutePlanner.gridWidth
        let height = PassageRoutePlanner.gridHeight
        let res = PassageRoutePlanner.resolution
        
        stateLock.lock()
        let wasPassable = isPreviouslyPassable
        stateLock.unlock()
        
        // 依据前序状态与规范边缘情况施加滞后区间门限 (0.55m ~ 0.65m):
        // 若前序已开通，则维持开通的临界宽度放宽至 closeHysteresisThreshold (0.55m);
        // 若前序未开通，则必须达到开通门槛 openHysteresisThreshold (0.65m) 才能激活
        let activeWidthThreshold = wasPassable ? Self.closeHysteresisThreshold : Self.openHysteresisThreshold
        let requiredClearanceRadius = activeWidthThreshold / 2.0
        
        // 1. 初始化 300x300 二维二值栅格 (0 表示障碍物，大数值表示自由空间)
        var grid = [Float](repeating: 1e8, count: width * height)
        
        // 2. 标记左右侧向边界为物理墙体障碍物 (防止路线无限漂向无视野边界)
        for r in 0..<height {
            grid[r * width + 0] = 0.0
            grid[r * width + (width - 1)] = 0.0
        }
        // 标记前向终点边界为障碍物
        for c in 0..<width {
            grid[(height - 1) * width + c] = 0.0
        }
        
        // 3. 将前向视野内的障碍物 AABB 包围盒栅格化写入 BEV 地图
        for obs in obstacles {
            // 仅处理可能阻挡地面行进的前方障碍物 (z <= 0.2m 且不是高空远离碰头)
            if obs.position.z > 0.2 { continue }
            if obs.category == .hangingHazard && obs.position.y > 0.5 { continue }
            
            let halfSizeX = obs.size.x / 2.0
            let halfSizeZ = obs.size.z / 2.0
            
            let minX = obs.position.x - halfSizeX
            let maxX = obs.position.x + halfSizeX
            let minDepth = max(0.0, -obs.position.z - halfSizeZ)
            let maxDepth = min(PassageRoutePlanner.maxDepthMeters, -obs.position.z + halfSizeZ)
            
            let cMin = max(0, min(width - 1, Int(floor((minX + PassageRoutePlanner.halfWidthMeters) / res))))
            let cMax = max(0, min(width - 1, Int(ceil((maxX + PassageRoutePlanner.halfWidthMeters) / res))))
            let rMin = max(0, min(height - 1, Int(floor(minDepth / res))))
            let rMax = max(0, min(height - 1, Int(ceil(maxDepth / res))))
            
            for r in rMin...rMax {
                let rowOffset = r * width
                for c in cMin...cMax {
                    grid[rowOffset + c] = 0.0
                }
            }
        }
        
        // 4. 执行线性时间二维欧氏距离变换 (2D EDT)
        let edtGrid = computeEDT2D(grid: grid, width: width, height: height)
        
        // 5. 采用 A* 全局路径寻优提取最优通行走廊
        // 使用 2 倍降采样网格进行极速路径搜索 (搜索空间 150x150, 耗时 < 1ms)
        let searchScale = 2
        let searchWidth = width / searchScale
        let searchHeight = height / searchScale
        let searchRes = res * Float(searchScale)
        
        let startR = 0
        let startC = (width / 2) / searchScale
        
        // A* 优先队列节点
        struct SearchNode: Comparable {
            let r: Int
            let c: Int
            let gCost: Float
            let priority: Float
            static func < (lhs: SearchNode, rhs: SearchNode) -> Bool {
                lhs.priority < rhs.priority
            }
        }
        
        var minHeap = BinaryHeap<SearchNode>()
        var costMap = [Float](repeating: Float.infinity, count: searchWidth * searchHeight)
        var parentMap = [Int](repeating: -1, count: searchWidth * searchHeight)
        
        let startIdx = startR * searchWidth + startC
        costMap[startIdx] = 0.0
        minHeap.push(SearchNode(r: startR, c: startC, gCost: 0.0, priority: 0.0))
        
        var deepestR = 0
        var deepestNodeIdx = startIdx
        
        // 8-邻域前向搜索（不向后退，平局优先右偏）
        let directions: [(dr: Int, dc: Int)] = [
            (1, 0), (1, 1), (2, 1), (0, 1),
            (1, -1), (2, -1), (0, -1), (2, 0)
        ]
        
        var iterations = 0
        while let current = minHeap.pop() {
            iterations += 1
            if iterations > 15000 { break }
            
            let curIdx = current.r * searchWidth + current.c
            if current.gCost > costMap[curIdx] { continue }
            
            if current.r > deepestR {
                deepestR = current.r
                deepestNodeIdx = curIdx
            }
            
            // 达到纵深目标 5.5 米时提前收敛
            if current.r >= searchHeight - 10 {
                break
            }
            
            for dir in directions {
                let nr = current.r + dir.dr
                let nc = current.c + dir.dc
                if nr < 0 || nr >= searchHeight - 2 || nc < 2 || nc >= searchWidth - 2 {
                    continue
                }
                
                // 校验原图对应网格的物理通行净空半径
                let origR = nr * searchScale
                let origC = nc * searchScale
                let cellDist = sqrt(edtGrid[origR * width + origC]) * res
                
                // 人体半宽 0.3m 约束
                if cellDist < requiredClearanceRadius {
                    continue
                }
                
                // 路径代价函数: 步长欧氏距离 + 障碍物贴近惩罚 + 偏离中心小惩罚
                let stepDist = sqrt(Float(dir.dr * dir.dr + dir.dc * dir.dc)) * searchRes
                let clearanceBonus = max(0.0, cellDist - requiredClearanceRadius)
                let clearancePenalty = 0.05 / max(clearanceBonus + 0.1, 0.1)
                let centerOffset = Float(abs(nc - startC)) * searchRes
                let moveCost = stepDist + clearancePenalty + (centerOffset * 0.03)
                
                let newG = current.gCost + moveCost
                let neighborIdx = nr * searchWidth + nc
                
                if newG < costMap[neighborIdx] {
                    costMap[neighborIdx] = newG
                    parentMap[neighborIdx] = curIdx
                    // 启发式函数: 剩余目标纵深
                    let h = Float(searchHeight - 1 - nr) * searchRes
                    minHeap.push(SearchNode(r: nr, c: nc, gCost: newG, priority: newG + h))
                }
            }
        }
        
        // 6. 回溯解算连续平滑路径
        var pathCoords: [(r: Int, c: Int)] = []
        var trace = deepestNodeIdx
        while trace != -1 {
            let r = trace / searchWidth
            let c = trace % searchWidth
            pathCoords.append((r: r, c: c))
            if r == startR && c == startC { break }
            trace = parentMap[trace]
        }
        pathCoords.reverse()
        
        let maxTraversedDepth = Float(deepestR * searchScale) * res
        
        // 7. 通道瓶颈特征提取与自适应航路点生成
        var waypoints: [RouteWaypoint] = []
        if pathCoords.count >= 2 {
            // 计算沿途所有点的物理坐标与净宽
            struct PathPoint {
                let pos: SIMD2<Float>
                let clearance: Float
                let origR: Int
                let origC: Int
            }
            
            var pathPoints: [PathPoint] = []
            pathPoints.reserveCapacity(pathCoords.count)
            for coord in pathCoords {
                let origR = coord.r * searchScale
                let origC = coord.c * searchScale
                let x = Float(origC) * res - PassageRoutePlanner.halfWidthMeters
                let z = -Float(origR) * res
                let cellDist = sqrt(edtGrid[origR * width + origC]) * res
                let clearance = cellDist * 2.0
                pathPoints.append(PathPoint(pos: SIMD2<Float>(x, z), clearance: clearance, origR: origR, origC: origC))
            }
            
            // 标记特征点 (起点、局部净宽瓶颈点、大折角点、终点)
            var keypointIndices = Set<Int>()
            keypointIndices.insert(0)
            keypointIndices.insert(pathPoints.count - 1)
            
            // 自动检测局部净宽极小值点 (通道瓶颈特征点，如门洞、狭窄走廊口)
            if pathPoints.count >= 5 {
                for i in 2..<(pathPoints.count - 2) {
                    let cPrev = pathPoints[i - 1].clearance
                    let cCurr = pathPoints[i].clearance
                    let cNext = pathPoints[i + 1].clearance
                    // 局部净宽谷底且处于较窄通道区间 (< 2.5m)
                    if cCurr <= cPrev && cCurr <= cNext && cCurr < 2.5 {
                        keypointIndices.insert(i)
                    }
                }
            }
            
            // 沿路径平滑抽取航路点序列 (保证各航路点间距在 0.3m ~ 0.5m 之间)
            var lastRecordedPos = SIMD2<Float>(0.0, 0.0)
            for i in 1..<pathPoints.count {
                let pt = pathPoints[i]
                let distFromLast = simd_distance(lastRecordedPos, pt.pos)
                let isKeypoint = keypointIndices.contains(i)
                let isLast = (i == pathPoints.count - 1)
                
                // 距离满足步长 (>= 0.35m) 或命中关键瓶颈点 (且距上一点 >= 0.25m)
                if (distFromLast >= 0.35 && pt.origR >= 15) || (isKeypoint && distFromLast >= 0.25) || (isLast && distFromLast >= 0.25) {
                    let wpPos = SIMD3<Float>(pt.pos.x, -cameraHeight, pt.pos.y)
                    waypoints.append(RouteWaypoint(position: wpPos, clearanceWidth: pt.clearance))
                    lastRecordedPos = pt.pos
                }
            }
        }
        
        // 8. 综合判定路线可用性与起步推荐朝向
        let isPathAvailable = !waypoints.isEmpty && maxTraversedDepth >= 1.2
        
        stateLock.lock()
        isPreviouslyPassable = isPathAvailable
        stateLock.unlock()
        
        let recommendedHeading: Float
        if let firstWp = waypoints.first {
            let targetX: Float
            let targetZ: Float
            if waypoints.count >= 2 {
                targetX = (firstWp.position.x + waypoints[1].position.x) / 2.0
                targetZ = (firstWp.position.z + waypoints[1].position.z) / 2.0
            } else {
                targetX = firstWp.position.x
                targetZ = firstWp.position.z
            }
            recommendedHeading = atan2(targetX, -targetZ) * (180.0 / .pi)
        } else {
            recommendedHeading = 0.0
        }
        
        return PassableRouteData(
            isPathAvailable: isPathAvailable,
            safeDepth: isPathAvailable ? maxTraversedDepth : min(maxTraversedDepth, 1.2),
            recommendedHeading: recommendedHeading,
            waypoints: isPathAvailable ? waypoints : []
        )
    }
    
    // MARK: - 线性时间二维欧氏距离变换 (2D EDT) 算法
    
    /// 基于 Felzenszwalb 分离抛物线包络算法实现严格 O(W * H) 极速二维 EDT
    private func computeEDT2D(
        grid: [Float],
        width: Int,
        height: Int
    ) -> [Float] {
        var tempGrid = [Float](repeating: 0, count: width * height)
        var outputGrid = [Float](repeating: 0, count: width * height)
        
        // 1. 沿列方向执行一维 EDT
        var colInput = [Float](repeating: 0, count: height)
        for c in 0..<width {
            for r in 0..<height {
                colInput[r] = grid[r * width + c]
            }
            let colOutput = distanceTransform1D(f: colInput, n: height)
            for r in 0..<height {
                tempGrid[r * width + c] = colOutput[r]
            }
        }
        
        // 2. 沿行方向执行一维 EDT
        var rowInput = [Float](repeating: 0, count: width)
        for r in 0..<height {
            let rowOffset = r * width
            for c in 0..<width {
                rowInput[c] = tempGrid[rowOffset + c]
            }
            let rowOutput = distanceTransform1D(f: rowInput, n: width)
            for c in 0..<width {
                outputGrid[rowOffset + c] = rowOutput[c]
            }
        }
        
        return outputGrid
    }
    
    /// 一维精确平方欧氏距离变换
    private func distanceTransform1D(
        f: [Float],
        n: Int
    ) -> [Float] {
        var d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        var k = 0
        v[0] = 0
        z[0] = -Float.infinity
        z[1] = Float.infinity
        
        for q in 1..<n {
            var s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k]))) / (2.0 * Float(q - v[k]))
            while s <= z[k] {
                k -= 1
                s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k]))) / (2.0 * Float(q - v[k]))
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = Float.infinity
        }
        
        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) {
                k += 1
            }
            let dx = Float(q - v[k])
            d[q] = dx * dx + f[v[k]]
        }
        return d
    }
}

// MARK: - 基础轻量二叉最小堆 (BinaryHeap)

/// 供 A* 搜索极速调度的轻量泛型优先队列
private struct BinaryHeap<Element: Comparable> {
    private var elements: [Element] = []
    
    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }
    
    mutating func push(_ element: Element) {
        elements.append(element)
        siftUp(elements.count - 1)
    }
    
    mutating func pop() -> Element? {
        guard !elements.isEmpty else { return nil }
        if elements.count == 1 { return elements.removeLast() }
        let top = elements[0]
        elements[0] = elements.removeLast()
        siftDown(0)
        return top
    }
    
    private mutating func siftUp(_ index: Int) {
        var child = index
        var parent = (child - 1) / 2
        while child > 0 && elements[child] < elements[parent] {
            elements.swapAt(child, parent)
            child = parent
            parent = (child - 1) / 2
        }
    }
    
    private mutating func siftDown(_ index: Int) {
        var parent = index
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var candidate = parent
            
            if left < elements.count && elements[left] < elements[candidate] {
                candidate = left
            }
            if right < elements.count && elements[right] < elements[candidate] {
                candidate = right
            }
            if candidate == parent { return }
            elements.swapAt(parent, candidate)
            parent = candidate
        }
    }
}
