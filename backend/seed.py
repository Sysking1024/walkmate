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
CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, from_user TEXT NOT NULL, place TEXT NOT NULL, time TEXT NOT NULL, message TEXT, store_id TEXT);
CREATE TABLE IF NOT EXISTS invitation_responses (invitation_id TEXT NOT NULL, device_id TEXT NOT NULL, accepted INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (invitation_id, device_id));
CREATE TABLE IF NOT EXISTS journeys (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL, duration TEXT NOT NULL, distance_km REAL NOT NULL, note TEXT, likes INTEGER, comments INTEGER, shares INTEGER, video_file_name TEXT, cover_key TEXT, created_at INTEGER DEFAULT 0);
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
    ("s_insta360", "影石Insta360 仙林金鹰店", "购物", 2.2, "store_insta360", 4.8, 36,
     ["无障碍入口", "方便独立前往", "店内安静", "无障碍卫生间"],
     {"start": "小区南门", "end": "影石Insta360 仙林金鹰店", "distanceMeters": 2200, "averageObstacles": 28,
      "points": [[0.08, 0.85], [0.3, 0.8], [0.35, 0.55], [0.6, 0.5], [0.65, 0.25], [0.9, 0.15]],
      "obstacles": [[0.14, 0.83], [0.22, 0.81], [0.3, 0.8], [0.33, 0.68], [0.36, 0.55], [0.48, 0.52], [0.6, 0.5], [0.62, 0.38], [0.65, 0.25], [0.78, 0.2], [0.9, 0.15]],
      "steps": ["出小区南门右转，沿人行道直行约 400 米", "路口有过街音响提示，直行过马路", "沿商场外墙走到玻璃门入口，门口有两级台阶"],
      # 真实地址与高德坐标（GCJ-02），路线页据此跳高德步行导航
      "destination": {"name": "影石Insta360南京仙林金鹰店", "address": "栖霞区仙林街道学海路1号仙林金鹰HB01-F1111", "latitude": 32.103141, "longitude": 118.926546}},
     1),
    ("s_duck_soup", "回味鸭血粉丝汤 九霄梦天地店", "美食", 1.4, "store_duck_soup", 4.5, 21,
     ["店员友善", "菜单可朗读", "有盲道", "店内安静"],
     {"start": "小区南门", "end": "回味鸭血粉丝汤 九霄梦天地店", "distanceMeters": 1400, "averageObstacles": 18,
      "points": [[0.1, 0.8], [0.4, 0.78], [0.45, 0.45], [0.8, 0.4], [0.85, 0.2]],
      "obstacles": [[0.2, 0.79], [0.3, 0.78], [0.4, 0.78], [0.43, 0.6], [0.45, 0.45], [0.62, 0.42], [0.8, 0.4], [0.83, 0.28]],
      "steps": ["出小区南门左转，沿盲道走约 300 米", "菜市场门口常有电动车停放，靠右侧行走", "店门口无台阶，推门进入"],
      "destination": {"name": "回味鸭血粉丝汤(九霄梦天地店)", "address": "栖霞区仙林街道学衡路1号九霄梦天地B1层01号101号商铺", "latitude": 32.092324, "longitude": 118.917132}},
     2),
]

INVITATIONS = [("inv_1", "u_momo", "影石Insta360 仙林金鹰店", "9月25日 星期六 早上9:30出发", "想去摸摸新相机，顺便逛逛金鹰。", "s_insta360")]

# (id, 用户, 标题, 时长, 公里, 留言, 赞, 评论, 转发, 随应用内置的视频文件名, 封面图键, 发布时间)
JOURNEYS = [
    ("j_1", "u_doris", "记录我的第一次半开放户外探索", "0:19", 0.65, None, 52, 1, 5, "demo_highlight.mp4", "journey_cover_bamboo", 1758600000),
    ("j_2", "u_zixuan", "湖边散步的傍晚", "0:10", 1.8, None, 31, 1, 2, "demo_outdoor.mp4", "journey_cover_outdoor", 1758500000),
]


def ensure_seeded(db_path):
    conn = sqlite3.connect(db_path)
    conn.executescript(SCHEMA)
    if conn.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 0:
        conn.executemany("INSERT INTO users VALUES (?, ?, ?, ?)", USERS)
        conn.executemany("INSERT INTO achievements (user_id, crown, note, rank) VALUES (?, ?, ?, ?)", ACHIEVEMENTS)
        for s in STORES:
            conn.execute("INSERT INTO stores VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (s[0], s[1], s[2], s[3], s[4], s[5], s[6], json.dumps(s[7], ensure_ascii=False), json.dumps(s[8], ensure_ascii=False), s[9]))
        conn.executemany("INSERT INTO invitations VALUES (?, ?, ?, ?, ?, ?)", INVITATIONS)
        conn.executemany("INSERT INTO journeys VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", JOURNEYS)
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
