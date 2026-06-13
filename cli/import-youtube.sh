#!/usr/bin/env bash
# 在【你自己的 Mac（家庭网络）】上运行：下载一个 YouTube 播放列表并逐个上传到流媒体。
# 注意：不要在服务器/数据中心 IP 上跑——YouTube 会拦截数据中心 IP。
#
# 前置：brew install yt-dlp ffmpeg；浏览器(Chrome)已登录 YouTube；R2 环境变量已配(见 cli/README.md)。
# 用法：
#   bash cli/import-youtube.sh "<播放列表或视频URL>" "<系列名>" "<学科(可选)>"
# 示例（动物兄弟第五季 → 科学）：
#   bash cli/import-youtube.sh \
#     "https://www.youtube.com/playlist?list=PLzAMELnCkLjBE4LhXJVpzHUXxNzesVcfG" \
#     "动物兄弟 第五季" "科学"

set -euo pipefail
PLAYLIST="${1:?用法: import-youtube.sh <URL> <系列名> [学科]}"
SERIES="${2:-未分类系列}"
CATEGORY="${3:-}"
BROWSER="${COOKIES_BROWSER:-chrome}"   # 可改 safari/firefox/edge

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /tmp/yt-import.XXXXXX)"
cd "$WORK"
echo "▶ 下载到 $WORK（720p / H.264 / AAC / 内嵌中英字幕）..."

# env -u NODE_OPTIONS：某些环境注入的 NODE_OPTIONS 会破坏 yt-dlp 的 JS 解算器（解 n-challenge）；清掉它最稳。
# player_client=web,tv,web_safari：换 web 客户端签名的媒体 URL，避开默认客户端的 403。
env -u NODE_OPTIONS yt-dlp --cookies-from-browser "$BROWSER" \
  --extractor-args "youtube:player_client=web,tv,web_safari" \
  -S "res:720,vcodec:h264,acodec:aac" --merge-output-format mp4 \
  --write-subs --write-auto-subs --sub-langs "zh-Hans,zh,en" \
  --convert-subs srt --embed-subs --embed-metadata \
  --download-archive archive.txt \
  -R 20 --fragment-retries 40 \
  -o "%(playlist_index)02d-%(title)s.%(ext)s" \
  "$PLAYLIST"

catarg=()
[ -n "$CATEGORY" ] && catarg=(--category "$CATEGORY")

shopt -s nullglob
echo "▶ 串行上传（manifest 读改写，勿并行）..."
for f in *.mp4; do
  base="${f%.*}"
  title="${base#*-}"     # 去掉 "01-" 这类序号前缀
  echo "  ↑ $title"
  node "$ROOT/cli/src/index.js" upload "$f" \
    --title "$title" --series "$SERIES" "${catarg[@]}" --json
done

echo "✅ 完成。播放器刷新即可看到「$SERIES」。临时文件在：$WORK（确认无误后可删）"
