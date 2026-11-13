#!/bin/bash
# 把 GitHub 仓库 videos/ 里的新视频同步到视频网站目录。
# 只下载没下过的文件；下过的记在 STATE 里，网站上删掉的视频不会被再拉回来。
REPO="fanxianzhuoniubi/video"
BRANCH="main"
DEST="/opt/videoserver/videos"
STATE="/opt/videoserver/.synced_from_github"

exec 9>/tmp/videoserver-sync.lock
flock -n 9 || exit 0                      # 上一次还没下完就跳过，避免重复下载
mkdir -p "$DEST"; touch "$STATE"

json=$(curl -fsS -m 30 -H "Accept: application/vnd.github+json" \
       "https://api.github.com/repos/$REPO/contents/videos?ref=$BRANCH") || exit 0

echo "$json" | grep -o '"download_url": *"[^"]*"' | sed 's/.*: *"\(.*\)"/\1/' |
while read -r url; do
  name=$(basename "$url")
  name=$(printf '%b' "${name//%/\\x}")    # 解码 URL 里的 %xx
  case "$name" in *.mp4|*.MP4|*.mov|*.webm|*.mkv) ;; *) continue ;; esac
  grep -qxF "$name" "$STATE" && continue  # 已经同步过
  if [ -e "$DEST/$name" ]; then echo "$name" >> "$STATE"; continue; fi
  tmp="$DEST/.$name.part"
  if curl -fsSL -m 1800 -o "$tmp" "$url"; then
    mv "$tmp" "$DEST/$name"; echo "$name" >> "$STATE"
    echo "$(date '+%F %T') 已同步 $name ($(stat -c %s "$DEST/$name") 字节)"
  else
    rm -f "$tmp"; echo "$(date '+%F %T') 下载失败 $name，5 分钟后重试"
  fi
done
