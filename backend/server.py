"""伴行 WalkMate 后端服务。

零依赖：只用 Python 标准库（http.server + sqlite3 + json），任何装了 Python 3 的机器都能直接跑。
启动：python3 backend/server.py --port 8080 --db backend/walkmate.db
首次启动会建表并写入种子数据（用户、店铺、评分、邀约、旅程、成就动态）。
"""
import argparse
import json
import sqlite3
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

from seed import ensure_seeded

DB_PATH = "walkmate.db"


def connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def store_summary(conn, store_id):
    """店铺的平均分、去过的人数与出现最多的标签"""
    store = conn.execute("SELECT * FROM stores WHERE id = ?", (store_id,)).fetchone()
    if not store:
        return None
    reviews = conn.execute("SELECT score, tags FROM reviews WHERE store_id = ?", (store_id,)).fetchall()
    count = len(reviews)
    # 与基线（设计稿给定的历史分数与人数）加权，避免一条新评分就把均分拉偏
    total = store["baseline_score"] * store["baseline_visitors"] + sum(r["score"] for r in reviews)
    average = round(total / (store["baseline_visitors"] + count), 1)
    frequency = {}
    for r in reviews:
        for tag in json.loads(r["tags"]):
            frequency[tag] = frequency.get(tag, 0) + 1
    tags = [t for t, _ in sorted(frequency.items(), key=lambda kv: -kv[1])]
    for tag in json.loads(store["baseline_tags"]):
        if tag not in tags:
            tags.append(tag)
    return {
        "id": store["id"], "name": store["name"], "category": store["category"],
        "distanceKm": store["distance_km"], "coverKey": store["cover_key"],
        "averageScore": average, "visitorCount": store["baseline_visitors"] + count,
        "tags": tags[:4], "route": json.loads(store["route"]),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "WalkMate/1.0"

    # 统一返回 JSON
    def respond(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length) or b"{}")

    def device_id(self):
        return self.headers.get("X-Device-Id", "anonymous")

    def log_message(self, fmt, *args):
        # 业务日志统一中文，级别沿用行业标准
        print(f"[INFO] {self.address_string()} 请求 {fmt % args}")

    def do_GET(self):
        url = urlparse(self.path)
        parts = [p for p in url.path.split("/") if p]
        query = parse_qs(url.query)
        conn = connect()
        try:
            if parts == ["health"]:
                return self.respond(200, {"ok": True, "time": int(time.time())})

            if parts == ["stores"]:
                ids = [r["id"] for r in conn.execute("SELECT id FROM stores ORDER BY sort_order")]
                return self.respond(200, [store_summary(conn, i) for i in ids])

            if len(parts) == 3 and parts[0] == "stores" and parts[2] == "reviews":
                rows = conn.execute(
                    "SELECT id, device_id, score, tags, comment, created_at FROM reviews WHERE store_id = ? ORDER BY created_at DESC",
                    (parts[1],)).fetchall()
                return self.respond(200, [
                    {"id": r["id"], "deviceId": r["device_id"], "score": r["score"], "tags": json.loads(r["tags"]),
                     "comment": r["comment"], "createdAt": r["created_at"]} for r in rows])

            if len(parts) == 3 and parts[0] == "stores" and parts[2] == "summary":
                summary = store_summary(conn, parts[1])
                return self.respond(200, summary) if summary else self.respond(404, {"error": "店铺不存在"})

            if parts == ["feed"]:
                device = self.device_id()
                achievements = [dict(r) for r in conn.execute(
                    "SELECT u.name AS user, u.avatar_key AS avatarKey, a.crown, a.note FROM achievements a JOIN users u ON u.id = a.user_id ORDER BY a.rank")]
                invitations = []
                for r in conn.execute("SELECT i.*, u.name AS from_name, u.avatar_key AS avatar FROM invitations i JOIN users u ON u.id = i.from_user"):
                    status = conn.execute("SELECT accepted FROM invitation_responses WHERE invitation_id = ? AND device_id = ?",
                                          (r["id"], device)).fetchone()
                    invitations.append({
                        "id": r["id"], "from": r["from_name"], "avatarKey": r["avatar"], "place": r["place"],
                        "time": r["time"], "message": r["message"], "storeId": r["store_id"],
                        "status": None if status is None else ("accepted" if status["accepted"] else "declined"),
                    })
                journeys = [dict(r) for r in conn.execute(
                    "SELECT j.title, j.duration, j.distance_km AS distanceKm, j.note, j.likes, j.comments, j.shares, u.name AS user, u.avatar_key AS avatarKey FROM journeys j JOIN users u ON u.id = j.user_id")]
                return self.respond(200, {"achievements": achievements, "invitations": invitations, "journeys": journeys})

            if parts == ["sessions"]:
                device = query.get("deviceId", [self.device_id()])[0]
                rows = conn.execute(
                    "SELECT id, duration_seconds AS durationSeconds, distance_meters AS distanceMeters, obstacles_avoided AS obstaclesAvoided, moments_count AS momentsCount, finished_at AS finishedAt FROM sessions WHERE device_id = ? ORDER BY finished_at DESC",
                    (device,)).fetchall()
                return self.respond(200, [dict(r) for r in rows])

            return self.respond(404, {"error": "接口不存在"})
        finally:
            conn.close()

    def do_POST(self):
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        conn = connect()
        try:
            body = self.read_json()
            device = self.device_id()

            if len(parts) == 3 and parts[0] == "stores" and parts[2] == "reviews":
                score = int(body.get("score", 0))
                if not 1 <= score <= 5:
                    return self.respond(400, {"error": "评分必须在 1 到 5 之间"})
                review_id = body.get("id") or str(uuid.uuid4())
                conn.execute(
                    "INSERT OR REPLACE INTO reviews (id, store_id, device_id, score, tags, comment, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (review_id, parts[1], device, score, json.dumps(body.get("tags", []), ensure_ascii=False),
                     body.get("comment", ""), body.get("createdAt") or int(time.time())))
                conn.commit()
                print(f"[INFO] 收到评分：店铺 {parts[1]}，{score} 星，设备 {device}")
                return self.respond(200, store_summary(conn, parts[1]))

            if len(parts) == 3 and parts[0] == "invitations" and parts[2] == "respond":
                accepted = 1 if body.get("accepted") else 0
                conn.execute(
                    "INSERT OR REPLACE INTO invitation_responses (invitation_id, device_id, accepted, created_at) VALUES (?, ?, ?, ?)",
                    (parts[1], device, accepted, int(time.time())))
                conn.commit()
                return self.respond(200, {"id": parts[1], "status": "accepted" if accepted else "declined"})

            if parts == ["sessions"]:
                session_id = body.get("id") or str(uuid.uuid4())
                conn.execute(
                    "INSERT OR REPLACE INTO sessions (id, device_id, duration_seconds, distance_meters, obstacles_avoided, moments_count, finished_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (session_id, device, int(body.get("durationSeconds", 0)), int(body.get("distanceMeters", 0)),
                     int(body.get("obstaclesAvoided", 0)), int(body.get("momentsCount", 0)), int(body.get("finishedAt", time.time()))))
                conn.commit()
                return self.respond(200, {"id": session_id})

            return self.respond(404, {"error": "接口不存在"})
        except (ValueError, KeyError, json.JSONDecodeError) as error:
            return self.respond(400, {"error": f"请求体不合法：{error}"})
        finally:
            conn.close()


def main():
    global DB_PATH
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--db", default="backend/walkmate.db")
    args = parser.parse_args()
    DB_PATH = args.db
    ensure_seeded(DB_PATH)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"[INFO] 伴行后端已启动，端口 {args.port}，数据库 {DB_PATH}")
    server.serve_forever()


if __name__ == "__main__":
    main()
