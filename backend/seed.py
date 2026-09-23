"""建表与种子数据。用户、成就动态、店铺、邀约、旅程均为演示用预置内容。"""
import json
import sqlite3
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT NOT NULL, avatar_key TEXT NOT NULL, bio TEXT);
CREATE TABLE IF NOT EXISTS achievements (id INTEGER PRIMARY KEY, user_id TEXT NOT NULL, crown TEXT, note TEXT NOT NULL, rank INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS stores (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, distance_km REAL NOT NULL, cover_key TEXT NOT NULL,
  baseline_score REAL NOT NULL, baseline_visitors INTEGER NOT NULL, baseline_tags TEXT NOT NULL, route TEXT NOT NULL, sort_order INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS reviews (id TEXT PRIMARY KEY, store_id TEXT NOT NULL, device_id TEXT NOT NULL, score INTEGER NOT NULL, tags TEXT NOT NULL, comment TEXT, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, from_user TEXT NOT NULL, place TEXT NOT NULL, time TEXT NOT NULL, message TEXT);
CREATE TABLE IF NOT EXISTS invitation_responses (invitation_id TEXT NOT NULL, device_id TEXT NOT NULL, accepted INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (invitation_id, device_id));
CREATE TABLE IF NOT EXISTS journeys (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL, duration TEXT NOT NULL, distance_km REAL NOT NULL, note TEXT, likes INTEGER, comments INTEGER, shares INTEGER);
CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, device_id TEXT NOT NULL, duration_seconds INTEGER, distance_meters INTEGER, obstacles_avoided INTEGER, moments_count INTEGER, finished_at INTEGER);
"""

USERS = [
    ("u_doris", "Doris", "avatar_doris", "喜欢探索户外"),
    ("u_momo", "Momo", "avatar_momo", "刚开始户外训练"),
    ("u_zixuan", "子璇爸爸", "avatar_zixuan", "每天带女儿散步"),
    ("u_liujiajia", "刘佳佳", "avatar_liujiajia", "第一次独立坐地铁"),
    ("u_ming", "Ming", "avatar_doris_small", "避障一百次"),
]

ACHIEVEMENTS = [
    ("u_zixuan", "crown_gold", "独立出行 3.2 km，探索 2 个新地点", 1),
    ("u_momo", "crown_silver", "完成 Level 4 户外训练", 2),
    ("u_liujiajia", "crown_bronze", "第一次独立乘坐地铁", 3),
]

# 路线描述：起点、终点、折线点（0 到 1 的相对坐标）、障碍标记、平均障碍数
STORES = [
    ("s_insta360", "影石Insta360", "购物", 2.2, "store_insta360", 4.8, 36,
     ["无障碍入口", "方便独立前往", "店内安静", "无障碍卫生间"],
     {"start": "小区南门", "end": "影石Insta360 门店", "distanceMeters": 2200, "averageObstacles": 6,
      "points": [[0.08, 0.85], [0.3, 0.8], [0.35, 0.55], [0.6, 0.5], [0.65, 0.25], [0.9, 0.15]],
      "obstacles": [[0.3, 0.8], [0.6, 0.5], [0.65, 0.25]],
      "steps": ["出小区南门右转，沿人行道直行约 400 米", "路口有过街音响提示，直行过马路", "沿商场外墙走到玻璃门入口，门口有两级台阶"],
      # 真实地址与高德坐标，填上后路线页出现「用高德步行导航」
      "destination": None},
     1),
    ("s_duck_soup", "南京鸭血粉丝汤店", "美食", 1.4, "store_duck_soup", 4.5, 21,
     ["店员友善", "菜单可朗读", "有盲道", "店内安静"],
     {"start": "小区南门", "end": "鸭血粉丝汤店", "distanceMeters": 1400, "averageObstacles": 4,
      "points": [[0.1, 0.8], [0.4, 0.78], [0.45, 0.45], [0.8, 0.4], [0.85, 0.2]],
      "obstacles": [[0.4, 0.78], [0.8, 0.4]],
      "steps": ["出小区南门左转，沿盲道走约 300 米", "菜市场门口常有电动车停放，靠右侧行走", "店门口无台阶，推门进入"],
      "destination": None},
     2),
]

INVITATIONS = [("inv_1", "u_momo", "上野公园", "9月25日 星期六 早上9:30出发", "想去感受秋天。")]

JOURNEYS = [("j_1", "u_doris", "第一次独立去购物", "4:28", 15.0, "第一次独自去商业中心，有点紧张！但是去了之后发现真的很有趣！", 52, 12, 5)]


def ensure_seeded(db_path):
    conn = sqlite3.connect(db_path)
    conn.executescript(SCHEMA)
    if conn.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 0:
        conn.executemany("INSERT INTO users VALUES (?, ?, ?, ?)", USERS)
        conn.executemany("INSERT INTO achievements (user_id, crown, note, rank) VALUES (?, ?, ?, ?)", ACHIEVEMENTS)
        for s in STORES:
            conn.execute("INSERT INTO stores VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (s[0], s[1], s[2], s[3], s[4], s[5], s[6], json.dumps(s[7], ensure_ascii=False), json.dumps(s[8], ensure_ascii=False), s[9]))
        conn.executemany("INSERT INTO invitations VALUES (?, ?, ?, ?, ?)", INVITATIONS)
        conn.executemany("INSERT INTO journeys VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", JOURNEYS)
        # 预置几条评分，让店铺一开始就有真实来源的分数与标签
        now = int(time.time())
        conn.executemany("INSERT INTO reviews VALUES (?, ?, ?, ?, ?, ?, ?)", [
            ("r_1", "s_insta360", "seed_momo", 5, json.dumps(["无障碍入口", "店员友善"], ensure_ascii=False), "门口有引导，进店很顺", now - 86400 * 3),
            ("r_2", "s_insta360", "seed_zixuan", 4, json.dumps(["方便独立前往", "店内安静"], ensure_ascii=False), "", now - 86400),
            ("r_3", "s_duck_soup", "seed_liujiajia", 5, json.dumps(["店员友善", "菜单可朗读"], ensure_ascii=False), "老板会念菜单", now - 86400 * 2),
        ])
        conn.commit()
        print("[INFO] 已写入种子数据")
    conn.close()
