#!/usr/bin/env bash
# 端到端后端验收测试：对线上 Worker 全链路断言。
# 用法：BASE=https://video.example.com PIN=1234 VIDEO=bigbuckbunny bash tests/e2e-backend.sh
# 退出码：0 全过 / 1 有失败。依赖：curl、node。
set -uo pipefail

BASE="${BASE:-https://video.xyt1989loveson.uk}"
PIN="${PIN:-1234}"
VIDEO="${VIDEO:-bigbuckbunny}"   # 库里需存在的一个 videoId（用于媒体/进度测试）
DAY="$(date +%Y-%m-%d)"

pass=0; fail=0
jq() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{let j=JSON.parse(s);let v=j;for(const k of process.argv[1].split("."))v=v?.[k];console.log(typeof v==="object"?JSON.stringify(v):v)}catch(e){console.log("")}})' "$1"; }
ok()  { echo "  ✅ $1"; pass=$((pass+1)); }
ko()  { echo "  ❌ $1"; fail=$((fail+1)); }
chk() { # chk "名称" 实际 期望
  if [ "$2" = "$3" ]; then ok "$1 ($2)"; else ko "$1 — 期望 [$3] 实得 [$2]"; fi
}

echo "=== 端到端后端验收 @ $BASE ==="

# 1. 健康检查
H=$(curl -s -m 20 "$BASE/api/health" | jq ok); chk "健康检查 ok=true" "$H" "true"

# 2. 无令牌拉库 → 401
C=$(curl -s -m 20 -o /dev/null -w "%{http_code}" "$BASE/api/library"); chk "无令牌 library=401" "$C" "401"

# 3. 错误 PIN 激活 → 403
C=$(curl -s -m 20 -o /dev/null -w "%{http_code}" -X POST "$BASE/api/activate" -H 'content-type: application/json' -d '{"pin":"000000","name":"e2e-bad"}'); chk "错误PIN激活=403" "$C" "403"

# 4. 正确 PIN 激活 → token
RESP=$(curl -s -m 20 -X POST "$BASE/api/activate" -H 'content-type: application/json' -d "{\"pin\":\"$PIN\",\"name\":\"e2e-test\"}")
TOKEN=$(echo "$RESP" | jq token); DEVID=$(echo "$RESP" | jq deviceId)
if [ "${#TOKEN}" = "64" ]; then ok "激活返回64位令牌"; else ko "激活令牌异常 (len=${#TOKEN})"; echo "  无法继续，缺令牌"; echo "=== 通过 $pass / 失败 $fail ==="; exit 1; fi
AUTH="Authorization: Bearer $TOKEN"

# 5. 带令牌拉库 → 有 videos
LIB=$(curl -s -m 20 "$BASE/api/library" -H "$AUTH")
VN=$(echo "$LIB" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).videos.length)}catch(e){console.log(0)}})')
if [ "$VN" -ge 1 ] 2>/dev/null; then ok "带令牌 library 返回 $VN 个视频"; else ko "library 视频数=$VN"; fi
HASURL=$(echo "$LIB" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).videos.every(v=>v.videoUrl&&v.posterUrl))}catch(e){console.log(false)}})')
chk "library 含 videoUrl/posterUrl" "$HASURL" "true"

# 6. 媒体 Range → 206 + Content-Range
HDR=$(curl -s -m 30 -D - -o /dev/null -H "$AUTH" -H "Range: bytes=0-1023" "$BASE/media/$VIDEO/video.mp4")
C=$(echo "$HDR" | grep -i "^HTTP/2" | tail -1 | awk '{print $2}'); chk "媒体Range=206" "$C" "206"
echo "$HDR" | grep -qi "content-range: bytes 0-1023/" && ok "含 Content-Range" || ko "缺 Content-Range"

# 7. 媒体全量 → 200
C=$(curl -s -m 60 -o /dev/null -w "%{http_code}" -H "$AUTH" "$BASE/media/$VIDEO/video.mp4"); chk "媒体全量=200" "$C" "200"

# 8. 边缘缓存：等后台写入后再请求 → HIT
sleep 8
EC=$(curl -s -m 20 -D - -o /dev/null -H "$AUTH" -H "Range: bytes=0-1023" "$BASE/media/$VIDEO/video.mp4" | grep -i "x-edge-cache" | tr -d '\r' | awk '{print $2}')
chk "边缘缓存命中=HIT" "$EC" "HIT"

# 9. 封面 → 200
C=$(curl -s -m 20 -o /dev/null -w "%{http_code}" -H "$AUTH" "$BASE/media/$VIDEO/poster.jpg"); chk "封面=200" "$C" "200"

