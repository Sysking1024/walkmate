# 空间感知实测多模态离线回放数据集规范 (Replay Datasets)

本目录用于存放从真实设备采集（或基于严格几何仿真生成）的空间感知多模态实测数据包，供 `ReplayTests` 离线回归测试与调优基准套件使用。

## 一、 会话目录规范

每个实测会话独立为一个目录，目录命名遵循规范 `session_YYYYMMDD_HHMMSS` 或特定场景别名（如 `session_blocked_sample`），内部结构必须严格包含：

```text
session_xxx/
├── metadata.json           # 会话全局元数据 (时长、帧数、设备信息等)
├── telemetry.jsonl         # 10~30Hz 行式时序遥测快照 (逐帧 JSON)
├── frames/                 # 1~2Hz 抽样全景视觉 JPEG 快照
│   ├── 1774341000500.jpg
│   └── 1774341001000.jpg
└── depths/                 # 1~2Hz 抽样 256x512 物理深度矩阵二进制快照
    ├── 1774341000500.bin
    └── 1774341001000.bin
```

## 二、 核心文件格式说明

### 1. `metadata.json`
描述采集会话的基本概要：
- `sessionId`: 唯一会话标识符
- `startTimeMs`: 启动时间戳 (毫秒)
- `endTimeMs`: 结束时间戳 (毫秒)
- `durationSeconds`: 录制总时长 (秒)
- `totalTelemetryFrames`: 时序遥测帧总数
- `totalImageSnapshots`: 抽样快照帧总数
- `deviceInfo`: 采集设备型号
- `appVersion`: 应用程序版本

### 2. `telemetry.jsonl`
每一行均为一个独立的 JSON 对象（对齐 `FrameTelemetryRecord` 数据模型），行末紧跟换行符 `\n`。关键字段包含：
- `timestampMs`: 帧同步毫秒时间戳
- `orientation`: IMU 绝对姿态四元数（`x, y, z, w`）
- `eulerAngles`: 横滚/俯仰/偏航角（度）
- `groundPlane`: 拟合地平面方程参数 $(A, B, C, D)$
- `cameraHeight`: 解算得到的相机离地高度（米）
- `rawObstacles`: 剥离地面后聚类检出的全量三维障碍物列表
- `hazardObstacles`: 筛选出的前向贴身威胁障碍物列表
- `isPassable`: 当前帧路径规划可通行状态
- `safeDepth`: 当前通道有效安全纵深（米）
- `recommendedHeading`: 推荐起步偏航角（度）
- `waypoints`: 解算生成的全局空间航路折线点序列
- `processingLatencyMs`: 感知算法处理端到端时延（毫秒）

### 3. `depths/*.bin`
连续 `256 x 512 = 131,072` 个 32 位单精度浮点数（IEEE 754 Float32），小端序，文件固定大小为 524,288 字节。

## 三、 测试基准场景

- `session_blocked_sample`: 模拟前方狭窄通道（净宽不足 0.55m）或障碍物阻挡路面的极限挑战场景，用于评估避障灵敏度与调参前后的航路点生成率。
- `session_clear_sample`: 模拟开阔走廊与平整路面场景，用于验证基准路径规划稳定性与零误报。
