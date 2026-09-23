# 伴行后端

零依赖的 Python 标准库服务，负责评分、邀约响应、训练记录上传与社群动态。

```bash
python3 backend/server.py --port 8080 --db backend/walkmate.db
```

首次启动自动建表并写入种子数据（用户、成就、两家店铺、邀约、旅程、预置评分）。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 存活检查 |
| GET | `/stores` | 店铺列表（含平均分、人数、标签、路线） |
| GET | `/stores/{id}/reviews` | 某店的全部评分 |
| POST | `/stores/{id}/reviews` | 提交评分 `{score, tags, comment}` |
| GET | `/feed` | 好友成就、邀约（含本设备的响应状态）、旅程 |
| POST | `/invitations/{id}/respond` | `{accepted: true/false}` |
| GET/POST | `/sessions` | 本设备的训练记录 |

请求头 `X-Device-Id` 标识设备。客户端在 `Secrets.plist` 的 `BackendBaseURL` 指定服务地址。
