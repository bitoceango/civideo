-- 设备：孩子的每台设备一行，由家长用 PIN 激活后写入
CREATE TABLE IF NOT EXISTS devices (
  id          TEXT PRIMARY KEY,        -- uuid
  token_hash  TEXT NOT NULL UNIQUE,    -- 设备令牌的 sha256（明文只在激活时返回一次）
  name        TEXT,                    -- 设备名（如"客厅iPad"）
  created_at  INTEGER NOT NULL,
  -- 家长控制规则（null = 不限制）
  daily_limit_min  INTEGER,            -- 每日观看上限（分钟）
  allowed_start    INTEGER,            -- 允许时段起（当天分钟数，如 16*60=960）
  allowed_end      INTEGER             -- 允许时段止
);
CREATE INDEX IF NOT EXISTS idx_devices_token ON devices(token_hash);

-- 播放进度：断点续播
CREATE TABLE IF NOT EXISTS watch_progress (
  device_id    TEXT NOT NULL,
  video_id     TEXT NOT NULL,
  position_sec INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  PRIMARY KEY (device_id, video_id)
);

-- 每日观看时长累计（防沉迷）：按设备按天累加秒数
CREATE TABLE IF NOT EXISTS watch_daily (
  device_id  TEXT NOT NULL,
  day        TEXT NOT NULL,            -- YYYY-MM-DD（设备本地日期由客户端上报）
  watched_sec INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, day)
);
