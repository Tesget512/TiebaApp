#!/bin/zsh
# 健壮下载：代理(7890) → 直连 → ghfast 镜像，每路最多重试 2 次；校验最小体积
# 用法: fetch.sh <输出文件绝对路径> <URL> [最小字节数,默认1000]
set -u
OUT="$1"; URL="$2"; MIN="${3:-1000}"
PROXY="${CLASH_PROXY:-http://127.0.0.1:7890}"
mkdir -p "$(dirname "$OUT")"
declare -a LABELS=(api direct proxy mirror)
for label in "${LABELS[@]}"; do
try_fetch() {
  local label="$1"
  case "$label" in
    # api 域名 asset 端点（把 github.com/owner/repo/releases/download/... 转换成 api 调用）
    # 本机实测：代理失效、github.com 直连间歇超时，api.github.com 直连 200 且下载 2MB/s
    api)    local repo="${URL#https://github.com/}"; repo="${repo%%/releases/download/*}"; local rest="${URL#https://github.com/${repo}/releases/download/}"; local tag="${rest%%/*}"; local name="${rest#*/}"; local aid
            aid=$(curl -sfL --connect-timeout 8 "https://api.github.com/repos/$repo/releases/tags/$tag" 2>/dev/null | /usr/bin/python3 -c "import sys,json;print(next(a['id'] for a in json.load(sys.stdin)['assets'] if a['name']=='$name'))" 2>/dev/null)
            if [ -z "$aid" ]; then return 1; fi
            curl -fL --connect-timeout 10 --max-time 900 -H "Accept: application/octet-stream" -o "$OUT.part" "https://api.github.com/repos/$repo/releases/assets/$aid" 2>/dev/null ;;
    proxy)  curl -fL --connect-timeout 8 --max-time 600 -x "$PROXY" -o "$OUT.part" "$URL" 2>/dev/null ;;
    direct) curl -fL --connect-timeout 10 --max-time 600 -o "$OUT.part" "$URL" 2>/dev/null ;;
    mirror) curl -fL --connect-timeout 10 --max-time 900 -o "$OUT.part" "https://ghfast.top/$URL" 2>/dev/null ;;
  esac
}
for label in "${LABELS[@]}"; do
  for attempt in 1 2; do
    echo "  [$label#$attempt] $URL" >&2
    if try_fetch "$label"; then
      SIZE=$(stat -f%z "$OUT.part" 2>/dev/null || echo 0)
      if [ "$SIZE" -ge "$MIN" ]; then
        mv "$OUT.part" "$OUT"
        echo "  ✅ [$label] $OUT ($SIZE bytes)" >&2
        exit 0
      fi
      echo "  ⚠️ [$label] 体积过小($SIZE < $MIN)，视为失败" >&2
    else
      echo "  ⚠️ [$label] 失败(exit=$?)" >&2
    fi
    sleep 2
  done
done
echo "❌ 所有通道均失败: $URL" >&2
exit 1