# 10. 进度 GET → 含 rules/watchedSec/weekSec
PG=$(curl -s -m 20 "$BASE/api/progress?day=$DAY" -H "$AUTH")
chk "进度GET ok=true" "$(echo "$PG" | jq ok)" "true"
echo "$PG" | grep -q "weekSec" && ok "进度含 weekSec(本周报告)" || ko "进度缺 weekSec"

# 11. 进度 POST → watchedSec 累加
P1=$(curl -s -m 20 -X POST "$BASE/api/progress" -H "$AUTH" -H 'content-type: application/json' -d "{\"videoId\":\"$VIDEO\",\"positionSec\":30,\"day\":\"$DAY\",\"deltaSec\":30,\"minuteOfDay\":600}")
chk "进度POST ok=true" "$(echo "$P1" | jq ok)" "true"
W=$(echo "$P1" | jq watchedSec); if [ "$W" -ge 30 ] 2>/dev/null; then ok "watchedSec 累加 ($W)"; else ko "watchedSec=$W"; fi

# 12. 规则：错误 PIN → 403
C=$(curl -s -m 20 -o /dev/null -w "%{http_code}" -X POST "$BASE/api/rules" -H "$AUTH" -H 'content-type: application/json' -d '{"pin":"000000","dailyLimitMin":45}'); chk "规则错误PIN=403" "$C" "403"

# 13. 规则：正确 PIN + 时段 → 200，且回读生效
C=$(curl -s -m 20 -o /dev/null -w "%{http_code}" -X POST "$BASE/api/rules" -H "$AUTH" -H 'content-type: application/json' -d "{\"pin\":\"$PIN\",\"allowedStart\":960,\"allowedEnd\":1200}"); chk "规则保存=200" "$C" "200"
RS=$(curl -s -m 20 "$BASE/api/progress?day=$DAY" -H "$AUTH" | jq rules.allowedStart); chk "规则回读 allowedStart=960" "$RS" "960"

# 14. 拦截：当前不在 16:00-20:00 时段 → 超时段（若当前恰在时段内则跳过）
NOWMIN=$(( $(date +%H) * 60 + $(date +%M) ))
if [ "$NOWMIN" -lt 960 ] || [ "$NOWMIN" -ge 1200 ]; then
  B=$(curl -s -m 20 -X POST "$BASE/api/progress" -H "$AUTH" -H 'content-type: application/json' -d "{\"videoId\":\"$VIDEO\",\"positionSec\":5,\"day\":\"$DAY\",\"deltaSec\":0,\"minuteOfDay\":$NOWMIN}" | jq blocked)
  chk "超时段拦截=outside_allowed_hours" "$B" "outside_allowed_hours"
else
  echo "  ⏭  当前在允许时段内，跳过超时段断言"
fi

# 15. 拦截：每日上限 → daily_limit_reached（设1分钟上限，已看>60s）
curl -s -m 20 -o /dev/null -X POST "$BASE/api/rules" -H "$AUTH" -H 'content-type: application/json' -d "{\"pin\":\"$PIN\",\"dailyLimitMin\":1}"
curl -s -m 20 -o /dev/null -X POST "$BASE/api/progress" -H "$AUTH" -H 'content-type: application/json' -d "{\"videoId\":\"$VIDEO\",\"positionSec\":70,\"day\":\"$DAY\",\"deltaSec\":70,\"minuteOfDay\":$NOWMIN}"
B=$(curl -s -m 20 -X POST "$BASE/api/progress" -H "$AUTH" -H 'content-type: application/json' -d "{\"videoId\":\"$VIDEO\",\"positionSec\":71,\"day\":\"$DAY\",\"deltaSec\":1,\"minuteOfDay\":$NOWMIN}" | jq blocked)
chk "超时长拦截=daily_limit_reached" "$B" "daily_limit_reached"

# 16. 清理：解除规则（清空）；测试设备留待 D1 清理（见下方提示）
curl -s -m 20 -o /dev/null -X POST "$BASE/api/rules" -H "$AUTH" -H 'content-type: application/json' -d "{\"pin\":\"$PIN\",\"dailyLimitMin\":null,\"allowedStart\":null,\"allowedEnd\":null}"
echo "  🧹 已清空本测试设备规则（设备 $DEVID 可用 wrangler d1 删除：DELETE FROM devices WHERE id='$DEVID'）"

echo "=== 结果：通过 $pass / 失败 $fail ==="
[ "$fail" -eq 0 ]
