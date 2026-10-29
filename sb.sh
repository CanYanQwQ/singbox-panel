#!/usr/bin/env bash

# ============================================================
# Sing-box Elite Management System
# 由 build.sh 自动合并生成，请勿直接编辑此文件
# 源码位于 lib/ 目录下的各模块文件
# ============================================================


# >>>>>>>>> BEGIN MODULE: 00_base.sh <<<<<<<<<<<
# ============================================================
# 模块: 00_base.sh
# 职责: 全局常量、颜色码、UI 基础函数、协议注册表、共享 jq 模板
# ============================================================

# ============================================================
# 解释器引导（POSIX sh 兼容，必须位于任何 bash 专有语法之前）
# ------------------------------------------------------------
# 本脚本需要 bash 4+（关联数组、mapfile、$'\x01'、[[ ]]）。
# 但 Alpine / 极简系统默认只有 busybox ash，连 bash 都可能没装，
# 此时 `bash /root/sb.sh` 会直接 "bash: not found"，脚本一行都跑不到。
#
# 这里用纯 POSIX 语法做一次引导：无论用户用 `sh sb.sh`、`ash sb.sh`
# 还是 `dash sb.sh` 启动，都会在这里换成 bash 并重新执行自身；
# 系统没有 bash 时先按包管理器自动装上。
#
# ash/dash 是逐条读取执行的，下方的 bash 专有语法在 exec 成功替换
# 进程后永远不会被解析，因此这段引导可以安全地放在同一文件里。
#
# 注意：判据不能用 `command -v bash`。busybox 自带一个名为 bash 的
# applet，它其实是 ash 的别名——`command -v bash` 会成功返回，但那个
# "bash" 里 BASH_VERSION 依然为空，于是脚本 exec 自己、再 exec 自己，
# 变成无限递归（极简/嵌入式系统上尤其常见）。唯一可靠的判据是让候选
# 解释器真的跑一次并报出 BASH_VERSION。
# ============================================================
if [ -z "${BASH_VERSION:-}" ]; then
  # 重入哨兵：已经重执行过一次却仍不是真 bash，就报错退出，
  # 绝不再 exec 一次（否则就是上面说的死循环）。
  if [ "${_SB_REEXEC_TRIED:-0}" = "1" ]; then
    echo "[ERROR] 当前 shell 不是真 bash（BASH_VERSION 为空），重执行也未能启动 bash。" >&2
    echo "        系统里的 bash 可能只是 busybox 的同名别名，请先安装真正的 bash：" >&2
    echo "        Alpine: apk add bash" >&2
    echo "        Debian/Ubuntu: apt-get install -y bash" >&2
    exit 1
  fi
  _SB_REEXEC_TRIED=1
  export _SB_REEXEC_TRIED

  # 真 bash 判据：能报出非空的 BASH_VERSION。
  # 用 $( ) 捕获而不是写临时文件：$( ) 是纯 POSIX，不需要 /tmp 可写，
  # 在只读根文件系统（Docker scratch、OpenWrt、部分极简镜像）上也能用。
  # 不用 [ -x ] 预判：精简环境的权限位/挂载选项不可信，直接试着执行、
  # 只看它吐不吐 BASH_VERSION 才是唯一稳的判据。
  _sb_is_real_bash() {
    [ -n "$( "$1" -c 'printf %s "${BASH_VERSION:-}"' 2>/dev/null )" ]
  }

  _sb_find_and_exec_bash() {
    # 直接试绝对路径，不走 command -v，避免命中 busybox 的同名别名
    for _sb_b in bash /bin/bash /usr/bin/bash /usr/local/bin/bash \
                 /bin/bash4 /usr/bin/bash4; do
      if _sb_is_real_bash "$_sb_b"; then
        exec "$_sb_b" "$0" "$@"
      fi
    done
    return 1
  }

  # $0 为 sh/bash 本身（例如 curl | sh）时无法自我重执行
  case "$0" in
    sh|bash|dash|ash|*/sh|*/bash|*/dash|*/ash|"")
      echo "[ERROR] 检测到缺少 bash，且当前为管道或交互式执行，无法自动重启动。" >&2
      echo "        请先下载为文件再运行：curl -fsSL <url> -o /root/sb.sh && sh /root/sb.sh" >&2
      exit 1
      ;;
  esac

  _sb_find_and_exec_bash "$@" || true

  # 没找到真 bash：按包管理器安装后重试一次
  echo "[INFO] 未找到可用的 bash，正在尝试自动安装..." >&2
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache bash >/dev/null 2>&1 || true
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y bash >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bash >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y bash >/dev/null 2>&1 || true
  elif command -v zypper >/dev/null 2>&1; then
    zypper install -y bash >/dev/null 2>&1 || true
  elif command -v pacman >/dev/null 2>&1; then
    pacman -S --noconfirm bash >/dev/null 2>&1 || true
  fi

  _sb_find_and_exec_bash "$@" || true

  echo "[ERROR] 无法安装 bash。请先手动安装再运行本脚本：" >&2
  echo "        Alpine: apk add bash" >&2
  echo "        Debian: apt-get install -y bash" >&2
  exit 1
fi
unset _SB_REEXEC_TRIED 2>/dev/null || true

# 至此已确认运行在 bash 下，后续可安全使用 bash 专有语法。
set -Eeuo pipefail

# -------------------- 版本 --------------------
SCRIPT_VERSION="6.1.9"

# -------------------- 路径常量 --------------------
CONFIG_FILE="/etc/sing-box/config.json"
SCRIPT_SELF="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[0]:-$0}")"
SB_TARGET_SCRIPT="/root/sb.sh"
SB_SHORTCUT="/usr/local/bin/s"
SINGBOX_RELEASE_REPO="Tangfffyx/sing-box"
SINGBOX_INSTALL_DIR="/usr/local/bin"
SINGBOX_BIN="${SINGBOX_INSTALL_DIR}/sing-box"
SINGBOX_VERSION_STAMP="/etc/sing-box/.installed_release"
GRPCURL_BIN="/usr/local/bin/grpcurl"
V2RAY_API_LISTEN="127.0.0.1:18080"
V2RAY_PROTO_V2RAY="/etc/sing-box/v2rayapi-v2ray.proto"
USER_WATCH_CRON_MARK="sb.sh --user-watch"
USER_WATCH_CRON_SCHEDULE="*/5 * * * *"
LOG_MAINTAIN_CRON_MARK="sb.sh --maintain-logs"
LOG_MAINTAIN_CRON_SCHEDULE="0 4 * * *"
UPSTREAM_REFRESH_CRON_MARK="sb.sh --refresh-upstream"
UPSTREAM_REFRESH_CRON_SCHEDULE="47 3 * * *"
PERIODIC_SYNC_CRON_MARK="sb.sh --periodic-sync"
# 低内存优化：原为 */3（每 3 分钟一次），每次都会 fork 一个完整 bash 去加载
# 1 万行脚本，128MB 机器上这是可观的峰值内存压力。到期/配额巡检 5 分钟
# 足够（账期精度是天，不是分钟），故放宽到每 5 分钟。
PERIODIC_SYNC_CRON_SCHEDULE="*/5 * * * *"
DAILY_MAINTENANCE_CRON_MARK="sb.sh --daily-maintenance"
DAILY_MAINTENANCE_CRON_SCHEDULE="47 4 * * *"
UPSTREAM_TAG_CACHE_FILE="/etc/sing-box-manager/.upstream-tag-cache"
UPSTREAM_TAG_CACHE_MAX_AGE_SECS=172800
SCRIPT_LOG_FILE="/var/log/sing-box/access.log"
LOG_MAX_BYTES=$((10 * 1024 * 1024))
USER_DB_FILE="/etc/sing-box-manager/user-manager.json"
META_FILE="/etc/sing-box-manager/meta.json"
SB_LOCK_FILE="/var/lock/singbox-manager.lock"

# 业务时区：所有"今天/本月"判断（重置日、到期日、续期）都按它算，
# 与 OS 时区无关，避免跨 VPS 因 OS 时区不同导致重置/到期时刻分裂。
BUSINESS_TZ="Asia/Shanghai"

# -------------------- 颜色 --------------------
B='\033[1;34m'; G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'
C='\033[1;36m'; NC='\033[0m'; W='\033[1;37m'

# -------------------- 日志/UI 函数 --------------------
say()  { echo -e "${C}[INFO]${NC} $*"; }
ok()   { echo -e "${G}[ OK ]${NC} $*"; }
warn() { echo -e "${Y}[WARN]${NC} $*" >&2; }
err()  { echo -e "${R}[ERR ]${NC} $*" >&2; }
pause(){ read -r -n 1 -p "按任意键继续..." || true; echo ""; }
ui_echo(){ printf '%b\n' "$*" >&2; }

param_echo() {
  local label="$1" value="$2"
  printf '  %b%s%b: %b%s%b\n' "$W" "$label" "$NC" "$C" "$value" "$NC" >&2
}

text_display_width() {
  local s="${1:-}"
  local width=0
  local i ch ord

  for ((i=0; i<${#s}; i++)); do
    ch="${s:i:1}"
    LC_ALL=C printf -v ord '%d' "'$ch" 2>/dev/null || ord=255
    if (( ord >= 32 && ord <= 126 )); then
      width=$((width + 1))
    else
      width=$((width + 2))
    fi
  done

  echo "$width"
}

pad_display_text() {
  local text="${1:-}"
  local target_width="${2:-0}"
  local current_width pad
  current_width="$(text_display_width "$text")"
  if [ "$current_width" -ge "$target_width" ]; then
    printf "%s" "$text"
    return 0
  fi
  pad=$((target_width - current_width))
  printf "%s%*s" "$text" "$pad" ""
}

print_rect_title() {
  local title="$1"
  local inner_width=46
  local title_width pad left right line

  title_width=$(text_display_width "$title")
  pad=$(( inner_width - title_width ))
  (( pad < 0 )) && pad=0

  left=$(( pad / 2 ))
  right=$(( pad - left ))

  line=$(printf '%*s' "$inner_width" '' | tr ' ' '-')

  printf "%b+%s+%b\n" "$B" "$line" "$NC"
  printf "%b|%*s%s%*s|%b\n" "$B" "$left" "" "$title" "$right" "" "$NC"
  printf "%b+%s+%b\n" "$B" "$line" "$NC"
}

table_compute_widths() {
  local sep="$1"
  shift
  local -a rows=("$@")
  local -a widths=()
  local row i w
  local -a cols=()
  for row in "${rows[@]}"; do
    IFS="$sep" read -r -a cols <<< "$row"
    for i in "${!cols[@]}"; do
      w="$(text_display_width "${cols[$i]}")"
      if [ -z "${widths[$i]:-}" ] || [ "$w" -gt "${widths[$i]}" ]; then
        widths[$i]="$w"
      fi
    done
  done
  local -a out=()
  for i in "${!widths[@]}"; do
    out+=("$((widths[$i] + 2))")
  done
  printf '%s\n' "${out[*]}"
}

table_print_row() {
  local widths_line="$1"
  shift
  local -a widths=()
  local -a cells=("$@")
  local i out=""
  read -r -a widths <<< "$widths_line"
  for i in "${!cells[@]}"; do
    out+="$(pad_display_text "${cells[$i]}" "${widths[$i]}")"
  done
  printf '%s\n' "$out"
}

# ====================================================
# 协议注册表 — 所有协议定义的唯一权威来源
# 新增协议：只需在此注册 + 写 builder + 写 exporter
# ====================================================
SUPPORTED_PROTOCOLS=(vless-reality anytls shadowsocks socks trojan vmess-ws vless-ws tuic)

declare -A PROTO_PREFIX=(
  [vless-reality]=reality
  [anytls]=anytls
  [shadowsocks]=ss
  [trojan]=trojan
  [vmess-ws]=vmess-ws
  [vless-ws]=vless-ws
  [tuic]=tuic
  [socks]=socks
)

declare -A PREFIX_TO_PROTO=()
for proto in "${SUPPORTED_PROTOCOLS[@]}"; do
  PREFIX_TO_PROTO["${PROTO_PREFIX[$proto]}"]="$proto"
done
unset proto

declare -A PROTO_TRANSPORT=(
  [vless-reality]=tcp
  [anytls]=tcp
  [shadowsocks]="tcp udp"
  [trojan]=tcp
  [vmess-ws]=tcp
  [vless-ws]=tcp
  [tuic]=udp
  [socks]=tcp
)

# ====================================================
# 共享 jq 模板 — 消除跨模块重复定义
# 使用方式：echo "$json" | jq "${JQ_DETECT_PROTOCOL} ..."
# ====================================================
#
# 【项目标准】jq 多字段输出与 bash read 配合规范
# ----------------------------------------------------
# 当需要从 jq 输出中用 read 拆分多个字段，且任一字段可能为空时，
# 必须使用 \x01 (SOH) 作为分隔符，而不是 \t (@tsv)：
#
#   ✔ 正确：
#     jq -r '[...] | join("\u0001")' | {
#       IFS=$'\x01' read -r a b c d
#     }
#
#   ✘ 错误（已知 bug 源，v5.3.5 修复过）：
#     jq -r '[...] | @tsv' | {
#       IFS=$'\t' read -r a b c d   # 连续 tab 被折叠，空字段导致字段左移
#     }
#
# 原因：bash 默认 IFS 包含 tab，遇到连续 tab 会折叠为单个分隔符。
#       \x01 不在默认 IFS 中，连续 \x01 会严格保留空字段位置。
# ====================================================

# 协议检测：将 inbound 对象映射为协议标签（唯一定义）
JQ_DETECT_PROTOCOL='
def detect_protocol:
  if .type == "vless" and (.tls.reality.enabled // false) then "vless-reality"
  elif .type == "anytls" then "anytls"
  elif .type == "shadowsocks" then "shadowsocks"
  elif .type == "trojan" then "trojan"
  elif .type == "vmess" and ((.transport.type // "") == "ws") then "vmess-ws"
  elif .type == "vless" and ((.transport.type // "") == "ws") then "vless-ws"
  elif .type == "tuic" then "tuic"
  elif .type == "socks" then "socks"
  else ""
  end;
'

# auth_user 统一数组化（唯一定义，取代 8 处内联）
JQ_AUTH_USERS='
def auth_users_array:
  if (.auth_user? == null) then []
  elif ((.auth_user | type) == "array") then .auth_user
  else [ .auth_user ]
  end;
'

# node_part 提取（唯一定义）
JQ_NODE_PART='
def node_part($s):
  if ($s | contains("@")) then ($s | split("@")[0]) else $s end;
'

# 协议排序索引：将 tag/node_key 映射为排序序号（唯一定义）
JQ_PROTOCOL_SORT='
def protocol_sort_index($tag):
  if ($tag | startswith("reality-")) then 0
  elif ($tag | startswith("anytls-")) then 1
  elif ($tag | startswith("ss-")) then 2
  elif ($tag | startswith("socks-")) then 3
  elif ($tag | startswith("trojan-")) then 4
  elif ($tag | startswith("vmess-ws-")) then 5
  elif ($tag | startswith("vless-ws-")) then 6
  elif ($tag | startswith("tuic-")) then 7
  else 99
  end;
'

# 组合：常用 jq 前缀（包含所有共享定义）
JQ_SHARED="${JQ_DETECT_PROTOCOL}${JQ_AUTH_USERS}${JQ_NODE_PART}${JQ_PROTOCOL_SORT}"

# ====================================================
# 节点排序基础设施 — bash 层面的协议排序
# 所有需要按协议排序的地方统一调用这些函数
# ====================================================

# 返回 node key 的排序序号（00-06，未知为 99）
node_protocol_sort_key() {
  local key="$1"
  local i=0 prefix
  for proto in "${SUPPORTED_PROTOCOLS[@]}"; do
    prefix="${PROTO_PREFIX[$proto]}"
    if [[ "$key" == "${prefix}-"* ]]; then
      printf '%02d' "$i"
      return 0
    fi
    i=$((i+1))
  done
  printf '99'
}

# 从 stdin 读取 node key，按协议顺序排序后输出
sort_node_keys_by_protocol() {
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    printf '%s\t%s\n' "$(node_protocol_sort_key "$key")" "$key"
  done | sort -t$'\t' -k1,1 -k2,2 | cut -f2
}

# 从 stdin 读取 SOH(\x01) 分隔行，按指定字段的协议顺序排序
# 保留旧函数名以兼容已有调用；用法：some_command | sort_tsv_by_protocol 1
sort_tsv_by_protocol() {
  local field="${1:-1}"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local fval
    fval="$(echo "$line" | cut -d$'\x01' -f"$field")"
    printf '%s\t%s\n' "$(node_protocol_sort_key "$fval")" "$line"
  done | sort -t$'\t' -k1,1 | cut -f2-
}


# >>>>>>>>> END MODULE: 00_base.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 01_utils.sh <<<<<<<<<<<
# ============================================================
# 模块: 01_utils.sh
# 职责: 通用工具函数（无业务逻辑依赖）
# ============================================================

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "请使用 root 运行此脚本。"
    exit 1
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

make_disk_tmp_dir() {
  local prefix="${1:-sb-install}" base="/var/tmp" tmp_dir
  mkdir -p "$base" 2>/dev/null || base="/tmp"
  tmp_dir="$(mktemp -d "${base}/${prefix}.XXXXXX")" || return 1
  echo "$tmp_dir"
}

random_b64_password() {
  local bytes="${1:-16}" value
  value="$(openssl rand -base64 "$bytes" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    value="$(head -c "$bytes" /dev/urandom 2>/dev/null | openssl base64 -A 2>/dev/null || true)"
  fi
  [ -n "$value" ] && echo "$value"
}

run_with_timeout() {
  local seconds="$1"
  shift
  if has_cmd timeout; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

download_file() {
  local url="$1" output="$2" connect_timeout="${3:-20}" retry_count="${4:-3}"
  if [ ! -t 1 ] || [ ! -t 2 ]; then
    curl -fsSL --connect-timeout "$connect_timeout" --retry "$retry_count" "$url" -o "$output" >/dev/null 2>&1
    return $?
  fi

  local total tmp_err curl_pid rc size tick=0
  total="$(download_file_total_bytes "$url" "$connect_timeout")"
  tmp_err="$(mktemp /tmp/sb-download-err.XXXXXX)" || return 1
  rm -f "$output" >/dev/null 2>&1 || true

  curl -fsSL --connect-timeout "$connect_timeout" --retry "$retry_count" "$url" -o "$output" 2>"$tmp_err" &
  curl_pid=$!
  while kill -0 "$curl_pid" 2>/dev/null; do
    size="$(file_size_bytes "$output")"
    print_download_progress "$size" "$total" "$tick"
    tick=$((tick + 1))
    sleep 1
  done

  if wait "$curl_pid"; then
    rc=0
  else
    rc=$?
  fi

  clear_download_progress
  if [ "$rc" -ne 0 ] && [ -s "$tmp_err" ]; then
    sed 's/^/  /' "$tmp_err" >&2
  fi
  rm -f "$tmp_err" >/dev/null 2>&1 || true
  return "$rc"
}

download_file_total_bytes() {
  local url="$1" connect_timeout="${2:-20}" total
  [ "$connect_timeout" -gt 5 ] && connect_timeout=5
  total="$(curl -fsSIL --connect-timeout "$connect_timeout" --max-time 10 "$url" 2>/dev/null \
    | awk 'tolower($1) == "content-length:" {gsub(/\r/,"",$2); n=$2} END {if (n ~ /^[0-9]+$/) print n}')" || true
  echo "${total:-0}"
}

file_size_bytes() {
  local file="$1" size
  [ -f "$file" ] || { echo 0; return 0; }
  size="$(stat -c '%s' "$file" 2>/dev/null || wc -c < "$file" 2>/dev/null || echo 0)"
  size="${size//[[:space:]]/}"
  [[ "$size" =~ ^[0-9]+$ ]] || size=0
  echo "$size"
}

format_download_bytes() {
  local bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN {
    if (b >= 1073741824) printf "%.1fG", b / 1073741824;
    else if (b >= 1048576) printf "%.1fM", b / 1048576;
    else if (b >= 1024) printf "%.1fK", b / 1024;
    else printf "%dB", b;
  }'
}

print_download_progress() {
  local size="${1:-0}" total="${2:-0}" tick="${3:-0}" width=24
  local percent filled bar spin
  if [[ "$total" =~ ^[0-9]+$ ]] && [ "$total" -gt 0 ]; then
    percent=$((size * 100 / total))
    [ "$percent" -gt 100 ] && percent=100
    filled=$((percent * width / 100))
    bar="$(printf '%*s' "$filled" '' | tr ' ' '=')"
    if [ "$filled" -lt "$width" ]; then
      bar="${bar}>$(printf '%*s' $((width - filled - 1)) '')"
    fi
    printf '\r下载中 [%-*s] %3d%% %s/%s' "$width" "$bar" "$percent" "$(format_download_bytes "$size")" "$(format_download_bytes "$total")"
  else
    case $((tick % 4)) in
      0) spin="|" ;;
      1) spin="/" ;;
      2) spin="-" ;;
      *) spin="\\" ;;
    esac
    printf '\r下载中 [%s] %s' "$spin" "$(format_download_bytes "$size")"
  fi
}

clear_download_progress() {
  local cols="${COLUMNS:-80}"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  printf '\r%*s\r' "$cols" ''
}

now_ms() {
  local value
  value="$(date +%s%3N 2>/dev/null || true)"
  if [[ "$value" =~ ^[0-9]{13,}$ ]]; then
    echo "$value"
    return 0
  fi
  value="$(date +%s 2>/dev/null || true)"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo $((value * 1000))
  else
    echo 0
  fi
}

# ---------- 包管理器 / init 系统检测 ----------

detect_pkg_manager() {
  if has_cmd apt-get; then echo "apt"
  elif has_cmd apk;   then echo "apk"
  else                     echo "unknown"
  fi
}
PKG_MANAGER="$(detect_pkg_manager)"

detect_init_system() {
  if has_cmd systemctl && systemctl --version >/dev/null 2>&1; then echo "systemd"
  elif has_cmd rc-service; then echo "openrc"
  else                          echo "unknown"
  fi
}
INIT_SYSTEM="$(detect_init_system)"

# ---------- 包管理抽象 ----------

pkg_installed() {
  case "$PKG_MANAGER" in
    apt) [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null || true)" = "installed" ] ;;
    apk) apk info -e "$1" >/dev/null 2>&1 ;;
    *)   return 1 ;;
  esac
}

pkg_update_once() {
  local stamp="/tmp/.sb_pkg_updated"
  [ -f "$stamp" ] && return 0
  case "$PKG_MANAGER" in
    apt)
      [ "${_PKG_INSTALL_QUIET:-0}" = "1" ] || say "更新包索引..."
      if [ "${_PKG_INSTALL_QUIET:-0}" = "1" ]; then
        apt-get update -y >/dev/null 2>&1
      else
        apt-get update -y
      fi
      ;;
    apk)
      [ "${_PKG_INSTALL_QUIET:-0}" = "1" ] || say "更新包索引..."
      if [ "${_PKG_INSTALL_QUIET:-0}" = "1" ]; then
        apk update -q >/dev/null 2>&1
      else
        apk update -q
      fi
      ;;
  esac
  touch "$stamp"
}

install_pkg() {
  local pkg="$1"
  pkg_installed "$pkg" && return 0
  pkg_update_once
  [ "${_PKG_INSTALL_QUIET:-0}" = "1" ] || say "安装依赖: $pkg"
  case "$PKG_MANAGER" in
    apt)
      if [ "${_PKG_INSTALL_QUIET:-0}" = "1" ]; then
        apt-get install -y "$pkg" >/dev/null 2>&1 || { err "依赖安装失败：$pkg"; return 1; }
      else
        apt-get install -y "$pkg"
      fi
      ;;
    apk)
      if [ "${_PKG_INSTALL_QUIET:-0}" = "1" ]; then
        apk add -q "$pkg" >/dev/null 2>&1 || { err "依赖安装失败：$pkg"; return 1; }
      else
        apk add -q "$pkg"
      fi
      ;;
    *)   err "不支持的包管理器，请手动安装: $pkg"; return 1 ;;
  esac
}

# 保留旧名以避免遗漏调用
install_pkg_apt() { install_pkg "$@"; }
apt_update_once()  { pkg_update_once; }

# ---------- 服务检测 ----------

singbox_service_active() {
  case "$INIT_SYSTEM" in
    systemd) has_cmd systemctl && systemctl is-active --quiet sing-box 2>/dev/null ;;
    openrc)  rc-service sing-box status >/dev/null 2>&1 ;;
    *)       return 1 ;;
  esac
}

generate_random_alpha_path() {
  local s
  s="$(openssl rand -base64 32 2>/dev/null | tr -dc 'A-Za-z' | head -c 7 || true)"
  [ ${#s} -ge 7 ] || s="$(head -c 32 /dev/urandom 2>/dev/null | tr -dc 'A-Za-z' | head -c 7 || echo "xBqLmRt")"
  echo "/${s:0:7}"
}

normalize_ws_path() {
  local p="${1:-}"
  if [ -z "$p" ]; then
    generate_random_alpha_path
    return 0
  fi
  [[ "$p" != /* ]] && p="/$p"
  echo "$p"
}

get_public_ip() {
  if [ -n "${_CACHED_PUBLIC_IP:-}" ]; then
    echo "$_CACHED_PUBLIC_IP"
    return 0
  fi
  local ip=""
  ip=$(curl -s4 --max-time 3 --connect-timeout 2 ifconfig.me 2>/dev/null || true)
  [ -z "$ip" ] && ip=$(curl -s4 --max-time 3 --connect-timeout 2 api.ipify.org 2>/dev/null || true)
  [ -z "$ip" ] && ip=$(curl -s4 --max-time 3 --connect-timeout 2 icanhazip.com 2>/dev/null | tr -d '\n' || true)
  [ -z "$ip" ] && ip="IP"
  _CACHED_PUBLIC_IP="$ip"
  echo "$ip"
}

parse_plus_selections() {
  local s="$1"
  local -A seen=()
  local out=()
  local x
  IFS='+' read -ra parts <<< "$s"
  for x in "${parts[@]}"; do
    x="$(echo "$x" | tr -d ' ')"
    [ -z "$x" ] && continue
    if [ -z "${seen[$x]:-}" ]; then
      out+=("$x")
      seen[$x]=1
    fi
  done
  printf "%s\n" "${out[@]}"
}

ask_confirm_yes() {
  local prompt="${1:-输入 YES 确认继续，其它任意输入取消: }"
  local ans
  read -r -p "$prompt" ans
  [ "$ans" = "YES" ]
}

ask_confirm_yn() {
  local prompt="${1:-确认继续吗？(y/N): }"
  local ans
  printf '%s' "$prompt" >&2
  read -r ans || ans=""
  [[ "$ans" =~ ^[Yy]$ ]]
}

is_valid_ymd_date() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  awk -v value="$value" '
    function leap(y) { return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) }
    function dim(y, m) {
      if (m == 2) return leap(y) ? 29 : 28
      if (m == 4 || m == 6 || m == 9 || m == 11) return 30
      return 31
    }
    BEGIN {
      split(value, a, "-")
      y = a[1] + 0; m = a[2] + 0; d = a[3] + 0
      if (y < 1 || m < 1 || m > 12 || d < 1 || d > dim(y, m)) exit 1
    }
  '
}

is_valid_port() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  [ "$v" -ge 1 ] && [ "$v" -le 65535 ]
}

ask_port_or_return() {
  local prompt="$1" default="$2" outvar="$3"
  local val __retry
  while true; do
    read -r -p "$prompt" val
    if [ -z "$val" ]; then
      val="$default"
    fi
    if is_valid_port "$val"; then
      printf -v "$outvar" '%s' "$val"
      return 0
    fi
    warn "端口输入无效：${val}。请输入 1-65535 的数字，回车使用默认值 ${default}。"
    read -r -p "输入 1 重新填写，其它任意键返回上一级: " __retry
    [ "${__retry:-}" = "1" ] || return 1
  done
}

json_is_object() {
  local s="${1:-}"
  [ -n "$s" ] && echo "$s" | jq -e 'type=="object"' >/dev/null 2>&1
}

format_traffic_auto() {
  local bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN {
    if (b < 1024*1024*1024) printf("%.1f MB", b/1024/1024);
    else if (b < 1024*1024*1024*1024) printf("%.1f GB", b/1024/1024/1024);
    else printf("%.1f TB", b/1024/1024/1024/1024);
  }'
}

format_bytes_human() { format_traffic_auto "$@"; }

reset_day_text() {
  case "${1:-0}" in
    0|"") echo "不重置" ;;
    32) echo "月底" ;;
    *) echo "${1}号" ;;
  esac
}

expire_text() {
  local v="${1:-}"
  [ -n "$v" ] && [ "$v" != "0" ] && echo "$v" || echo "永久"
}

parse_traffic_to_bytes() {
  local raw="${1:-}" normalized num unit sign=1
  normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  if [[ "$normalized" == -* ]]; then
    sign=-1
    normalized="${normalized#-}"
  fi
  if [[ ! "$normalized" =~ ^([0-9]+(\.[0-9])?)(mb|gb|tb)$ ]]; then
    return 1
  fi
  num="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[3]}"
  awk -v n="$num" -v u="$unit" -v s="$sign" 'BEGIN {
    if (u == "mb") printf "%.0f", s * n * 1048576;
    else if (u == "gb") printf "%.0f", s * n * 1073741824;
    else if (u == "tb") printf "%.0f", s * n * 1099511627776;
    else exit 1;
  }'
}

is_valid_user_name() {
  local u="${1:-}"
  [[ -n "$u" ]] || return 1
  [[ "$u" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$u" != *"@"* ]] || return 1
  [[ "$u" != *"/"* ]] || return 1
  [[ "$u" != *":"* ]] || return 1
  [[ "$u" != *" "* ]] || return 1
}

user_node_part() {
  local name="${1:-}"
  if [[ "$name" == *"@"* ]]; then
    echo "${name%%@*}"
  else
    echo "$name"
  fi
}

user_business_name() {
  local name="${1:-}"
  if [[ "$name" == *"@"* ]]; then
    echo "${name#*@}"
  else
    echo "admin"
  fi
}

node_user_name() {
  local node_key="$1" username="$2"
  if [ "$username" = "admin" ]; then
    echo "$node_key"
  else
    echo "${node_key}@${username}"
  fi
}

# >>>>>>>>> END MODULE: 01_utils.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 10_config.sh <<<<<<<<<<<
# ============================================================
# 模块: 10_config.sh
# 职责: 配置文件加载/校验/应用/回滚/重启服务
# 依赖: 00_base.sh, 01_utils.sh
# ============================================================

config_min_template() {
  cat <<'JSON'
{
  "log": {"level": "info", "output": "/var/log/sing-box/access.log", "timestamp": true},
  "inbounds": [],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "reject"}
  ],
  "route": {"rules": [], "final": "reject"},
  "experimental": {"cache_file": {"enabled": true}}
}
JSON
}

config_normalize() {
  local json="$1"
  if [ -z "$json" ]; then
    json="$(config_min_template)"
  fi
  echo "$json" | jq '
    if type != "object" then
      {
        "log": {"level":"info","output":"/var/log/sing-box/access.log","timestamp":true},
        "inbounds": [],
        "outbounds": [
          {"type":"direct","tag":"direct"},
          {"type":"block","tag":"reject"}
        ],
        "route": {"rules": [], "final": "reject"}
      }
    else . end
    | .log = (.log // {"level":"info","output":"/var/log/sing-box/access.log","timestamp":true})
    | .inbounds = (.inbounds // [])
    | .outbounds = (.outbounds // [])
    | .route = (.route // {"rules": [], "final": "reject"})
    | .route.rules = (.route.rules // [])
    | .route.final = "reject"
    | if (.route.rule_set? == null) then .
      else
        .route.rule_set = (
          (.route.rule_set | if type == "array" then . else [.] end)
          | map(
              if ((.type // "") == "remote" and (((.tag // "") | startswith("warp-geosite-")) or ((.tag // "") | startswith("relay-geosite-")))) then
                .format = (.format // "binary")

              else .
              end
            )
          | reduce .[] as $rs ({seen:{}, out:[]};
              ($rs.tag // "") as $tag
              | if $tag == "" then
                  .out += [$rs]
                elif (.seen[$tag] == null) then
                  .seen[$tag] = (.out | length)
                  | .out += [$rs]
                else
                  .out[.seen[$tag]] = $rs
                end
            )
          | .out
        )
      end
    | .experimental = (.experimental // {})
    | .experimental.cache_file = (.experimental.cache_file // {})
    | .experimental.cache_file.enabled = true
    | if (.outbounds | any((.tag // "")=="direct")) then . else .outbounds += [{"type":"direct","tag":"direct"}] end
    | if (.outbounds | any((.tag // "")=="reject")) then . else .outbounds += [{"type":"block","tag":"reject"}] end
  ' | config_migrate_114

}

# Canonical 1.14 format. Preserve custom download detours and direct dialer options.
config_migrate_114() {
  jq '
    . as $root
    | def client($tag):
        ([$root.outbounds[]? | select(.tag == $tag)][0]) as $out
        | if $out.type == "direct" and ($out | del(.type,.tag) | length) == 0
          then {version:2} else {version:2,detour:$tag} end;
    .route.rule_set |= (if . == null then . else map(
      if .type == "remote" then
        if (.http_client? == null) then
          .http_client = (if (.download_detour // "") != "" then client(.download_detour)
            elif ($root.http_clients // [] | length) > 0 or ($root.route.default_http_client // "") != "" then null
            else client(if ($root.route.final // "reject") == "reject" then "direct" else $root.route.final end) end)
        else . end
        | del(.download_detour)
        | if .http_client == null then del(.http_client)
          elif (.http_client|type) == "object" and (.http_client.detour // "") != "" then
            .http_client as $c | client($c.detour) as $base
            | if $base.detour? == null then .http_client |= del(.detour) else . end
          else . end
      else . end) end)
    | if .route.rule_set == null then del(.route.rule_set) else . end
    | [.outbounds[]? | select(.type == "block") | .tag] as $blocks
    | .route.rules |= map(walk(if type == "object" and .outbound? != null
        then .outbound as $o | if ($blocks|index($o)) != null then del(.outbound) | .action="reject" else . end
        else . end))
    | .outbounds |= map(select(.type != "block"))
    | del(.route.final)
    | .route.rules = ([.route.rules[]? | select(. != {action:"reject"})] + [{action:"reject"}])
  '
}

config_load() {
  if [ -s "$CONFIG_FILE" ] && jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
    config_normalize "$(cat "$CONFIG_FILE")"
  else
    config_min_template | config_migrate_114
  fi
}

config_ensure_exists() {
  mkdir -p /etc/sing-box
  chmod 700 /etc/sing-box 2>/dev/null || true
  if [ ! -e "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
    warn "未发现配置文件，将写入最小模板：$CONFIG_FILE"
    config_min_template | config_migrate_114 > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    return 0
  fi

  if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
    local ts broken
    ts="$(date +%Y%m%d_%H%M%S)"
    broken="${CONFIG_FILE}.broken.${ts}"
    cp -a "$CONFIG_FILE" "$broken" 2>/dev/null || true
    warn "检测到配置文件不是合法 JSON，已备份到：$broken"
    config_min_template | config_migrate_114 > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    return 0
  fi
}

ensure_manager_file_permissions() {
  mkdir -p /etc/sing-box "$(dirname "$USER_DB_FILE")" "$(dirname "$META_FILE")"
  chmod 700 /etc/sing-box "$(dirname "$USER_DB_FILE")" "$(dirname "$META_FILE")" 2>/dev/null || true
  [ -e "$CONFIG_FILE" ] && chmod 600 "$CONFIG_FILE" 2>/dev/null || true
  [ -e "$USER_DB_FILE" ] && chmod 600 "$USER_DB_FILE" 2>/dev/null || true
  [ -e "$META_FILE" ] && chmod 600 "$META_FILE" 2>/dev/null || true
}

check_config_or_print() {
  if ! has_cmd sing-box; then
    err "未找到 sing-box 命令。请先安装。"
    return 1
  fi
  if [ ! -f "$CONFIG_FILE" ]; then
    err "未找到配置文件：$CONFIG_FILE"
    return 1
  fi
  if sing-box check -c "$CONFIG_FILE" >/dev/null 2>&1; then
    return 0
  fi
  err "配置校验失败：sing-box check -c $CONFIG_FILE"
  sing-box check -c "$CONFIG_FILE" 2>&1 | sed 's/^/  /'
  return 1
}

openrc_service_exists() {
  local service="$1"
  [ -e "/etc/init.d/$service" ] || rc-service -e "$service" >/dev/null 2>&1
}

openrc_service_enabled() {
  local service="$1" runlevel="${2:-default}"
  rc-update show "$runlevel" 2>/dev/null | awk -v svc="$service" '$1 == svc {found=1} END {exit !found}'
}

openrc_enable_service() {
  local service="$1" runlevel="${2:-default}"
  openrc_service_enabled "$service" "$runlevel" && return 0
  rc-update add "$service" "$runlevel"
}

openrc_disable_service() {
  local service="$1" runlevel="${2:-default}"
  openrc_service_enabled "$service" "$runlevel" || return 0
  rc-update del "$service" "$runlevel"
}

openrc_service_running() {
  local service="$1"
  rc-service "$service" status >/dev/null 2>&1
}

openrc_start_service() {
  local service="$1"
  openrc_service_running "$service" && return 0
  rc-service "$service" start
}

openrc_stop_service() {
  local service="$1"
  openrc_service_running "$service" || return 0
  rc-service "$service" stop
}

# HUP 会在原进程中重建实例；这里明确重启并验证新的进程，兼顾升级与计费代次。
singbox_process_token() {
  local pid stat boot
  case "$INIT_SYSTEM" in
    systemd) pid="$(systemctl show sing-box -p MainPID --value 2>/dev/null)" || return 1 ;;
    openrc) pid="$(cat /run/sing-box.pid 2>/dev/null)" || return 1 ;;
    *) return 1 ;;
  esac
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
  # comm 字段可以包含空格及括号；删到最后一个右括号后再取 starttime。
  stat="${stat##*) }"
  stat="$(printf '%s\n' "$stat" | awk '{print $20}')"
  [[ "$stat" =~ ^[0-9]+$ ]] || return 1
  boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || return 1
  printf '%s:%s:%s\n' "$boot" "$pid" "$stat"
}

wait_singbox_ready() {
  local old_token="${1:-}" token="" last_token="" stable=0 attempt api_enabled
  api_enabled="$(jq -r '.experimental.v2ray_api.stats.enabled // false' "$CONFIG_FILE")" || return 1
  for ((attempt=0; attempt<20; attempt++)); do
    token="$(singbox_process_token 2>/dev/null)" || token=""
    if singbox_service_active && [ -n "$token" ] && [ "$token" != "$old_token" ]; then
      if [ "$api_enabled" != true ] || query_v2ray_api_uptime >/dev/null 2>&1; then
        if [ "$token" = "$last_token" ]; then stable=$((stable + 1)); else stable=1; fi
        last_token="$token"
        [ "$stable" -ge 3 ] && return 0
      else
        stable=0
      fi
    else
      stable=0
    fi
    sleep 1
  done
  err "sing-box 未在期限内稳定启动或统计 API 不可用。"
  return 1
}

reload_or_restart_singbox_safe() {
  check_config_or_print || return 1
  local old_token quiet="${_RESTART_SINGBOX_QUIET_OK:-0}"
  old_token="$(singbox_process_token 2>/dev/null)" || old_token=""
  case "$INIT_SYSTEM" in
    systemd) systemctl restart sing-box >/dev/null 2>&1 || return 1 ;;
    openrc) rc-service sing-box restart >/dev/null 2>&1 || return 1 ;;
    *) err "未识别的 init 系统，无法重启 sing-box。"; return 1 ;;
  esac
  wait_singbox_ready "$old_token" || return 1
  [ "$quiet" = "1" ] || ok "sing-box 已重启并通过运行检查。"
  return 0
}

enable_now_singbox_safe() {
  local quiet="${_SINGBOX_ENABLE_QUIET_OK:-0}"
  if ! check_config_or_print; then
    err "已阻止启动/自启：请先修复配置。"
    return 1
  fi
  case "$INIT_SYSTEM" in
    systemd)
      systemctl enable sing-box >/dev/null 2>&1 || return 1
      systemctl start sing-box >/dev/null 2>&1 || return 1
      sleep 1
      systemctl is-active --quiet sing-box 2>/dev/null || return 1
      ;;
    openrc)
      openrc_enable_service sing-box default >/dev/null 2>&1 || return 1
      openrc_start_service sing-box >/dev/null 2>&1 || return 1
      sleep 1
      openrc_service_running sing-box || return 1
      ;;
    *)
      err "未识别的 init 系统，无法启动 sing-box。"
      return 1
      ;;
  esac
  [ "$quiet" = "1" ] || ok "sing-box 已启用自启并启动。"
}

with_manager_lock() {
  local _lock_fd _rc=0

  # 并发保护：通过 _CONFIG_LOCK_HELD 哨兵防止重入死锁
  if [ "${_CONFIG_LOCK_HELD:-0}" = "1" ]; then
    if "$@"; then return 0; else return $?; fi
  fi

  if ! has_cmd flock; then
    err "缺少 flock，已阻止无锁写入；请先安装 util-linux（Alpine: flock）。"
    return 1
  fi

  mkdir -p "$(dirname "$SB_LOCK_FILE")" 2>/dev/null || true

  # 注意：exec 行的尾部重定向是永久作用于当前 shell 的，不能写成
  # `exec {_lock_fd}>"$SB_LOCK_FILE" 2>/dev/null`（会把整个 shell 的
  # stderr 永久关闭到 /dev/null，后续 err/warn/read -p 提示全丢失）。
  # 必须用命令组 { ... } 2>/dev/null，把重定向锚定在组作用域内。
  if { exec {_lock_fd}>"$SB_LOCK_FILE"; } 2>/dev/null; then
    if flock "$_lock_fd"; then
      _CONFIG_LOCK_HELD=1
      if "$@"; then _rc=0; else _rc=$?; fi
      _CONFIG_LOCK_HELD=0
      { exec {_lock_fd}>&-; } 2>/dev/null || true
    else
      { exec {_lock_fd}>&-; } 2>/dev/null || true
      err "获取管理锁失败，未执行写入。"
      _rc=1
    fi
  else
    err "无法创建管理锁：$SB_LOCK_FILE，未执行写入。"
    _rc=1
  fi
  return $_rc
}

config_apply() {
  with_manager_lock _config_apply_body "$@"
}

config_apply_no_usage_sync() {
  _CONFIG_SKIP_USAGE_SYNC=1 config_apply "$@"
}

# 配套提交 config + meta：先 config_apply 后 meta_save，meta_save 失败时回滚 config。
# 用法：config_and_meta_apply <config_json> <meta_json>
# 环境变量 _CONFIG_APPLY_QUIET_OK / _CONFIG_SKIP_USAGE_SYNC 透传给内部 config_apply。
# 整个流程在同一把 with_manager_lock 内执行，避免并发会话在 config 已写、meta 未写的间隙插入修改。
config_and_meta_apply() {
  with_manager_lock _config_and_meta_apply_body "$@"
}

_config_and_meta_apply_body() {
  local config_json="$1" meta_json="$2"
  local old_config
  old_config="$(config_load 2>/dev/null)" || old_config='{}'
  # _config_apply_body 直接调用（持锁状态下 sentinel 会让 config_apply wrapper 走 fast path，
  # 但直接调 body 更清晰，省一次条件判断）
  _config_apply_body "$config_json" || return 1
  if ! meta_save "$meta_json"; then
    err "元数据保存失败，正在回滚配置..."
    if ! _CONFIG_APPLY_QUIET_OK=1 _CONFIG_SKIP_USAGE_SYNC=1 _config_apply_body "$old_config"; then
      err "回滚也失败，sing-box 可能运行在新配置上但 meta 是旧的。请手动检查 $CONFIG_FILE 和 $META_FILE"
    fi
    return 1
  fi
}

_config_apply_body() {
  local json="$1"
  local normalized
  normalized="$(config_normalize "$json")"

  if ! echo "$normalized" | jq -e 'type=="object"' >/dev/null 2>&1; then
    err "内部错误：即将写入的配置不是 JSON object。"
    return 1
  fi

  if ! echo "$normalized" | jq -e '
    (.route.final // "") as $final
    | ($final == "" or ([.outbounds[]? | (.tag // "")] | index($final) != null))
  ' >/dev/null 2>&1; then
    err "配置校验失败：route.final 指向的 outbound 不存在。"
    return 1
  fi

  if [ "${_CONFIG_FORCE_RESTART:-0}" != "1" ] && [ -s "$CONFIG_FILE" ] && singbox_service_active; then
    if [ "$(printf '%s' "$normalized" | jq -Sc .)" = "$(jq -Sc . "$CONFIG_FILE")" ]; then
      return 0
    fi
  fi
  if [ "${_CONFIG_SKIP_USAGE_SYNC:-0}" != "1" ]; then
    sync_user_usage_counters || return 1
  fi

  local tmp_file
  tmp_file="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")" || {
    err "创建临时配置文件失败。"
    return 1
  }

  echo "$normalized" | jq . > "$tmp_file" || {
    err "JSON 格式化失败，未写入配置。"
    rm -f "$tmp_file" >/dev/null 2>&1 || true
    return 1
  }

  if ! has_cmd sing-box; then
    err "未找到 sing-box，无法校验配置。"
    rm -f "$tmp_file" >/dev/null 2>&1 || true
    return 1
  fi

  if ! sing-box check -c "$tmp_file" >/dev/null 2>&1; then
    err "sing-box check 校验未通过，未写入配置。"
    sing-box check -c "$tmp_file" 2>&1 | sed 's/^/  /'
    rm -f "$tmp_file" >/dev/null 2>&1 || true
    return 1
  fi

  local ts backup prev_tmp
  ts="$(date +%Y%m%d_%H%M%S)"
  backup="/etc/sing-box/config.json.bak.fail.$ts"
  prev_tmp="$(mktemp "${CONFIG_FILE}.prev.XXXXXX")" || {
    err "创建回滚临时文件失败。"
    rm -f "$tmp_file" >/dev/null 2>&1 || true
    return 1
  }
  chmod 600 "$prev_tmp" 2>/dev/null || true

  if [ -f "$CONFIG_FILE" ]; then
    if ! cp -a "$CONFIG_FILE" "$prev_tmp"; then
      err "无法备份旧配置：$CONFIG_FILE → $prev_tmp"
      rm -f "$tmp_file" "$prev_tmp" >/dev/null 2>&1 || true
      return 1
    fi
  else
    if ! : > "$prev_tmp"; then
      err "无法初始化回滚备份文件：$prev_tmp"
      rm -f "$tmp_file" "$prev_tmp" >/dev/null 2>&1 || true
      return 1
    fi
  fi

  mv -f "$tmp_file" "$CONFIG_FILE" || {
    err "配置文件写入失败：$CONFIG_FILE"
    rm -f "$tmp_file" "$prev_tmp" >/dev/null 2>&1 || true
    return 1
  }
  chmod 600 "$CONFIG_FILE" 2>/dev/null || true

  if _RESTART_SINGBOX_QUIET_OK=1 reload_or_restart_singbox_safe; then
    case "$INIT_SYSTEM" in
      systemd) systemctl enable sing-box >/dev/null 2>&1 || true ;;
      openrc)  openrc_enable_service sing-box default >/dev/null 2>&1 || true ;;
    esac
    rm -f "$prev_tmp" >/dev/null 2>&1 || true
    # 自动清理旧备份，保留最近 1 个
    ls -1t /etc/sing-box/config.json.bak.fail.* 2>/dev/null | tail -n +2 | xargs rm -f -- 2>/dev/null || true
    [ "${_CONFIG_APPLY_QUIET_OK:-0}" = "1" ] || ok "配置已应用。"
    return 0
  fi

  err "热载/重启失败：正在回滚。"
  if [ -f "$prev_tmp" ] && [ -s "$prev_tmp" ]; then
    cp -a "$prev_tmp" "$backup" || warn "失败现场备份未能保存到 $backup"
    if ! cp -a "$prev_tmp" "$CONFIG_FILE"; then
      err "回滚 cp 失败，sing-box 可能仍运行在坏配置上。手动恢复：cp $prev_tmp $CONFIG_FILE"
      return 1
    fi
    warn "已生成失败备份：$backup"
  else
    cp -a "$CONFIG_FILE" "$backup" 2>/dev/null || true
    warn "无旧配置可回滚，已保存失败现场：$backup"
  fi
  rm -f "$prev_tmp" >/dev/null 2>&1 || true
  if ! reload_or_restart_singbox_safe; then
    err "回滚后热载/重启仍失败，sing-box 当前可能处于异常状态。"
    warn "手动恢复命令："
    case "$INIT_SYSTEM" in
      systemd) warn "  systemctl start sing-box" ;;
      openrc)  warn "  rc-service sing-box start" ;;
    esac
    warn "如需恢复到失败前的配置，请检查：$backup"
  fi
  return 1
}

config_reset() {
  config_apply "$(config_min_template)"
}

init_manager_env() {
  # 幂等哨兵：首次执行后标记，避免菜单循环重复跑 require_root/has_cmd/磁盘读
  [ "${_MANAGER_ENV_READY:-0}" = "1" ] && return 0
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "请使用 root 运行此脚本。"
    return 1
  fi
  has_cmd jq || { err "未找到 jq，请先安装/更新 sing-box（会自动装依赖）。"; return 1; }
  has_cmd curl || { err "未找到 curl，请先安装/更新 sing-box（会自动装依赖）。"; return 1; }
  has_cmd openssl || { err "未找到 openssl，请先安装/更新 sing-box（会自动装依赖）。"; return 1; }
  has_cmd sing-box || { err "未找到 sing-box，请先安装。"; return 1; }
  local core_version
  core_version="$(sing-box version | awk '/^sing-box version / {print $3; exit}')"
  version_ge "$core_version" "1.14.0" || { err "此脚本需要 sing-box 1.14.0 或更新版本，请先在安装/更新菜单升级内核。"; return 1; }
  [ "$INIT_SYSTEM" = "unknown" ] && { err "未识别的 init 系统（需要 systemd 或 OpenRC）。"; return 1; }
  config_ensure_exists
  ensure_manager_file_permissions
  _MANAGER_ENV_READY=1
}

# >>>>>>>>> END MODULE: 10_config.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 20_protocol.sh <<<<<<<<<<<
# ============================================================
# 模块: 20_protocol.sh
# 职责: 协议构建器、TLS 域名选择、证书生成
# 依赖: 00_base.sh (协议注册表), 01_utils.sh
# ============================================================

# ---------- 协议 entry key 映射（基于注册表，取代 6 处 case） ----------

entry_key_prefix_by_type() {
  local proto="$1"
  local prefix="${PROTO_PREFIX[$proto]:-}"
  if [ -z "$prefix" ]; then return 1; fi
  echo "$prefix"
}

entry_key_from_parts() {
  local proto="$1" port="$2"
  local prefix
  prefix="$(entry_key_prefix_by_type "$proto")" || return 1
  echo "${prefix}-${port}"
}

entry_key_to_protocol_label() {
  local key="$1"
  # 从 entry_key 提取 prefix 并查注册表
  local prefix
  for prefix in "${!PREFIX_TO_PROTO[@]}"; do
    if [[ "$key" == "${prefix}-"* ]]; then
      echo "${PREFIX_TO_PROTO[$prefix]}"
      return 0
    fi
  done
  echo "unknown"
}

entry_key_to_port() {
  echo "$1" | awk -F- '{print $NF}'
}

# ---------- TLS 证书 ----------

ensure_self_signed_cert() {
  local cn="$1" crt_path="$2" key_path="$3"
  mkdir -p "$(dirname "$crt_path")" || return 1
  openssl req -x509 -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$key_path" -out "$crt_path" -days 36500 -nodes -subj "/CN=${cn}" >/dev/null 2>&1 || return 1
  [ -s "$crt_path" ] && [ -s "$key_path" ]
}

generate_reality_keypair_auto() {
  local out priv pub
  out="$(sing-box generate reality-keypair 2>/dev/null || true)"
  priv="$(printf '%s\n' "$out" | awk -F': *' '/PrivateKey/ {print $2; exit}')"
  pub="$(printf '%s\n' "$out" | awk -F': *' '/PublicKey/ {print $2; exit}')"
  if [ -n "$priv" ] && [ -n "$pub" ]; then
    printf '%s\t%s\n' "$priv" "$pub"
    return 0
  fi
  return 1
}

# ---------- TLS 域名选择 ----------

get_tls_domain_candidates() {
  cat <<'EOF_TLS'
assets.adobedtm.com
lpcdn.lpsnmedia.net
s.go-mpulse.net
d0.m.awsstatic.com
a0.awsstatic.com
devblogs.microsoft.com
ds-aksb-a.akamaihd.net
tag.demandbase.com
electronics.sony.com
tag-logger.demandbase.com
d3agakyjgjv5i8.cloudfront.net
ms-python.gallerycdn.vsassets.io
img-prod-cms-rt-microsoft-com.akamaized.net
cdn.bizible.com
store-images.s-microsoft.com
catalog.gamepass.com
www.nvidia.com
mscom.demdex.net
drivers.amd.com
azure.microsoft.com
downloadmirror.intel.com
prod.us-east-1.ui.gcr-chat.marketing.aws.dev
r.bing.com
www.intel.com
ms-vscode.gallerycdn.vsassets.io
rum.hlx.page
www.tesla.com
ts2.tc.mm.bing.net
res-1.cdn.office.net
cdn-dynmedia-1.microsoft.com
EOF_TLS
}

benchmark_tls_domain_ms() {
  local domain="$1" t1 t2
  t1="$(now_ms)"
  run_with_timeout 1 openssl s_client -connect "${domain}:443" -servername "$domain" </dev/null >/dev/null 2>&1 || return 1
  t2="$(now_ms)"
  if [[ "$t1" =~ ^[0-9]+$ ]] && [[ "$t2" =~ ^[0-9]+$ ]] && [ "$t2" -ge "$t1" ]; then
    echo $((t2 - t1))
  else
    echo 999
  fi
}

auto_pick_tls_domain() {
  local best_domain="" best_ms=999999 ms domain
  local -a candidates=()
  mapfile -t candidates < <(get_tls_domain_candidates)
  # 随机抽取 10 个域名测速，避免全量串行等待过久
  local total=${#candidates[@]}
  if [ "$total" -gt 10 ]; then
    local -a sampled=()
    local -a indices=()
    while [ ${#sampled[@]} -lt 10 ]; do
      local r=$((RANDOM % total))
      local dup=0 idx
      for idx in "${indices[@]}"; do
        [ "$idx" -eq "$r" ] && { dup=1; break; }
      done
      [ $dup -eq 0 ] && { sampled+=("${candidates[$r]}"); indices+=("$r"); }
    done
    candidates=("${sampled[@]}")
  fi
  for domain in "${candidates[@]}"; do
    [ -n "$domain" ] || continue
    ms="$(benchmark_tls_domain_ms "$domain" 2>/dev/null || true)"
    if [ -n "$ms" ] && [[ "$ms" =~ ^[0-9]+$ ]] && [ "$ms" -lt "$best_ms" ]; then
      best_ms="$ms"
      best_domain="$domain"
    fi
  done
  [ -n "$best_domain" ] || return 1
  printf '%s\t%s\n' "$best_domain" "$best_ms"
}

choose_tls_domain() {
  local proto_label="$1" choice manual picked picked_ms
  ui_echo "1. 手动输入"
  ui_echo "2. 自动测速选择推荐域名"
  read -r -p "请选择域名填写方式（回车默认2. 自动测速选择推荐域名）: " choice
  case "${choice:-2}" in
    1)
      read -r -p "请输入${proto_label}域名（回车返回）: " manual
      if [ -z "${manual:-}" ]; then
        warn "输入无效，已返回上一级。"
        pause >&2
        return 1
      fi
      param_echo "SNI" "$manual"
      echo "$manual"
      ;;
    *)
      picked="$(auto_pick_tls_domain 2>/dev/null || true)"
      if [ -n "$picked" ]; then
        picked_ms="${picked#*$'\t'}"
        picked="${picked%%$'\t'*}"
        param_echo "SNI" "${picked} (${picked_ms} ms)"
        echo "$picked"
      else
        warn "自动测速失败，已返回上一级。"
        pause >&2
        return 1
      fi
      ;;
  esac
}

# ---------- SS 密码规范化 ----------

ss2022_normalize_password_pair() {
  local raw="$1"
  local sp up
  if [ -z "$raw" ]; then
    sp="$(random_b64_password 16)"
    up="$(random_b64_password 16)"
    echo "${sp}:${up}"
    return 0
  fi
  sp="${raw%%:*}"
  up=""
  [[ "$raw" == *:* ]] && up="${raw#*:}"
  if ! echo "$sp" | base64 -d >/dev/null 2>&1; then sp="$(openssl rand -base64 16)"; fi
  if [ -n "$up" ] && ! echo "$up" | base64 -d >/dev/null 2>&1; then up="$(openssl rand -base64 16)"; fi
  if [ -n "$up" ]; then echo "${sp}:${up}"; else echo "$sp"; fi
}

ss2022_password_part_valid() {
  local part="$1"
  local bytes
  [ -n "$part" ] || return 1
  bytes="$(printf '%s' "$part" | base64 -d 2>/dev/null | wc -c | tr -d ' ')" || return 1
  [ "$bytes" = "16" ]
}

ss2022_prepare_password_pair() {
  local raw="${1:-}" sp up
  if [ -z "$raw" ]; then
    sp="$(random_b64_password 16)"
    up="$(random_b64_password 16)"
    [ -n "$sp" ] && [ -n "$up" ] || return 1
    echo "${sp}:${up}"
    return 0
  fi

  sp="${raw%%:*}"
  if [[ "$raw" == *:* ]]; then
    up="${raw#*:}"
  else
    up="$sp"
  fi
  ss2022_password_part_valid "$sp" || return 1
  ss2022_password_part_valid "$up" || return 1
  echo "${sp}:${up}"
}

# ====================================================
# 协议 Inbound 构建器
# 每个协议一个函数，结构统一，互不依赖
# ====================================================

build_vless_reality_inbound() {
  local port="$1" sni="$2" priv="$3" sid="$4"
  local entry_key uuid sid_json
  entry_key="$(entry_key_from_parts vless-reality "$port")"
  uuid="$(sing-box generate uuid)"
  if [ -n "$sid" ]; then
    sid_json="[\"$sid\"]"
  else
    sid_json='[]'
  fi
  jq -n --arg tag "$entry_key" --arg uuid "$uuid" --arg sni "$sni" --arg priv "$priv" --argjson sid "$sid_json" --argjson port "$port" '
    {
      "type":"vless",
      "tag":$tag,
      "listen":"::",
      "listen_port":$port,
      "users":[{"name":$tag,"uuid":$uuid,"flow":"xtls-rprx-vision"}],
      "tls":{
        "enabled":true,
        "server_name":$sni,
        "reality":{
          "enabled":true,
          "handshake":{"server":$sni,"server_port":443},
          "private_key":$priv,
          "short_id":$sid
        }
      }
    }
  '
}

build_anytls_inbound() {
  local port="$1" sni="$2" pass="${3:-}"
  local entry_key crt key
  entry_key="$(entry_key_from_parts anytls "$port")"
  [ -n "$pass" ] || pass="$(random_b64_password 16)"
  crt="/etc/sing-box/anytls-${port}.crt"
  key="/etc/sing-box/anytls-${port}.key"
  ensure_self_signed_cert "$sni" "$crt" "$key" || return 1
  jq -n --arg tag "$entry_key" --arg pass "$pass" --arg sni "$sni" --arg crt "$crt" --arg key "$key" --argjson port "$port" '
    {
      "type":"anytls",
      "tag":$tag,
      "listen":"::",
      "listen_port":$port,
      "users":[{"name":$tag,"password":$pass}],
      "padding_scheme":[],
      "tls":{
        "enabled":true,
        "server_name":$sni,
        "certificate_path":$crt,
        "key_path":$key,
        "alpn":["h2","http/1.1"]
      }
    }
  '
}

build_ss_inbound() {
  local port="$1" raw_password="${2:-}"
  local entry_key server_p user_p normalized_pw
  entry_key="$(entry_key_from_parts shadowsocks "$port")"
  normalized_pw="$(ss2022_prepare_password_pair "$raw_password")" || return 1
  server_p="${normalized_pw%%:*}"
  user_p="${normalized_pw#*:}"
  jq -n --arg tag "$entry_key" --arg sp "$server_p" --arg up "$user_p" --argjson port "$port" '
    {
      "type":"shadowsocks",
      "tag":$tag,
      "listen":"::",
      "listen_port":$port,
      "method":"2022-blake3-aes-128-gcm",
      "password":$sp,
      "users":[{"name":$tag,"password":$up}]
    }
  '
}

build_trojan_inbound() {
  local port="$1" sni="$2" pass="${3:-}"
  local entry_key crt key
  entry_key="$(entry_key_from_parts trojan "$port")"
  [ -n "$pass" ] || pass="$(random_b64_password 16)"
  crt="/etc/sing-box/trojan-${port}.crt"
  key="/etc/sing-box/trojan-${port}.key"
  ensure_self_signed_cert "$sni" "$crt" "$key" || return 1
  jq -n --arg tag "$entry_key" --arg pass "$pass" --arg sni "$sni" --arg crt "$crt" --arg key "$key" --argjson port "$port" '
    {
      "type":"trojan",
      "tag":$tag,
      "listen":"::",
      "listen_port":$port,
      "users":[{"name":$tag,"password":$pass}],
      "tls":{
        "enabled":true,
        "server_name":$sni,
        "certificate_path":$crt,
        "key_path":$key
      }
    }
  '
}

build_vmess_ws_inbound() {
  local port="$1" listen="$2" path="$3"
  local entry_key uuid
  entry_key="$(entry_key_from_parts vmess-ws "$port")"
  uuid="$(sing-box generate uuid)"
  jq -n --arg tag "$entry_key" --arg uuid "$uuid" --arg listen "$listen" --arg path "$path" --argjson port "$port" '
    {
      "type":"vmess",
      "tag":$tag,
      "listen":$listen,
      "listen_port":$port,
      "users":[{"name":$tag,"uuid":$uuid,"alterId":0}],
      "transport":{"type":"ws","path":$path,"max_early_data":2048,"early_data_header_name":"Sec-WebSocket-Protocol"}
    }
  '
}

build_vless_ws_inbound() {
  local port="$1" listen="$2" path="$3"
  local entry_key uuid
  entry_key="$(entry_key_from_parts vless-ws "$port")"
  uuid="$(sing-box generate uuid)"
  jq -n --arg tag "$entry_key" --arg uuid "$uuid" --arg listen "$listen" --arg path "$path" --argjson port "$port" '
    {
      "type":"vless",
      "tag":$tag,
      "listen":$listen,
      "listen_port":$port,
      "users":[{"name":$tag,"uuid":$uuid}],
      "transport":{"type":"ws","path":$path,"max_early_data":2048,"early_data_header_name":"Sec-WebSocket-Protocol"}
    }
  '
}

build_tuic_inbound() {
  local port="$1" sni="$2" pass="${3:-}"
  local entry_key uuid crt key
  entry_key="$(entry_key_from_parts tuic "$port")"
  uuid="$(sing-box generate uuid)"
  [ -n "$pass" ] || pass="$(random_b64_password 12)"
  crt="/etc/sing-box/tuic-${port}.crt"
  key="/etc/sing-box/tuic-${port}.key"
  ensure_self_signed_cert "$sni" "$crt" "$key" || return 1
  jq -n --arg tag "$entry_key" --arg uuid "$uuid" --arg pass "$pass" --arg sni "$sni" --arg crt "$crt" --arg key "$key" --argjson port "$port" '
    {
      "type":"tuic",
      "tag":$tag,
      "listen":"::",
      "listen_port":$port,
      "users":[{"name":$tag,"uuid":$uuid,"password":$pass}],
      "tls":{"enabled":true,"server_name":$sni,"alpn":["h3"],"certificate_path":$crt,"key_path":$key},
      "congestion_control":"bbr"
    }
  '
}

build_socks_inbound() {
  local port="$1" password="${2:-}"
  local entry_key
  entry_key="$(entry_key_from_parts socks "$port")"
  [ -n "$password" ] || password="$(random_b64_password 12)"
  jq -n --arg tag "$entry_key" --arg password "$password" --argjson port "$port" '
    {
      "type":"socks",
      "tag":$tag,
      "listen":"::",
      "listen_port":$port,
      "users":[{"username":$tag,"password":$password}]
    }
  '
}

# ---------- 证书清理 ----------

cleanup_inbound_generated_cert_files() {
  local json="$1" entry_key="$2"
  local crt key
  crt="$(echo "$json" | jq -r --arg ek "$entry_key" '.inbounds[]? | select((.tag // "") == $ek) | .tls.certificate_path // empty' | head -n1)"
  key="$(echo "$json" | jq -r --arg ek "$entry_key" '.inbounds[]? | select((.tag // "") == $ek) | .tls.key_path // empty' | head -n1)"
  if [ -n "$crt" ] && [[ "$crt" == /etc/sing-box/* ]]; then
    rm -f "$crt" >/dev/null 2>&1 || true
  fi
  if [ -n "$key" ] && [[ "$key" == /etc/sing-box/* ]]; then
    rm -f "$key" >/dev/null 2>&1 || true
  fi
}

# ---------- 用户对象构建（按协议类型分派） ----------

build_user_object_from_inbound() {
  local inbound="$1" full_name="$2"
  local inbound_type
  inbound_type="$(echo "$inbound" | jq -r '.type')"
  case "$inbound_type" in
    vless)
      if echo "$inbound" | jq -e '.tls.reality.enabled == true' >/dev/null 2>&1; then
        jq -n --arg name "$full_name" --arg uuid "$(sing-box generate uuid)" '{name:$name,uuid:$uuid,flow:"xtls-rprx-vision"}'
      else
        jq -n --arg name "$full_name" --arg uuid "$(sing-box generate uuid)" '{name:$name,uuid:$uuid}'
      fi
      ;;
    vmess)
      jq -n --arg name "$full_name" --arg uuid "$(sing-box generate uuid)" '{name:$name,uuid:$uuid,alterId:0}'
      ;;
    shadowsocks|anytls|trojan)
      jq -n --arg name "$full_name" --arg pass "$(random_b64_password 16)" '{name:$name,password:$pass}'
      ;;
    tuic)
      jq -n --arg name "$full_name" --arg uuid "$(sing-box generate uuid)" --arg pass "$(random_b64_password 12)" '{name:$name,uuid:$uuid,password:$pass}'
      ;;
    socks)
      jq -n --arg username "$full_name" --arg pass "$(random_b64_password 12)" '{username:$username,password:$pass}'
      ;;
    *)
      return 1
      ;;
  esac
}

find_user_obj_in_inbound() {
  local inbound="$1" full_name="$2"
  echo "$inbound" | jq -c --arg n "$full_name" '(.users // [])[]? | select(((.name // .username // "") == $n))' | head -n1
}

# >>>>>>>>> END MODULE: 20_protocol.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 30_route.sh <<<<<<<<<<<
# ============================================================
# 模块: 30_route.sh
# 职责: 路由重建、协议清单、端口冲突检测、inbound 删除
# 依赖: 00_base.sh (JQ_SHARED), 10_config.sh, 20_protocol.sh
# ============================================================

# ---------- 协议清单（使用共享 jq 模板） ----------

protocol_entry_inventory() {
  local json="$1"
  echo "$json" | jq -r "${JQ_DETECT_PROTOCOL}"'
    .inbounds[]?
    | (detect_protocol) as $proto
    | select($proto != "")
    | [(.tag // ""), $proto, ((.listen_port // 0) | tostring)]
    | join("\u0001")
  '
}

protocol_entry_inventory_ext() {
  local json="$1"
  echo "$json" | jq -r "${JQ_DETECT_PROTOCOL}"'
    .inbounds
    | to_entries[]?
    | .key as $idx
    | .value as $ib
    | ($ib | detect_protocol) as $proto
    | select($proto != "")
    | [$idx, ($ib.tag // ""), $proto, (($ib.listen_port // 0) | tostring)]
    | join("\u0001")
  '
}

inbound_protocol_name() {
  local inbound="$1"
  echo "$inbound" | jq -r "${JQ_DETECT_PROTOCOL}"'detect_protocol'
}

# ---------- 端口冲突检测（使用注册表） ----------

protocol_transport_layer() {
  local proto="$1"
  echo "${PROTO_TRANSPORT[$proto]:-tcp}"
}

config_port_in_use_by_layer() {
  local json="$1" port="$2" layer="$3" exclude_tag="${4:-}"
  echo "$json" | jq -e --arg p "$port" --arg ex "$exclude_tag" --arg layer "$layer" '
    .inbounds[]?
    | select((.listen_port? // empty | tostring) == $p)
    | select(($ex == "") or ((.tag // "") != $ex))
    | (if .type == "tuic" or .type == "hysteria2" or .type == "hysteria" then ["udp"]
       elif .type == "shadowsocks" then
         if (.network // "") == "" then ["tcp","udp"]
         elif (.network|type) == "array" then .network else (.network|split(",")) end
       else ["tcp"] end) as $layers
    | select(($layers | index($layer)) != null)
  ' >/dev/null 2>&1
}

port_conflict_for_protocol() {
  local json="$1" proto="$2" port="$3" exclude_tag="${4:-}"
  local layer
  layer="$(protocol_transport_layer "$proto")"
  local transport
  for transport in $layer; do
    if config_port_in_use_by_layer "$json" "$port" "$transport" "$exclude_tag"; then return 0; fi
  done
  return 1
}

find_inbound_by_entry_key() {
  local json="$1" entry_key="$2"
  echo "$json" | jq -c --arg ek "$entry_key" '.inbounds[]? | select(.tag==$ek)' | head -n1
}

# ---------- 辅助：列出所有节点 key ----------

list_all_node_keys() {
  local json="$1"
  echo "$json" | jq -r '.inbounds[]?.tag // empty' \
    | awk 'NF' | LC_ALL=C sort -u | sort_node_keys_by_protocol
}

# ====================================================
# 路由重建（核心函数，使用共享 jq 模板去重）
# ====================================================

route_rebuild(){
  local json="$1"
  local normalized core_auth_users_json preserved_rules_json

  normalized="$(config_normalize "$json")" || return 1

  core_auth_users_json="$(echo "$normalized" | jq -c "${JQ_NODE_PART}"'
    [.inbounds[]? | .tag as $entry | .users[]? | (.name // .username // "")
      | select(. != "" and node_part(.) == $entry)] | unique
  ')" || return 1

  preserved_rules_json="$(
    echo "$normalized" | jq -c '
      [ .route.rules[]? | select(.auth_user? == null and .inbound? == null and . != {action:"reject"}) ]
    '
  )" || return 1

  echo "$normalized" | jq \
    --argjson core_auth "$core_auth_users_json" \
    --argjson kept "$preserved_rules_json" '
    .route.rules = (
      ($kept // [])
      + (if ($core_auth | length) > 0 then [{auth_user:($core_auth | unique | sort),outbound:"direct"}] else [] end)
    )
    # 保留规则的完整条件和顺序；生成的用户列表已在上面 unique。
    # 不可用 outbound/auth_user/rule_set 三字段对用户规则做全局去重。
    | . as $root
    | .outbounds |= map(
        (.tag // "") as $tag
        | select(
            (
              ($tag != "direct")
              and (($tag | startswith("out-")) or ($tag | startswith("to-")))
              and (([$root.route.rules[]? | .outbound // empty] | index($tag)) == null)
            ) | not
          )
      )
    | if (.route.rule_set? == null) then .
      else
        .route.rule_set = (
            ((.route.rule_set // []) | if type == "array" then . else [.] end)
            | map(select((((.tag // "") | startswith("warp-geosite-")) or ((.tag // "") | startswith("relay-geosite-"))) | not))
          )
      end
    | .route.rules += [{action:"reject"}]
    | del(.route.final)
  ' || return 1
}

# ====================================================
# 删除操作（使用共享 jq 模板去重）
# ====================================================

remove_inbound_by_entry_key(){
  local json="$1" entry_key="$2"
  local inbound_users_json related_outbounds_json updated_json

  inbound_users_json="$(
    echo "$json" | jq -c --arg ek "$entry_key" '
      [
        .inbounds[]?
        | select(.tag == $ek)
        | (.users // [])[]?
        | (.name // .username // empty)
        | select(. != "")
      ]
    '
  )" || return 1

  related_outbounds_json="$(
    echo "$json" | jq -c "${JQ_AUTH_USERS}"'
      (
        [
          .route.rules[]?
          | select((auth_users_array | any(. as $u | (($users | index($u)) != null))))
          | .outbound // empty
          | select(. != "" and . != "direct")
        ]
        + [
            ($users // [])[] as $u
            | (["out-" + $u] + (if ($u | contains("-to-")) then ["out-to-" + (($u | capture(".*-to-(?<land>.+)$").land)), "to-" + (($u | capture(".*-to-(?<land>.+)$").land))] else [] end))[] as $cand
            | .outbounds[]?
            | .tag // empty
            | select(. == $cand)
          ]
      ) | unique
    ' --argjson users "$inbound_users_json"
  )" || return 1

  updated_json="$(
    echo "$json" | jq "${JQ_AUTH_USERS}"'
      .inbounds |= map(select((.tag // "") != $ek))
      | .route.rules |= map(
          select(
            (
              .auth_user? as $au
              | if $au == null then true
                else
                  (
                    if ($au | type) == "array" then $au else [ $au ] end
                  ) as $arr
                  | any($arr[]; . as $u | (($users | index($u)) != null)) | not
                end
            )
          )
        )
    ' --arg ek "$entry_key" --argjson users "$inbound_users_json"
  )" || return 1

  echo "$updated_json" | jq --argjson outs "$related_outbounds_json" '
    . as $root
    | .outbounds |= map(
        (.tag // "") as $tag
        | select(
            (
              (($outs | index($tag)) != null)
              and (([$root.route.rules[]? | .outbound // empty] | index($tag)) == null)
            ) | not
          )
      )
  ' || return 1
}

# >>>>>>>>> END MODULE: 30_route.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 50_v2ray_api.sh <<<<<<<<<<<
# ============================================================
# 模块: 50_v2ray_api.sh
# 职责: gRPC 流量统计查询、meta 存储、grpcurl 安装
# 依赖: 00_base.sh, 01_utils.sh
# ============================================================

# ---------- Proto 文件管理 ----------

ensure_v2ray_api_proto_files() {
  mkdir -p /etc/sing-box
  cat > "$V2RAY_PROTO_V2RAY" <<'EOF_V2V'
syntax = "proto3";
package v2ray.core.app.stats.command;
message GetStatsRequest { string name = 1; bool reset = 2; }
message Stat { string name = 1; int64 value = 2; }
message GetStatsResponse { Stat stat = 1; }
message QueryStatsRequest { string pattern = 1; bool reset = 2; repeated string patterns = 3; bool regexp = 4; }
message QueryStatsResponse { repeated Stat stat = 1; }
message SysStatsRequest {}
message SysStatsResponse {
  uint32 NumGoroutine = 1; uint32 NumGC = 2; uint64 Alloc = 3; uint64 TotalAlloc = 4;
  uint64 Sys = 5; uint64 Mallocs = 6; uint64 Frees = 7; uint64 LiveObjects = 8; uint64 PauseTotalNs = 9; uint32 Uptime = 10;
}
service StatsService {
  rpc GetStats (GetStatsRequest) returns (GetStatsResponse);
  rpc QueryStats (QueryStatsRequest) returns (QueryStatsResponse);
  rpc GetSysStats (SysStatsRequest) returns (SysStatsResponse);
}
EOF_V2V
}

# ---------- grpcurl 管理 ----------

ensure_grpcurl() {
  if [ -x "$GRPCURL_BIN" ]; then
    return 0
  fi
  local asset_pattern tag api api_json tmp_dir download_url
  case "$(uname -m)" in
    x86_64) asset_pattern='linux_x86_64.tar.gz' ;;
    aarch64|arm64) asset_pattern='linux_arm64.tar.gz' ;;
    *)
      warn "当前架构暂不支持自动下载 grpcurl：$(uname -m)"
      return 1
      ;;
  esac
  api="https://api.github.com/repos/fullstorydev/grpcurl/releases/latest"
  api_json="$(curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 "$api" 2>/dev/null || true)"
  [ -n "$api_json" ] || { warn "未获取到 grpcurl 最新版本。"; return 1; }
  tag="$(echo "$api_json" | jq -r '.tag_name // empty' 2>/dev/null)" || true
  [ -n "$tag" ] || { warn "未获取到 grpcurl 最新版本。"; return 1; }
  download_url="$(echo "$api_json" | jq -r --arg p "$asset_pattern" '.assets[]?.browser_download_url | select(contains($p))' 2>/dev/null | head -n1)" || true
  [ -n "$download_url" ] || { warn "未找到 grpcurl 适配当前架构的安装包。"; return 1; }
  tmp_dir="$(make_disk_tmp_dir sb-install)" || { warn "创建临时目录失败。"; return 1; }
  say "下载流量统计组件..."
  if ! download_file "$download_url" "$tmp_dir/grpcurl.tar.gz" 20 3; then
    rm -rf "$tmp_dir"
    warn "下载 grpcurl 失败。"
    return 1
  fi
  tar -xzf "$tmp_dir/grpcurl.tar.gz" -C "$tmp_dir" || { rm -rf "$tmp_dir"; warn "解压 grpcurl 失败。"; return 1; }
  [ -f "$tmp_dir/grpcurl" ] || { rm -rf "$tmp_dir"; warn "grpcurl 安装包中未找到 grpcurl。"; return 1; }
  install -m 755 "$tmp_dir/grpcurl" "$GRPCURL_BIN" || { rm -rf "$tmp_dir"; warn "安装 grpcurl 失败。"; return 1; }
  rm -rf "$tmp_dir"
  return 0
}

ensure_grpcurl_logged() {
  if [ -x "$GRPCURL_BIN" ]; then
    return 0
  fi
  if ensure_grpcurl; then
    return 0
  fi
  warn "grpcurl 安装失败，用户流量读数可能不可用。"
  return 1
}

# ---------- V2Ray API 配置注入 ----------

ensure_v2ray_api_on_json() {
  local json="$1"
  local users_json
  users_json="$(
    echo "$json" | jq -c "${JQ_AUTH_USERS}"'
      [
        .route.rules[]?
        | auth_users_array[]?
        | select(length > 0)
      ] | unique | sort
    '
  )"
  echo "$json" | jq --arg listen "$V2RAY_API_LISTEN" --argjson users "$users_json" '
    .experimental = (.experimental // {})
    | .experimental.v2ray_api = (.experimental.v2ray_api // {})
    | .experimental.v2ray_api.listen = $listen
    | .experimental.v2ray_api.stats = {
        "enabled": true,
        "users": $users
      }
  '
}

# ---------- 流量查询 ----------

v2ray_api_query() {
  local method="$1" payload="$2"
  [ -x "$GRPCURL_BIN" ] || { warn "缺少 grpcurl，统计不可用。"; return 1; }
  [ -s "$V2RAY_PROTO_V2RAY" ] || ensure_v2ray_api_proto_files || return 1
  "$GRPCURL_BIN" -plaintext -connect-timeout 2 -max-time 3 \
    -import-path "$(dirname "$V2RAY_PROTO_V2RAY")" -proto "$(basename "$V2RAY_PROTO_V2RAY")" \
    -d "$payload" "$V2RAY_API_LISTEN" "v2ray.core.app.stats.command.StatsService/$method"
}

query_v2ray_api_stats_json() {
  local out
  out="$(v2ray_api_query QueryStats '{"patterns":["user>>>"],"reset":false,"regexp":false}')" || return 1
  printf '%s' "$out" | jq -ce '(.stat // []) | select(type == "array")'
}

query_v2ray_api_uptime() {
  local out
  out="$(v2ray_api_query GetSysStats '{}')" || return 1
  printf '%s' "$out" | jq -er '(.Uptime // .uptime // 0) | tonumber | select(. >= 0)'
}

query_usage_snapshot() {
  local before after first last stats monotonic
  before="$(singbox_process_token)" || return 1
  first="$(query_v2ray_api_uptime)" || return 1
  stats="$(query_v2ray_api_stats_json)" || return 1
  last="$(query_v2ray_api_uptime)" || return 1
  monotonic="$(awk '{print int($1)}' /proc/uptime)" || return 1
  after="$(singbox_process_token)" || return 1
  [ "$before" = "$after" ] && [ "$last" -ge "$first" ] || return 1
  jq -nc --arg process "$after" --argjson start "$((monotonic - last))" --argjson stats "$stats" \
    '{process:$process, start:$start, stats:$stats}'
}

# 纯变换：按完整 auth_user 保存基线，再聚合业务用户。start 用单调时钟，避免 NTP 校时误判。
account_usage_snapshot() {
  local db="$1" snapshot="$2"
  printf '%s' "$db" | jq --argjson snap "$snapshot" '
    def business($name): if ($name|contains("@")) then ($name|split("@")[1]) else "admin" end;
    def delta($now; $old): if $now >= $old then $now-$old else $now end;
    . as $db
    | (.meta.usage // {}) as $prev
    | (($prev.process // "") != $snap.process or (($prev.start // 0) - $snap.start | fabs) > 2) as $new_epoch
    | (reduce ($snap.stats[]? | select((.name // "")|test("^user>>>.+>>>traffic>>>(uplink|downlink)$"))) as $s
        ({}; ($s.name|capture("^user>>>(?<user>.+)>>>traffic>>>(?<dir>uplink|downlink)$")) as $m
          | .[$m.user][$m.dir] = ($s.value|tonumber))) as $live
    | (reduce ($live|to_entries[]) as $item ({};
        business($item.key) as $u
        | ($item.value.uplink // 0) as $up | ($item.value.downlink // 0) as $down
        | (if $new_epoch then {} else ($prev.counters[$item.key] // {}) end) as $old
        | .[$u].up = ((.[$u].up // 0) + delta($up; ($old.uplink // 0)))
        | .[$u].down = ((.[$u].down // 0) + delta($down; ($old.downlink // 0)))
        | .[$u].live_up = ((.[$u].live_up // 0) + $up)
        | .[$u].live_down = ((.[$u].live_down // 0) + $down))) as $usage
    | .users |= with_entries(
        .key as $u | .value as $v | ($usage[$u] // {}) as $n
        # 首次从旧版迁移：沿用旧聚合基线结算一次，然后保存节点基线。
        | .value.used_up_bytes = (($v.used_up_bytes // 0) +
            (if $prev.process == null then delta(($n.live_up // 0); ($v.last_live_up_bytes // 0)) else ($n.up // 0) end))
        | .value.used_down_bytes = (($v.used_down_bytes // 0) +
            (if $prev.process == null then delta(($n.live_down // 0); ($v.last_live_down_bytes // 0)) else ($n.down // 0) end))
        | .value.last_live_up_bytes = ($n.live_up // 0)
        | .value.last_live_down_bytes = ($n.live_down // 0))
    | .meta.usage = {
        process:$snap.process,
        start:(if $new_epoch then $snap.start else $prev.start end),
        counters:((if $new_epoch then {} else ($prev.counters // {}) end) * $live)
      }
  '
}

build_live_usage_object() {
  local stats_json="$1"
  echo "$stats_json" | jq -c '
    reduce (.[]? | select((.name // "") | test("^user>>>.*>>>traffic>>>(downlink|uplink)$"))) as $s
      ({admin:{up:0,down:0}};
        (($s.name // "") | capture("^user>>>(?<user>.+)>>>traffic>>>(?<dir>downlink|uplink)$")) as $m
        | ($m.user) as $uname
        | ($m.dir) as $dir
        | ($s.value // 0 | tonumber? // 0) as $val
        | (if ($uname | contains("@")) then ($uname | split("@")[1]) else "admin" end) as $biz
        | .[$biz] = (.[$biz] // {up:0,down:0})
        | if $dir == "uplink" then
            .[$biz].up = ((.[$biz].up // 0) + $val)
          else
            .[$biz].down = ((.[$biz].down // 0) + $val)
          end
      )
  '
}

sync_user_usage_counters() {
  with_manager_lock _sync_user_usage_counters_body
}

_sync_user_usage_counters_body() {
  user_db_exists || return 0
  singbox_service_active || return 0
  # 尚未启用统计的首次安装，不读取不存在的 API。
  jq -e '.experimental.v2ray_api.stats.enabled == true' "$CONFIG_FILE" >/dev/null 2>&1 || return 0
  local snapshot db_json
  snapshot="$(query_usage_snapshot)" || { warn "统计采样失败，本次未修改流量基线。"; return 1; }
  db_json="$(account_usage_snapshot "$(user_db_load)" "$snapshot")" || return 1
  user_db_save "$db_json" || { warn "用户流量统计落盘失败：$USER_DB_FILE"; return 1; }
}

# ---------- Meta 存储（Reality 公钥等） ----------

meta_load() {
  if [ -s "$META_FILE" ] && jq -e . "$META_FILE" >/dev/null 2>&1; then
    cat "$META_FILE"
  else
    echo '{}'
  fi
}

meta_save() {
  local meta_json="$1"
  mkdir -p "$(dirname "$META_FILE")"
  chmod 700 "$(dirname "$META_FILE")" 2>/dev/null || true
  local tmp_file
  tmp_file="$(mktemp "${META_FILE}.tmp.XXXXXX")" || return 1
  if echo "$meta_json" | jq . > "$tmp_file"; then
    if ! mv -f "$tmp_file" "$META_FILE"; then
      err "元数据写入失败：$META_FILE"
      rm -f "$tmp_file" >/dev/null 2>&1 || true
      return 1
    fi
    chmod 600 "$META_FILE" 2>/dev/null || true
  else
    rm -f "$tmp_file"
    return 1
  fi
}

meta_set_reality_public_key() {
  local tag="$1" public_key="$2"
  [ -n "$tag" ] && [ -n "$public_key" ] || return 0
  local meta_json
  meta_json="$(meta_load)"
  meta_json="$(echo "$meta_json" | jq --arg t "$tag" --arg pk "$public_key" '.[$t] = ((.[$t] // {}) + {public_key:$pk, private_key_auto_generated:true})')" || return 1
  meta_save "$meta_json"
}

meta_get_reality_public_key() {
  local tag="$1"
  meta_load | jq -r --arg t "$tag" '.[$t].public_key // ""'
}

# >>>>>>>>> END MODULE: 50_v2ray_api.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 60_user_db.sh <<<<<<<<<<<
# ============================================================
# 模块: 60_user_db.sh
# 职责: 用户数据库 CRUD（纯数据操作，不含 UI）
# 依赖: 00_base.sh, 01_utils.sh, 10_config.sh (with_manager_lock)
# ============================================================

user_db_min_template() {
  cat <<'JSON'
{
  "enabled": true,
  "meta": {
    "data_updated_at_text": ""
  },
  "users": {
    "admin": {
      "enabled": true,
      "disabled_reason": null,
      "quota_gb": 0,
      "used_up_bytes": 0,
      "used_down_bytes": 0,
      "manual_added_bytes": 0,
      "last_live_up_bytes": 0,
      "last_live_down_bytes": 0,
      "last_reset_period": "",
      "reset_day": 0,
      "expire_at": "0",
      "allow_all_nodes": true,
      "nodes": []
    }
  }
}
JSON
}

user_db_exists() {
  [ -s "$USER_DB_FILE" ] && jq -e '.enabled == true and (.users.admin != null)' "$USER_DB_FILE" >/dev/null 2>&1
}

user_db_load() {
  if user_db_exists; then
    cat "$USER_DB_FILE"
  else
    user_db_min_template
  fi
}

user_db_save() {
  with_manager_lock _user_db_save_body "$@"
}

user_db_touch_data_updated_at() {
  with_manager_lock _user_db_touch_data_updated_at_body "$@"
}

_user_db_touch_data_updated_at_body() {
  user_db_exists || return 0
  local db_json now_text
  db_json="$(user_db_load)"
  now_text="$(date '+%Y-%m-%d %H:%M:%S')"
  db_json="$(echo "$db_json" | jq --arg now "$now_text" '
    .meta = (.meta // {})
    | .meta.data_updated_at_text = $now
  ')" || return 1
  user_db_save "$db_json"
}

_user_db_save_body() {
  local db_json="$1"
  mkdir -p "$(dirname "$USER_DB_FILE")" /etc/sing-box
  chmod 700 "$(dirname "$USER_DB_FILE")" 2>/dev/null || true
  local tmp_file
  tmp_file="$(mktemp "${USER_DB_FILE}.tmp.XXXXXX")" || return 1
  if echo "$db_json" | jq . > "$tmp_file"; then
    if ! mv -f "$tmp_file" "$USER_DB_FILE"; then
      err "用户数据库写入失败：$USER_DB_FILE"
      rm -f "$tmp_file" >/dev/null 2>&1 || true
      return 1
    fi
    chmod 600 "$USER_DB_FILE" 2>/dev/null || true
  else
    rm -f "$tmp_file"
    return 1
  fi
}

user_billable_bytes() {
  local db_json="$1" username="$2"
  echo "$db_json" | jq -r --arg u "$username" '
    (.users[$u].used_up_bytes // 0)
    + (.users[$u].used_down_bytes // 0)
    + (.users[$u].manual_added_bytes // 0)
  '
}

package_text_for_user() {
  local db_json="$1" username="$2"
  local quota
  quota="$(echo "$db_json" | jq -r --arg u "$username" '.users[$u].quota_gb // 0')"
  if [ "$quota" = "0" ]; then
    echo "不限"
  else
    echo "${quota}GB"
  fi
}

user_db_enabled_users() {
  local db_json="$1"
  echo "$db_json" | jq -r '.users | to_entries[] | select(.value.enabled == true) | .key' | awk 'NF'
}

user_db_all_users() {
  local db_json="$1"
  echo "$db_json" | jq -r '.users | to_entries[] | .key' | awk 'NF'
}

user_db_user_exists() {
  local db_json="$1" username="$2"
  echo "$db_json" | jq -e --arg u "$username" '.users[$u] != null' >/dev/null 2>&1
}

user_db_user_is_enabled() {
  local db_json="$1" username="$2"
  echo "$db_json" | jq -e --arg u "$username" '.users[$u].enabled == true' >/dev/null 2>&1
}

user_db_user_allow_node() {
  local db_json="$1" username="$2" node_key="$3"
  echo "$db_json" | jq -e --arg u "$username" --arg n "$node_key" '
    (.users[$u].allow_all_nodes == true) or ((.users[$u].nodes // []) | index($n) != null)
  ' >/dev/null 2>&1
}

# 节点添加时的扩展点（当前设计：新节点只给 admin，不自动分配给其他用户）
user_db_on_node_added() {
  local db_json="$1" node_key="$2"
  echo "$db_json"
}

user_db_cleanup_missing_nodes() {
  local db_json="$1" json="$2"
  local available_json
  available_json="$(
    list_all_node_keys "$json" | jq -R . | jq -s '.'
  )"
  echo "$db_json" | jq --argjson available "$available_json" '
    .users |= with_entries(
      .value.nodes = (
        (.value.nodes // [])
        | [.[] | . as $n | select(($available | index($n)) != null)]
        | unique
      )
    )
  '
}

user_db_cleanup_current_and_save() {
  with_manager_lock _user_db_cleanup_current_and_save_body "$@"
}

_user_db_cleanup_current_and_save_body() {
  local db_json json cleaned
  user_db_exists || return 0
  db_json="$(user_db_load)"
  json="$(config_load)"
  cleaned="$(user_db_cleanup_missing_nodes "$db_json" "$json")" || return 1
  user_db_save "$cleaned"
  return 0
}

# >>>>>>>>> END MODULE: 60_user_db.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 61_user_manager.sh <<<<<<<<<<<
# ============================================================
# 模块: 61_user_manager.sh
# 职责: 用户管理业务逻辑（投影、同步、自动控制）
# 依赖: 00_base.sh, 10_config.sh, 20_protocol.sh, 30_route.sh,
#       50_v2ray_api.sh, 60_user_db.sh
# ============================================================

user_manager_apply_to_json() {
  local json="$1" db_json="$2" meta_json="${3:-}"
  local work_json="$json"
  local inv_lines=() line idx entry_key proto port inbound
  work_json="$(config_normalize "$work_json")" || return 1
  mapfile -t inv_lines < <(protocol_entry_inventory_ext "$work_json")
  for line in "${inv_lines[@]}"; do
    IFS=$'\x01' read -r idx entry_key proto port <<< "$line"
    inbound="$(find_inbound_by_entry_key "$work_json" "$entry_key")"
    [ -n "$inbound" ] || continue

    # Plan credentials in one jq pass; only new credentials need external generators.
    local plan users_json missing desired new_obj
    plan="$(echo "$inbound" | jq -c --argjson db "$db_json" --arg entry "$entry_key" --arg proto "$proto" "${JQ_NODE_PART}"'
      def business($n): if ($n|contains("@")) then ($n|split("@")[1]) else "admin" end;
      . as $ib
      | [(.users // [])[] | (.name // .username // "") | node_part(.)
         | select(contains("-to-") and . != $entry)] | unique as $relays
      | def allowed($node):
          $db.users | to_entries[] | select(.key != "admin")
          | select($proto != "socks" or .value.enabled == true)
          | select(.value.allow_all_nodes == true or ((.value.nodes // []) | index($node)) != null)
          | $node + "@" + .key;
      [if $proto != "socks" or $db.users.admin.enabled == true then $entry else empty end,
       allowed($entry), ($relays[] | . as $node | $node, allowed($node))] as $desired
      | (reduce ($ib.users // [])[] as $u ({}; .[$u.name // $u.username] //= $u)) as $existing
      | [$desired[] | . as $name
          | ($existing[$name] // (if $proto == "socks" and node_part($name) == $entry then
              [$ib.users[]? | select((.username // "") != "")
               | select((node_part(.username)|contains("-to-")|not) and business(.username) == business($name))
               | .username=$name][0] else null end)) as $object
          | {name:$name,object:$object}]
    ')" || return 1
    users_json="$(echo "$plan" | jq -c '[.[].object | select(. != null)]')" || return 1
    while IFS= read -r desired; do
      [ -n "$desired" ] || continue
      new_obj="$(build_user_object_from_inbound "$inbound" "$desired")" || return 1
      users_json="$(echo "$users_json" | jq -c --argjson obj "$new_obj" '. + [$obj]')" || return 1
    done < <(echo "$plan" | jq -r '.[] | select(.object == null) | .name')
    # Match the original desired order, including credentials just created.
    users_json="$(echo "$users_json" | jq -c --argjson plan "$plan" '
      (reduce .[] as $u ({}; .[$u.name // $u.username]=$u)) as $by_name
      | [$plan[].name | $by_name[.]]
    ')" || return 1
    work_json="$(echo "$work_json" | jq --argjson idx "$idx" --argjson users "$users_json" '.inbounds[$idx].users = $users')" || return 1
  done

  if [ -n "$meta_json" ]; then
    work_json="$(route_rebuild "$work_json" "$meta_json")" || return 1
  else
    work_json="$(route_rebuild "$work_json")" || return 1
  fi
  work_json="$(filter_disabled_auth_users "$work_json" "$db_json")" || return 1
  ensure_v2ray_api_on_json "$work_json" || return 1
}

filter_disabled_auth_users() {
  local json="$1" db_json="$2"
  local enabled_json
  enabled_json="$(echo "$db_json" | jq -c '[.users | to_entries[] | select(.value.enabled == true) | .key]')"
  echo "$json" | jq "${JQ_AUTH_USERS}"'
    def user_enabled($u):
      if ($u | contains("@")) then ($enabled | index(($u | split("@")[1]))) != null
      else ($enabled | index("admin")) != null
      end;

    .route.rules |= map(
      if (.auth_user? == null) then .
      else
        (auth_users_array | map(select(user_enabled(.)))) as $remain
        | if ($remain | length) == 0 then empty
          elif ($remain | length) == 1 then .auth_user = $remain[0]
          else .auth_user = $remain
          end
      end
    )
  ' --argjson enabled "$enabled_json"
}

# 菜单传入前后快照用于提取字段补丁；在锁内将补丁合并到最新数据。
# 同字段被其他管理操作修改时拒绝提交，避免无声覆盖。
merge_user_edit() {
  local current="$1" before="$2" after="$3" mode="${4:-edit}" target="${5:-}"
  printf '%s' "$current" | jq --argjson before "$before" --argjson after "$after" --arg mode "$mode" --arg target "$target" '
    def policy: del(.used_up_bytes,.used_down_bytes,.last_live_up_bytes,.last_live_down_bytes,.manual_added_bytes);
    reduce ((($before.users|keys) + ($after.users|keys)) | unique[]) as $u (. ;
      ($before.users[$u]) as $old | ($after.users[$u]) as $new
      | if $old == null then
          if .users[$u] != null then error("用户已被其他操作创建: " + $u) else .users[$u]=$new end
        elif $new == null then
          if .users[$u] == null then .
          elif ((.users[$u]|policy) != ($old|policy)) then error("用户状态已变化，请重新确认删除: " + $u)
          else del(.users[$u]) end
        else
          ([$new|keys[] | select(. != "used_up_bytes" and . != "used_down_bytes" and . != "last_live_up_bytes" and . != "last_live_down_bytes")
            | . as $f | select($new[$f] != $old[$f])]) as $fields
          | if ($fields|length) == 0 and ($u != $target or $mode != "reset") then .
            elif .users[$u] == null then error("用户已被删除: " + $u)
            else reduce $fields[] as $f (. ;
              if $f == "manual_added_bytes" and $mode == "add" then
                .users[$u][$f] = ((.users[$u][$f] // 0) + ($new[$f] // 0) - ($old[$f] // 0))
              elif $f == "manual_added_bytes" and $mode == "reset" then .
              elif .users[$u][$f] != $old[$f] then error("字段已被其他操作修改: " + $u + "." + $f)
              else .users[$u][$f]=$new[$f] end)
            end
        end)
    | if $mode == "reset" then
        if .users[$target] == null then error("用户不存在") else
          .users[$target].used_up_bytes=0 | .users[$target].used_down_bytes=0 | .users[$target].manual_added_bytes=0
        end
      else . end
  '
}

user_manager_commit_edit() {
  with_manager_lock _user_manager_commit_edit_body "$@"
}

_user_manager_commit_edit_body() {
  local before="$1" after="$2" mode="${3:-edit}" target="${4:-}" merged
  sync_user_usage_counters || return 1
  merged="$(merge_user_edit "$(user_db_load)" "$before" "$after" "$mode" "$target")" || {
    err "数据已变化或输入无效，请重新打开菜单后操作。"
    return 1
  }
  _user_manager_apply_changes_body "$merged"
}

user_manager_apply_changes() {
  with_manager_lock _user_manager_apply_changes_body "$@"
}

_user_manager_apply_changes_body() {
  local db_json="$1" base_json="${2:-}" meta_json="${3:-}"
  if [ "${_USER_KEEP_LATEST_DB:-0}" = "1" ]; then
    sync_user_usage_counters || return 1
    db_json="$(user_db_load)"
  fi
  [ -n "$base_json" ] || base_json="$(config_load)"

  db_json="$(user_db_cleanup_missing_nodes "$db_json" "$base_json")" || return 1

  local applied_json
  applied_json="$(user_manager_apply_to_json "$base_json" "$db_json" "$meta_json")" || {
    err "生成用户节点关系失败。"
    return 1
  }

  local old_db_json="" had_db=0
  if user_db_exists; then
    old_db_json="$(user_db_load)"
    had_db=1
  fi
  # 抓 old_config 用于 meta_save 失败时回滚（即使调用方没传 meta_json 也无害——下面只在传了时才用）
  local old_config_json
  old_config_json="$(config_load 2>/dev/null)" || old_config_json='{}'

  user_db_save "$db_json" || {
    err "用户数据库保存失败，已阻止配置变更。"
    return 1
  }

  if ! _CONFIG_APPLY_QUIET_OK=1 config_apply_no_usage_sync "$applied_json"; then
    # config 失败，回滚 user_db
    if [ "$had_db" = "1" ]; then
      user_db_save "$old_db_json" || warn "配置应用失败，且用户数据库回滚失败，请手动检查：$USER_DB_FILE"
    else
      rm -f "$USER_DB_FILE" >/dev/null 2>&1 || warn "配置应用失败，且用户数据库清理失败，请手动检查：$USER_DB_FILE"
    fi
    return 1
  fi

  # config 已成功，提交 meta（如果调用方传了 meta_json）
  if [ -n "$meta_json" ]; then
    if ! meta_save "$meta_json"; then
      err "元数据保存失败，正在回滚配置和用户数据库..."
      _CONFIG_APPLY_QUIET_OK=1 _CONFIG_SKIP_USAGE_SYNC=1 config_apply "$old_config_json" \
        || err "回滚配置失败，请手动检查 $CONFIG_FILE"
      if [ "$had_db" = "1" ]; then
        user_db_save "$old_db_json" || warn "用户数据库回滚失败，请手动检查 $USER_DB_FILE"
      else
        rm -f "$USER_DB_FILE" >/dev/null 2>&1 || warn "用户数据库清理失败：$USER_DB_FILE"
      fi
      return 1
    fi
  fi

  [ "${_USER_MANAGER_APPLY_QUIET_OK:-0}" = "1" ] || ok "用户变更已应用。"
  return 0
}

user_manager_runtime_sync() {
  local db_json current_json desired_json current_norm desired_norm
  db_json="$(user_db_load)"
  if [ ! -s "$USER_DB_FILE" ]; then
    user_db_save "$db_json" || return 1
  fi

  current_json="$(config_load)"
  desired_json="$(user_manager_apply_to_json "$current_json" "$db_json")" || {
    err "生成用户流量统计配置失败。"
    return 1
  }

  current_norm="$(echo "$current_json" | jq -S .)"
  desired_norm="$(echo "$desired_json" | jq -S .)"
  if [ "$current_norm" != "$desired_norm" ]; then
    if _CONFIG_APPLY_QUIET_OK=1 config_apply "$desired_json"; then
      ok "配置已同步。"
    else
      err "配置同步失败。"
      return 1
    fi
  fi

  return 0
}

# ---------- 自动控制（到期/超额/重置） ----------

user_today_date() {
  TZ="${BUSINESS_TZ:-Asia/Shanghai}" date +%F
}

user_current_period() {
  TZ="${BUSINESS_TZ:-Asia/Shanghai}" date +%Y-%m
}

user_manager_reconcile_user_state() {
  with_manager_lock _user_manager_reconcile_user_state_body
}

_user_manager_reconcile_user_state_body() {
  init_manager_env || return 1
  user_db_exists || return 0
  sync_user_usage_counters || return 1

  local db_json json today period today_day last_day result changed
  db_json="$(user_db_load)"
  json="$(config_load)"
  # 单一时间真理源：所有派生字段都从 today 字符串切片，避免连续调多次 date 在毫秒级跨日导致字段错位
  today="$(user_today_date)"
  period="${today:0:7}"
  today_day=$((10#${today:8:2}))
  last_day=$(awk -v y="${today:0:4}" -v m="${today:5:2}" 'BEGIN {
    split("31 28 31 30 31 30 31 31 30 31 30 31", d, " ")
    d[2] = (y%4==0 && (y%100!=0 || y%400==0)) ? 29 : 28
    print d[m+0]
  }')

  result="$(echo "$db_json" | jq --arg today "$today" --arg period "$period" --argjson today_day "$today_day" --argjson last_day "$last_day" '
    .users |= with_entries(
      .value as $v
      | ($v.expire_at // "0") as $expire
      | ($v.reset_day // 0) as $reset_day
      | ($v.last_reset_period // "") as $last_reset
      | ($v.quota_gb // 0) as $quota
      | ($v.disabled_reason // null) as $reason
      | ($expire != "0" and ($today >= $expire)) as $expired
      | (
          if ($reset_day == 32) then $last_day
          elif ($reset_day >= 1 and $reset_day <= 29) then
            (if ($reset_day > $last_day) then $last_day else $reset_day end)
          else 0 end
        ) as $effective_reset_day

      | ($period | split("-") | map(tonumber)) as $ym
      | (if $ym[1] == 1 then [($ym[0]-1),12] else [$ym[0],($ym[1]-1)] end) as $prev
      | (if $today_day >= $effective_reset_day then $period
         else (($prev[0]|tostring) + "-" + ("0" + ($prev[1]|tostring))[-2:]) end) as $due_period
      # 新建用户/调整重置日先建账，不追溯清零；已有账期则补做漏掉的重置。
      | if ($effective_reset_day > 0 and $last_reset == "") then
          .value.last_reset_period = $due_period
        else . end
      # 1. 到期检查：expire_at 为到期停用日，当天即禁用
      | if $expired then
          .value.enabled = false
          | if ($reason == "manual") then
              .value.disabled_reason = "manual"
            else
              .value.disabled_reason = "expired"
            end
        end
      # 2. 重置检查
      | if (($expired | not) and $effective_reset_day > 0 and $last_reset != "" and $last_reset < $due_period) then
          .value.used_up_bytes = 0
          | .value.used_down_bytes = 0
          | .value.manual_added_bytes = 0
          | .value.last_reset_period = $due_period
          | if ((.value.disabled_reason // null) == "quota_exceeded") then
              .value.enabled = true
              | .value.disabled_reason = null
            else . end
        else . end
      # 3. 超额检查（重置后 billable 已清零，不会误判）
      | if ($quota > 0 and .value.enabled == true) then
          ((.value.used_up_bytes // 0) + (.value.used_down_bytes // 0) + (.value.manual_added_bytes // 0)) as $current_billable
          | if ($current_billable >= ($quota * 1073741824)) then
              .value.enabled = false
              | .value.disabled_reason = "quota_exceeded"
            else . end
        else . end
    )
  ')" || return 1

  changed="$(jq -n --argjson old "$db_json" --argjson new "$result" 'if ($old == $new) then "0" else "1" end' | tr -d '"')"

  if [ "$changed" = "1" ]; then
    user_manager_apply_changes "$result" "$json" >/dev/null 2>&1 || return 1
  fi
  return 0
}

apply_automatic_user_controls() {
  user_manager_reconcile_user_state
}

user_watch_run() {
  # cron 场景下用 flock 排他锁，避免与交互式操作并发修改文件
  local lock_fd
  user_db_exists || return 0
  mkdir -p "$(dirname "$SB_LOCK_FILE")" 2>/dev/null || true
  if ! has_cmd flock || ! { exec {lock_fd}>"$SB_LOCK_FILE"; } 2>/dev/null; then
    err "无法获取管理锁，本轮后台同步已跳过。"
    return 1
  fi
  flock -n "$lock_fd" || { exec {lock_fd}>&-; return 0; }
  # 设置哨兵告知嵌套的 config_apply 已持锁，避免重入死锁
  _CONFIG_LOCK_HELD=1
  if user_manager_background_sync >/dev/null 2>&1; then
    apply_automatic_user_controls >/dev/null 2>&1 || true
    user_db_touch_data_updated_at >/dev/null 2>&1 || true
  fi
  _CONFIG_LOCK_HELD=0
  exec {lock_fd}>&-
}

ensure_user_manager_ready() {
  init_manager_env || return 1
  if ! user_db_exists; then
    user_db_save "$(user_db_min_template)" || {
      err "用户数据库初始化失败：$USER_DB_FILE"
      return 1
    }
    ok "已初始化用户数据库，默认启用 admin 用户。"
  fi
  return 0
}

user_manager_background_sync() {
  user_db_exists || return 0
  init_manager_env || return 1
  user_db_cleanup_current_and_save || return 1
  user_manager_runtime_sync || return 1
  return 0
}

# >>>>>>>>> END MODULE: 61_user_manager.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 62_user_menu.sh <<<<<<<<<<<
# ============================================================
# 模块: 62_user_menu.sh
# 职责: 用户管理交互菜单（纯 UI 层）
# 依赖: 00_base.sh, 01_utils.sh, 60_user_db.sh, 61_user_manager.sh
# ============================================================

user_package_invalid_return() {
  ui_echo "${Y}[WARN]${NC} 输入无效，未作修改，已返回上一级。"
}

show_user_status_table() {
  local db_json="$1"
  local sep=$'\t'
  local header widths_line row_line
  local -a rows=()
  local -a cols=()

  header="用户名${sep}状态${sep}上传流量${sep}下载流量${sep}补正流量${sep}已用总量${sep}套餐${sep}重置日${sep}到期时间"
  rows+=("$header")

  while IFS= read -r row_line; do
    [ -n "$row_line" ] && rows+=("$row_line")
  done < <(
    echo "$db_json" | jq -r '
      .users
      | to_entries
      | .[]
      | [
          .key,
          (if (.value.enabled == true) then "开启" else "关闭" end),
          ((.value.used_up_bytes // 0) | tostring),
          ((.value.used_down_bytes // 0) | tostring),
          ((.value.manual_added_bytes // 0) | tostring),
          (((.value.used_up_bytes // 0) + (.value.used_down_bytes // 0) + (.value.manual_added_bytes // 0)) | tostring),
          ((if (.value.quota_gb // 0) == 0 then "不限" else ((.value.quota_gb|tostring) + "GB") end)),
          (if (.value.reset_day // 0) == 0 then "不重置" elif (.value.reset_day // 0) == 32 then "月底" else ((.value.reset_day|tostring) + "号") end),
          (if (.value.expire_at // "0") == "0" then "永久" else (.value.expire_at // "0") end)
        ] | join("\u0001")
    ' | while IFS=$'\x01' read -r c1 c2 c3 c4 c5 c6 c7 c8 c9; do
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$c1" \
            "$c2" \
            "$(format_bytes_human "$c3")" \
            "$(format_bytes_human "$c4")" \
            "$(format_bytes_human "$c5")" \
            "$(format_bytes_human "$c6")" \
            "$c7" \
            "$c8" \
            "$c9"
      done
  )

  widths_line="$(table_compute_widths "$sep" "${rows[@]}")"

  IFS="$sep" read -r -a cols <<< "$header"
  local header_line divider_line divider_width
  header_line="$(table_print_row "$widths_line" "${cols[@]}")"
  divider_width="$(text_display_width "$header_line")"
  divider_line="$(printf '%*s' "$divider_width" '' | tr ' ' '-')"

  ui_echo "\033[1m${header_line}${NC}"
  ui_echo "${B}${divider_line}${NC}"

  for row_line in "${rows[@]:1}"; do
    IFS="$sep" read -r -a cols <<< "$row_line"
    table_print_row "$widths_line" "${cols[@]}"
  done

  ui_echo "${B}${divider_line}${NC}"
}

prompt_reset_day() {
  local outvar="$1" val
  while true; do
    ui_echo "0  不重置"
    ui_echo "1-29 指定日期"
    ui_echo "32 月底"
    read -r -p "请输入重置日: " val
    case "$val" in
      0|32) printf -v "$outvar" '%s' "$val"; return 0 ;;
      '') ui_echo "${Y}[WARN]${NC} 请输入 0、1-29 或 32。" ;;
      *)
        if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 1 ] && [ "$val" -le 29 ]; then
          printf -v "$outvar" '%s' "$val"
          return 0
        fi
        ui_echo "${Y}[WARN]${NC} 请输入 0、1-29 或 32。"
        ;;
    esac
  done
}

prompt_expire_date() {
  local outvar="$1" val
  read -r -p "请输入到期日期（格式：YYYY-MM-DD，输入 0 表示永久，回车返回）: " val
  if [ "$val" = "0" ]; then
    printf -v "$outvar" '%s' '0'
    return 0
  fi
  if is_valid_ymd_date "$val"; then
    printf -v "$outvar" '%s' "$val"
    return 0
  fi
  ui_echo "${Y}[WARN]${NC} 日期不合法，未作修改，已返回上一级。"
  return 1
}

select_nodes_multi() {
  local json="$1" outvar="$2"
  local nodes=()
  # 节点按协议顺序排序
  mapfile -t nodes < <(list_all_node_keys "$json")
  if [ ${#nodes[@]} -eq 0 ]; then
    printf -v "$outvar" '%s' '[]'
    return 0
  fi
  ui_echo "请选择可用节点（多个用 + 连接，0 清除全部，回车跳过）："
  local i=1 node
  for node in "${nodes[@]}"; do
    ui_echo " [$i] $node"
    i=$((i+1))
  done
  local ans part selected=()
  read -r -p "请输入编号: " ans
  [ -z "${ans:-}" ] && { printf -v "$outvar" '%s' '__SKIP__'; return 0; }
  mapfile -t picks < <(parse_plus_selections "$ans")
  if [ ${#picks[@]} -eq 1 ] && [ "${picks[0]}" = "0" ]; then
    printf -v "$outvar" '%s' '[]'
    return 0
  fi
  for part in "${picks[@]}"; do
    if [[ "$part" =~ ^[0-9]+$ ]] && [ "$part" -ge 1 ] && [ "$part" -le "${#nodes[@]}" ]; then
      selected+=("${nodes[$((part-1))]}")
    fi
  done
  if [ ${#selected[@]} -gt 0 ]; then
    local picks_json
    picks_json="$(printf '%s\n' "${selected[@]}" | awk 'NF' | sort -u | jq -R . | jq -s '.')"
    printf -v "$outvar" '%s' "$picks_json"
  else
    printf -v "$outvar" '%s' '[]'
  fi
}

show_user_allowed_nodes() {
  local db_json="$1" username="$2"
  ui_echo "允许节点："
  if echo "$db_json" | jq -e --arg u "$username" '.users[$u].allow_all_nodes == true' >/dev/null 2>&1; then
    if [ "$username" = "admin" ]; then
      ui_echo "  - 全部节点（admin）"
    else
      ui_echo "  - 全部节点"
    fi
    return 0
  fi

  local has_node=0 node
  while IFS= read -r node; do
    [ -n "$node" ] || continue
    ui_echo "  - $node"
    has_node=1
  done < <(echo "$db_json" | jq -r --arg u "$username" '.users[$u].nodes[]? // empty' | sort_node_keys_by_protocol)
  [ "$has_node" -eq 1 ] || ui_echo "  - （无）"
}

user_add_menu() {
  local db_json json username quota reset_day expire_at ans nodes_json allow_all_json before_db
  db_json="$(user_db_load)"
  before_db="$db_json"
  json="$(config_load)"
  clear
  print_rect_title "新增用户"
  show_user_status_table "$db_json"
  read -r -p "请输入用户名（回车返回）: " username
  if ! is_valid_user_name "$username"; then
    warn "用户名仅允许字母、数字、点、下划线、短横线。"
    pause
    return 1
  fi
  [ "$username" = "admin" ] && { warn "admin 为系统默认用户，不能新增。"; pause; return 1; }
  if user_db_user_exists "$db_json" "$username"; then
    warn "用户已存在：$username"
    pause
    return 1
  fi
  ui_echo "${Y}折算成单向流量填入。示例：双向800G流量就填写400，单向500G流量就填写500${NC}"
  read -r -p "请输入流量限制（GB，输入 0 表示不限，回车返回）: " quota
  [[ "$quota" =~ ^[0-9]+$ ]] || { warn "输入无效，未作修改，已返回上一级。"; pause; return 0; }
  prompt_reset_day reset_day
  if ! prompt_expire_date expire_at; then pause; return 0; fi

  # 节点权限设置（按协议顺序展示）
  allow_all_json='false'
  nodes_json='[]'
  ui_echo "${C}--- 节点权限 ---${NC}"
  select_nodes_multi "$json" nodes_json
  if [ "$nodes_json" = "__SKIP__" ]; then
    nodes_json='[]'
    ui_echo "已跳过节点权限设置，默认不分配节点。"
  fi

  db_json="$(echo "$db_json" | jq --arg u "$username" --argjson quota "$quota" --argjson reset "$reset_day" --arg expire "$expire_at" --argjson allow "$allow_all_json" --argjson nodes "$nodes_json" '
    .users[$u] = {
      enabled: true,
      disabled_reason: null,
      quota_gb: $quota,
      used_up_bytes: 0,
      used_down_bytes: 0,
      manual_added_bytes: 0,
      last_live_up_bytes: 0,
      last_live_down_bytes: 0,
      last_reset_period: "",
      reset_day: $reset,
      expire_at: $expire,
      allow_all_nodes: $allow,
      nodes: $nodes
    }
  ')"
  user_manager_commit_edit "$before_db" "$db_json" || { pause; return 1; }
  pause
}

user_manage_permission_menu() {
  local db_json="$1" username="$2" json="$3"
  local cleaned_db_json
  cleaned_db_json="$(user_db_cleanup_missing_nodes "$db_json" "$json")" || cleaned_db_json="$db_json"
  db_json="$cleaned_db_json"
  local current_nodes_json
  local nodes=() node i raw picks=() invalid=0 sel idx selected_json new_db

  clear >&2
  print_rect_title "节点权限" >&2
  show_user_status_table "$db_json" >&2
  current_nodes_json="$(echo "$db_json" | jq -c --arg u "$username" '(.users[$u].nodes // [])')"

  ui_echo "当前已分配节点："
  while IFS= read -r node; do
    [ -n "$node" ] && ui_echo "- $node"
  done < <(echo "$current_nodes_json" | jq -r '.[]?')
  if ! echo "$current_nodes_json" | jq -e 'length > 0' >/dev/null 2>&1; then
    ui_echo "- （无）"
  fi
  ui_echo "${B}--------------------------------------------------------${NC}"

  # 节点列表按协议顺序排序
  mapfile -t nodes < <(list_all_node_keys "$json")
  ui_echo "可选节点："
  ui_echo "  0. 清除全部节点权限"
  i=1
  for node in "${nodes[@]}"; do
    ui_echo "  ${i}. ${node}"
    i=$((i+1))
  done
  read -r -p "请输入编号（多个用 + 连接，回车返回上一级）: " raw
  [ -z "${raw:-}" ] && return 1
  mapfile -t picks < <(parse_plus_selections "$raw")
  [ ${#picks[@]} -eq 0 ] && return 1

  # 选择 0 = 清除全部
  if [ ${#picks[@]} -eq 1 ] && [ "${picks[0]}" = "0" ]; then
    new_db="$(echo "$db_json" | jq --arg u "$username" '.users[$u].allow_all_nodes = false | .users[$u].nodes = []')"
    echo "$new_db"
    return 0
  fi

  for sel in "${picks[@]}"; do
    if ! [[ "$sel" =~ ^[0-9]+$ ]]; then invalid=1; break; fi
    if [ "$sel" -lt 1 ] || [ "$sel" -gt ${#nodes[@]} ]; then invalid=1; break; fi
  done

  if [ $invalid -eq 1 ]; then
    ui_echo "${Y}[WARN]${NC} 输入编号无效，未做任何修改。"
    pause >&2
    return 1
  fi

  selected_json="$({
    for sel in "${picks[@]}"; do
      idx=$((sel-1))
      if [ $idx -ge 0 ] && [ $idx -lt ${#nodes[@]} ]; then
        echo "${nodes[$idx]}"
      fi
    done
  } | awk 'NF' | LC_ALL=C sort -u | jq -R . | jq -s '.')"

  new_db="$(echo "$db_json" | jq --arg u "$username" --argjson nodes "$selected_json" '.users[$u].allow_all_nodes = false | .users[$u].nodes = $nodes')"
  echo "$new_db"
}

user_manage_package_menu() {
  local db_json="$1" username="$2"
  local current_quota current_reset current_expire quota_in reset_in expire_in quota_val reset_val expire_val
  clear >&2
  print_rect_title "套餐设置" >&2
  show_user_status_table "$db_json" >&2

  IFS=$'\x01' read -r current_quota current_reset current_expire < <(
    echo "$db_json" | jq -r --arg u "$username" '
      [((.users[$u].quota_gb // 0) | tostring),
       ((.users[$u].reset_day // 0) | tostring),
       (.users[$u].expire_at // "0")] | join("\u0001")
    '
  )

  ui_echo "当前流量限制：${current_quota} GB"
  ui_echo "${Y}折算成单向流量填入。示例：双向800G流量就填写400，单向500G流量就填写500${NC}"
  ui_echo "单位为 GB ，输入 0 表示不限"
  ui_echo "回车：保持当前值"
  read -r -p "请输入: " quota_in
  if [ -z "$quota_in" ]; then
    quota_val="$current_quota"
  elif [[ "$quota_in" =~ ^[0-9]+$ ]]; then
    quota_val="$quota_in"
  else
    user_package_invalid_return; pause >&2; return 1
  fi

  ui_echo "当前重置日期：$(reset_day_text "$current_reset")"
  ui_echo "0. 不重置"
  ui_echo "1-29. 指定日期"
  ui_echo "32. 月底"
  ui_echo "回车：保持当前值"
  read -r -p "请输入: " reset_in
  if [ -z "$reset_in" ]; then
    reset_val="$current_reset"
  elif [ "$reset_in" = "0" ] || [ "$reset_in" = "32" ]; then
    reset_val="$reset_in"
  elif [[ "$reset_in" =~ ^[0-9]+$ ]] && [ "$reset_in" -ge 1 ] && [ "$reset_in" -le 29 ]; then
    reset_val="$reset_in"
  else
    user_package_invalid_return; pause >&2; return 1
  fi

  ui_echo "当前到期时间：$(expire_text "$current_expire")"
  ui_echo "请输入到期日期（格式：YYYY-MM-DD，输入 0 表示永久）:"
  ui_echo "回车：保持当前值"
  read -r -p "请输入: " expire_in
  if [ -z "$expire_in" ]; then
    expire_val="$current_expire"
  elif [ "$expire_in" = "0" ]; then
    expire_val="0"
  elif is_valid_ymd_date "$expire_in"; then
    expire_val="$expire_in"
  else
    user_package_invalid_return; pause >&2; return 1
  fi

  if [ "$quota_val" = "$current_quota" ] && [ "$reset_val" = "$current_reset" ] && [ "$expire_val" = "$current_expire" ]; then
    ui_echo "${C}[INFO]${NC} 未检测到改动，按任意键返回。"
    pause >&2
    return 1
  fi

  echo "$db_json" | jq --arg u "$username" --argjson quota "$quota_val" --argjson reset "$reset_val" --arg exp "$expire_val" '
    (.users[$u].reset_day // 0) as $old_reset
    | .users[$u].quota_gb = $quota
    | .users[$u].reset_day = $reset
    | .users[$u].expire_at = $exp
    | if ($old_reset != $reset) then .users[$u].last_reset_period = "" else . end
  '
}

user_add_usage_menu() {
  local db_json="$1" username="$2" raw bytes
  clear >&2
  print_rect_title "手动添加流量" >&2
  show_user_status_table "$db_json" >&2
  ui_echo "此操作会增加该用户的手动补正流量，用于对齐总量。"
  ui_echo "支持负值输入（如 -100MB）减少补正流量。"
  read -r -p "请输入要增添的流量（精确到小数点后一位，需带单位 MB、GB、TB，回车返回）: " raw
  bytes="$(parse_traffic_to_bytes "$raw")" || {
    warn "输入无效，未作修改，已返回上一级。"
    pause >&2
    return 1
  }
  echo "$db_json" | jq --arg u "$username" --argjson add "$bytes" '
    .users[$u].manual_added_bytes = ((.users[$u].manual_added_bytes // 0) + $add)
  '
}

user_reset_usage_menu() {
  local db_json="$1" username="$2"
  clear >&2
  print_rect_title "手动重置流量" >&2
  show_user_status_table "$db_json" >&2
  ui_echo "将清零该用户的上传流量、下载流量和手动补正流量。"
  ui_echo "此操作不会修改用户的启用状态、套餐设置、到期时间或重置日。"
  local ans
  read -r -p "输入 YES 确认重置该用户流量，其它任意输入取消: " ans
  if [ "$ans" != "YES" ]; then
    return 1
  fi
  echo "$db_json" | jq --arg u "$username" '
    .users[$u].used_up_bytes = 0
    | .users[$u].used_down_bytes = 0
    | .users[$u].manual_added_bytes = 0
  '
}

user_date_add_months() {
  local base_date="$1" months="$2"
  awk -v base="$base_date" -v add="$months" '
    function leap(y) { return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) }
    function dim(y, m) {
      if (m == 2) return leap(y) ? 29 : 28
      if (m == 4 || m == 6 || m == 9 || m == 11) return 30
      return 31
    }
    BEGIN {
      split(base, a, "-")
      y = a[1] + 0; m = a[2] + 0; d = a[3] + 0; add += 0
      if (y < 1 || m < 1 || m > 12 || d < 1 || d > dim(y, m) || add < 1) exit 1
      is_eom = (d == dim(y, m))
      total = y * 12 + (m - 1) + add
      ty = int(total / 12)
      tm = (total % 12) + 1
      td = is_eom ? dim(ty, tm) : d
      if (td > dim(ty, tm)) td = dim(ty, tm)
      printf "%04d-%02d-%02d\n", ty, tm, td
    }
  '
}

user_expire_is_past() {
  local today="$1" expire_at="$2"
  [ "$expire_at" != "0" ] && { [[ "$today" > "$expire_at" ]] || [[ "$today" == "$expire_at" ]]; }
}

user_renew_menu() {
  local db_json="$1" username="$2"
  local current_expire today base_date expired=0 choice months custom_months new_expire

  clear >&2
  print_rect_title "一键续期" >&2
  show_user_status_table "$db_json" >&2

  current_expire="$(echo "$db_json" | jq -r --arg u "$username" '.users[$u].expire_at // "0"')"
  if [ "$current_expire" = "0" ]; then
    warn "永久用户无需续期。"
    pause >&2
    return 1
  fi

  today="$(user_today_date)"
  if user_expire_is_past "$today" "$current_expire"; then
    expired=1
    base_date="$today"
    warn "用户已过期：按今天续期，并重置流量。"
  else
    base_date="$current_expire"
  fi

  ui_echo "当前到期时间：$(expire_text "$current_expire")"
  ui_echo "续期起点：$base_date"
  ui_echo "1. 续期一个月"
  ui_echo "2. 续期一个季度"
  ui_echo "3. 自定义续期月数"
  read -r -p "请选择操作（回车返回上一级）: " choice
  case "${choice:-}" in
    1) months=1 ;;
    2) months=3 ;;
    3)
      read -r -p "填写需要续期的月数（回车返回）: " custom_months
      if ! [[ "$custom_months" =~ ^[0-9]+$ ]] || [ "$custom_months" -lt 1 ]; then
        user_package_invalid_return
        pause >&2
        return 1
      fi
      months="$custom_months"
      ;;
    "") return 1 ;;
    *)
      user_package_invalid_return
      pause >&2
      return 1
      ;;
  esac

  new_expire="$(user_date_add_months "$base_date" "$months")" || {
    err "续期日期计算失败，未作修改。"
    pause >&2
    return 1
  }
  param_echo "续期后到期时间" "$new_expire"
  ask_confirm_yn "确认续期吗？(y/N): " || {
    warn "已取消续期。"
    pause >&2
    return 1
  }

  echo "$db_json" | jq --arg u "$username" --arg exp "$new_expire" --argjson expired "$expired" '
    .users[$u].expire_at = $exp
    | if $expired == 1 then
        .users[$u].used_up_bytes = 0
        | .users[$u].used_down_bytes = 0
        | .users[$u].manual_added_bytes = 0
        | .users[$u].last_reset_period = ""
        | if (.users[$u].disabled_reason // null) == "manual" then .
          else .users[$u].enabled = true | .users[$u].disabled_reason = null
          end
      else
        if (.users[$u].disabled_reason // null) == "expired" then
          .users[$u].enabled = true | .users[$u].disabled_reason = null
        else . end
      end
  '
}

user_manage_single() {
  local username="$1"
  local db_json json act new_db mode is_admin=0
  [ "$username" = "admin" ] && is_admin=1
  while true; do
    sync_user_usage_counters || return 1
    db_json="$(user_db_load)"
    json="$(config_load)"
    clear
    print_rect_title "管理用户"
    show_user_status_table "$db_json"
    echo "当前用户：$username"
    [ $is_admin -eq 1 ] && echo "admin 为系统默认用户，不可删除，默认拥有全部节点权限。"
    show_user_allowed_nodes "$db_json" "$username"
    echo "  1. 启用/停用"
    [ $is_admin -eq 0 ] && echo "  2. 节点权限"
    echo "  3. 套餐设置"
    echo "  4. 手动重置流量"
    echo "  5. 手动添加流量（对齐总量）"
    echo "  6. 一键续期"
    echo "  0. 返回上一级"
    read -r -p "请选择操作: " act
    case "${act:-}" in
      1)
        if user_db_user_is_enabled "$db_json" "$username"; then
          new_db="$(echo "$db_json" | jq --arg u "$username" '.users[$u].enabled = false | .users[$u].disabled_reason = "manual"')"
        else
          new_db="$(echo "$db_json" | jq --arg u "$username" '.users[$u].enabled = true | .users[$u].disabled_reason = null')"
        fi
        user_manager_commit_edit "$db_json" "$new_db" edit "$username" || true
        ;;
      2)
        if [ $is_admin -eq 1 ]; then
          warn "无效输入：$act"; sleep 1
        else
          new_db="$(user_manage_permission_menu "$db_json" "$username" "$json")" || new_db=""
          if json_is_object "$new_db"; then
            user_manager_commit_edit "$db_json" "$new_db" edit "$username" || true
          fi
        fi
        ;;
      3)
        new_db="$(user_manage_package_menu "$db_json" "$username")" || new_db=""
        if json_is_object "$new_db"; then
          user_manager_commit_edit "$db_json" "$new_db" edit "$username" || true
        fi
        ;;
      4)
        new_db="$(user_reset_usage_menu "$db_json" "$username")" || new_db=""
        if json_is_object "$new_db"; then
          user_manager_commit_edit "$db_json" "$new_db" reset "$username" || true
        fi
        ;;
      5)
        new_db="$(user_add_usage_menu "$db_json" "$username")" || new_db=""
        if json_is_object "$new_db"; then
          user_manager_commit_edit "$db_json" "$new_db" add "$username" || true
        fi
        ;;
      6)
        mode=edit
        if user_expire_is_past "$(user_today_date)" "$(echo "$db_json" | jq -r --arg u "$username" '.users[$u].expire_at // "0"')"; then mode=reset; fi
        new_db="$(user_renew_menu "$db_json" "$username")" || new_db=""
        if json_is_object "$new_db"; then
          user_manager_commit_edit "$db_json" "$new_db" "$mode" "$username" || true
        fi
        ;;
      0|q|Q|"") return 0 ;;
      *) warn "无效输入：$act"; sleep 1 ;;
    esac
  done
}

user_select_and_manage_menu() {
  local db_json usernames=() ans idx username
  db_json="$(user_db_load)"
  clear
  print_rect_title "管理用户"
  show_user_status_table "$db_json"
  mapfile -t usernames < <(user_db_all_users "$db_json")
  local i=1
  for username in "${usernames[@]}"; do
    echo " [$i] $username"
    i=$((i+1))
  done
  read -r -p "请选择用户（回车返回上一级）: " ans
  [ -z "${ans:-}" ] && return 0
  if ! [[ "$ans" =~ ^[0-9]+$ ]] || [ "$ans" -lt 1 ] || [ "$ans" -gt "${#usernames[@]}" ]; then
    warn "无效输入：$ans"
    pause
    return 1
  fi
  idx=$((ans-1))
  user_manage_single "${usernames[$idx]}"
}

user_delete_menu() {
  local db_json json usernames=() ans new_db picks=() part idx username
  db_json="$(user_db_load)"
  json="$(config_load)"
  clear
  print_rect_title "删除用户"
  show_user_status_table "$db_json"
  mapfile -t usernames < <(echo "$db_json" | jq -r '.users | keys[] | select(. != "admin")')
  if [ ${#usernames[@]} -eq 0 ]; then
    warn "当前没有可删除的普通用户。"
    pause
    return 0
  fi
  local i=1
  for username in "${usernames[@]}"; do
    echo " [$i] $username"
    i=$((i+1))
  done
  read -r -p "请选择要删除的用户（支持 1+2+3，回车返回上一级）: " ans
  [ -z "${ans:-}" ] && return 0
  mapfile -t picks < <(parse_plus_selections "$ans")
  [ ${#picks[@]} -eq 0 ] && { warn "未选择任何用户。"; pause; return 1; }

  local names_to_delete=()
  for part in "${picks[@]}"; do
    if ! [[ "$part" =~ ^[0-9]+$ ]] || [ "$part" -lt 1 ] || [ "$part" -gt "${#usernames[@]}" ]; then
      err "编号超出范围：$part"
      pause
      return 1
    fi
    names_to_delete+=("${usernames[$((part-1))]}")
  done

  echo "即将删除以下用户："
  for username in "${names_to_delete[@]}"; do
    echo "  - $username"
  done
  ask_confirm_yes "输入 YES 确认彻底删除，其它任意输入取消: " || { warn "已取消删除。"; pause; return 0; }

  new_db="$db_json"
  for username in "${names_to_delete[@]}"; do
    new_db="$(echo "$new_db" | jq --arg u "$username" 'del(.users[$u])')" || return 1
  done
  user_manager_commit_edit "$db_json" "$new_db" || true
  pause
}

user_manager_menu() {
  if ! user_db_exists; then
    init_manager_env || { pause; return 0; }
    # 自愈：6.1.5 安装事务把 ensure_user_manager_ready 失败改成 warn，
    # 这里给用户管理菜单一个"进入时重试创建"的机会，避免用户卡在死循环。
    ensure_user_manager_ready || {
      err "用户数据库初始化失败，请检查 $USER_DB_FILE 所在磁盘和权限后再试。"
      pause
      return 0
    }
  fi
  while true; do
    local db_json
    db_json="$(user_db_load)"
    clear
    print_rect_title "用户管理"
    show_user_status_table "$db_json"
    echo -e "  ${C}1.${NC} 新增用户"
    echo -e "  ${C}2.${NC} 管理用户"
    echo -e "  ${C}3.${NC} 删除用户"
    echo -e "  ${R}0.${NC} 返回主菜单"
    read -r -p "请选择操作: " act
    case "${act:-}" in
      1) user_add_menu || true ;;
      2) user_select_and_manage_menu || true ;;
      3) user_delete_menu || true ;;
      0|q|Q|"") return 0 ;;
      *) warn "无效输入：$act"; sleep 1 ;;
    esac
  done
}

# >>>>>>>>> END MODULE: 62_user_menu.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 70_export.sh <<<<<<<<<<<
# ============================================================
# 模块: 70_export.sh
# 职责: 客户端配置导出（链接生成 + 多格式输出）
# 依赖: 00_base.sh, 01_utils.sh, 10_config.sh, 20_protocol.sh,
#       30_route.sh, 50_v2ray_api.sh
# ============================================================

# ---------- 编码工具 ----------

b64_std_no_wrap() {
  printf '%s' "${1:-}" | openssl base64 -A 2>/dev/null | tr -d '\n'
}

url_encode() {
  printf '%s' "${1:-}" | jq -sRr @uri
}

# ---------- V2RayN 链接构建器（每协议一个函数） ----------

build_v2rayn_ss_link() {
  local server="$1" port="$2" method="$3" password="$4" name="$5"
  local userinfo enc
  userinfo="${method}:${password}"
  enc="$(b64_std_no_wrap "$userinfo")"
  printf 'ss://%s@%s:%s#%s' "$enc" "$server" "$port" "$(url_encode "$name")"
}

build_v2rayn_vmess_ws_link() {
  local server="$1" uuid="$2" host="$3" path="$4" name="$5"
  local payload enc
  payload="$(jq -nc \
    --arg ps "$name" \
    --arg add "$server" \
    --arg port "443" \
    --arg id "$uuid" \
    --arg aid "0" \
    --arg scy "auto" \
    --arg net "ws" \
    --arg type "none" \
    --arg host "$host" \
    --arg path "$path" \
    --arg tls "tls" \
    --arg sni "$host" \
    '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:$aid,scy:$scy,net:$net,type:$type,host:$host,path:$path,tls:$tls,sni:$sni}')"
  enc="$(b64_std_no_wrap "$payload")"
  printf 'vmess://%s' "$enc"
}

build_v2rayn_vless_reality_link() {
  local server="$1" port="$2" uuid="$3" sni="$4" pbk="$5" sid="$6" flow="$7" name="$8"
  printf 'vless://%s@%s:%s?encryption=none&flow=%s&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s' \
    "$uuid" "$server" "$port" \
    "$(url_encode "$flow")" \
    "$(url_encode "$sni")" \
    "$(url_encode "$pbk")" \
    "$(url_encode "$sid")" \
    "$(url_encode "$name")"
}

build_v2rayn_vless_ws_link() {
  local server="$1" uuid="$2" host="$3" path="$4" name="$5"
  printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&type=ws&host=%s&path=%s#%s' \
    "$uuid" "$server" \
    "$(url_encode "$host")" \
    "$(url_encode "$host")" \
    "$(url_encode "$path")" \
    "$(url_encode "$name")"
}

build_v2rayn_anytls_link() {
  local server="$1" port="$2" password="$3" sni="$4" name="$5"
  # password 不做 url_encode：AnyTLS 客户端（mihomo/QX）实际未对 userinfo 做
  # URL 解码，编码后的 %2B/%3D 会被当成字面字符导致密码不匹配。
  # base64 字符集（A-Za-z0-9+/=）在 URL userinfo 中无歧义，可直接使用。
  printf 'anytls://%s@%s:%s?sni=%s&fp=chrome&alpn=%s&allowInsecure=1#%s' \
    "$password" "$server" "$port" \
    "$(url_encode "$sni")" \
    "$(url_encode "h2,http/1.1")" \
    "$(url_encode "$name")"
}

build_v2rayn_trojan_link() {
  local server="$1" port="$2" password="$3" sni="$4" name="$5"
  printf 'trojan://%s@%s:%s?security=tls&sni=%s&alpn=%s&allowInsecure=1#%s' \
    "$(url_encode "$password")" "$server" "$port" \
    "$(url_encode "$sni")" \
    "$(url_encode "h2,http/1.1")" \
    "$(url_encode "$name")"
}

build_v2rayn_tuic_link() {
  local server="$1" port="$2" uuid="$3" password="$4" sni="$5" name="$6"
  printf 'tuic://%s:%s@%s:%s?sni=%s&alpn=%s&allow_insecure=1&congestion_control=bbr#%s' \
    "$uuid" "$(url_encode "$password")" "$server" "$port" \
    "$(url_encode "$sni")" \
    "$(url_encode "h3")" \
    "$(url_encode "$name")"
}

# ---------- 导出上下文收集 ----------

export_collect_context() {
  local json="$1"
  local ip ws_domain vm_domain inventory
  ip="$(get_public_ip)"
  ws_domain="example.com"
  vm_domain="example.com"
  inventory="$(protocol_entry_inventory "$json")"

  # 分隔符用 POSIX 八进制 \001 而非十六进制 \x01：busybox awk（Alpine 默认）
  # 不认 \xHH 转义，会把 '\x01' 当成字面量 x01，导致字段永不匹配。
  # 八进制写法 gawk / mawk / busybox awk 三者都支持。
  if printf '%s\n' "$inventory" | awk -F '\001' '$2 == "vless-ws" {found=1} END{exit !found}'; then
    read -r -p "请输入 vless-ws 域名（默认: example.com）: " ws_domain
    ws_domain="${ws_domain:-example.com}"
  fi
  if printf '%s\n' "$inventory" | awk -F '\001' '$2 == "vmess-ws" {found=1} END{exit !found}'; then
    read -r -p "请输入 vmess-ws 域名（默认: example.com）: " vm_domain
    vm_domain="${vm_domain:-example.com}"
  fi

  jq -n --arg ip "$ip" --arg wsd "$ws_domain" --arg vmd "$vm_domain" '{ip:$ip,ws_domain:$wsd,vm_domain:$vmd}'
}

# ---------- 主导出函数 ----------

export_configs() {
  init_manager_env || { pause; return 0; }
  clear
  local json ctx ip ws_domain vm_domain
  local tag proto port sni path sid method server_p
  local name uuid pass flow out_name pw_out target_file business_user safe_user reality_public_key v2rayn_link
  json="$(config_load)"
  ctx="$(export_collect_context "$json")"
  IFS=$'\x01' read -r ip ws_domain vm_domain < <(
    echo "$ctx" | jq -r '[.ip, .ws_domain, .vm_domain] | join("\u0001")'
  )

  echo -e "${C}--- 节点配置导出 ---${NC}"

  local direct_tmp user_dir
  direct_tmp="$(mktemp)"
  user_dir="$(mktemp -d)"
  _export_cleanup() {
    rm -rf "$user_dir" >/dev/null 2>&1 || true
    rm -f "$direct_tmp" >/dev/null 2>&1 || true
  }
  trap '_export_cleanup; trap - RETURN' RETURN

  while read -r inbound; do
    IFS=$'\x01' read -r tag proto port sni path sid method server_p < <(
      echo "$inbound" | jq -r "${JQ_DETECT_PROTOCOL}"'
        [(.tag // ""), detect_protocol, ((.listen_port // 0) | tostring),
         (.tls.server_name // "www.icloud.com"), (.transport.path // "/"),
         (.tls.reality.short_id[0] // ""), (.method // "2022-blake3-aes-128-gcm"),
         (.password // "")] | join("\u0001")
      '
    )

    while read -r user; do
      IFS=$'\x01' read -r name uuid pass flow < <(
        echo "$user" | jq -r '[(.name // .username // ""), (.uuid // ""), (.password // ""),
          (.flow // "xtls-rprx-vision")] | join("\u0001")'
      )
      [ -z "$name" ] && continue
      out_name="$name"

      if [[ "$name" == *"@"* ]]; then
        business_user="$(user_business_name "$name")"
        safe_user="$(printf '%s' "$business_user" | tr '/ ' '__')"
        target_file="${user_dir}/${safe_user}.tmp"
      else
        target_file="$direct_tmp"
      fi

      case "$proto" in
        vless-reality)
          [ -z "$uuid" ] && continue
          reality_public_key="$(meta_get_reality_public_key "$tag")"
          [ -n "$reality_public_key" ] || reality_public_key="PUBLIC_KEY_MISSING"
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " Clash: - {name: ${out_name}, type: vless, server: $ip, port: $port, uuid: $uuid, network: tcp, udp: true, tls: true, flow: ${flow}, servername: $sni, reality-opts: {public-key: $reality_public_key, short-id: '$sid'}, client-fingerprint: chrome}"
            echo ""
            echo -e " Quantumult X: vless=$ip:$port, method=none, password=$uuid, obfs=over-tls, obfs-host=$sni, reality-base64-pubkey=$reality_public_key, reality-hex-shortid=$sid, vless-flow=${flow}, udp-relay=true, tag=${out_name}"
            echo ""
            v2rayn_link="$(build_v2rayn_vless_reality_link "$ip" "$port" "$uuid" "$sni" "$reality_public_key" "$sid" "$flow" "$out_name")"
            echo -e " 通用链接: ${v2rayn_link}"
          } >> "$target_file"
          ;;
        anytls)
          [ -z "$pass" ] && continue
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " Clash: - {name: ${out_name}, type: anytls, server: $ip, port: $port, password: \"${pass}\", client-fingerprint: chrome, udp: true, sni: \"${sni}\", alpn: [h2, http/1.1], skip-cert-verify: true}"
            echo ""
            echo -e " Quantumult X: anytls=${ip}:${port}, password=${pass}, over-tls=true, tls-host=${sni}, udp-relay=true, tag=${out_name}"
            echo ""
            v2rayn_link="$(build_v2rayn_anytls_link "$ip" "$port" "$pass" "$sni" "$out_name")"
            echo -e " 通用链接: ${v2rayn_link}"
            echo ""
            echo -e " Surge: ${out_name} = anytls, ${ip}, ${port}, password=${pass}, skip-cert-verify=true, sni=${sni}"
          } >> "$target_file"
          ;;
        shadowsocks)
          [ -z "$pass" ] && continue
          if [ -n "$server_p" ]; then pw_out="${server_p}:${pass}"; else pw_out="$pass"; fi
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " Clash: - {name: \"${out_name}\", type: ss, server: $ip, port: ${port}, cipher: ${method}, password: \"${pw_out}\", udp: true}"
            echo ""
            echo -e " Quantumult X: shadowsocks=$ip:${port}, method=${method}, password=${pw_out}, udp-relay=true, tag=${out_name}"
            echo ""
            v2rayn_link="$(build_v2rayn_ss_link "$ip" "$port" "$method" "$pw_out" "$out_name")"
            echo -e " 通用链接: ${v2rayn_link}"
            echo ""
            echo -e " Surge: ${out_name} = ss, ${ip}, ${port}, encrypt-method=${method}, password=${pw_out}, udp-relay=true"
          } >> "$target_file"
          ;;
        trojan)
          [ -z "$pass" ] && continue
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " Clash: - {name: \"${out_name}\", type: trojan, server: $ip, port: ${port}, password: \"${pass}\", client-fingerprint: chrome, udp: true, sni: \"${sni}\", alpn: [h2, http/1.1], skip-cert-verify: true}"
            echo ""
            echo -e " Quantumult X: trojan=${ip}:${port}, password=${pass}, over-tls=true, tls-host=${sni}, tls-verification=false, fast-open=false, udp-relay=true, tag=${out_name}"
            echo ""
            v2rayn_link="$(build_v2rayn_trojan_link "$ip" "$port" "$pass" "$sni" "$out_name")"
            echo -e " 通用链接: ${v2rayn_link}"
            echo ""
            echo -e " Surge: ${out_name} = trojan, ${ip}, ${port}, password=${pass}, skip-cert-verify=true, sni=${sni}"
          } >> "$target_file"
          ;;
        vmess-ws)
          [ -z "$uuid" ] && continue
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " Clash: - {name: ${out_name}, type: vmess, server: $ip, port: 443, uuid: ${uuid}, alterId: 0, cipher: auto, udp: true, tls: true, network: ws, servername: ${vm_domain}, ws-opts: {path: \"${path}\", headers: {Host: ${vm_domain}}, max-early-data: 2048, early-data-header-name: Sec-WebSocket-Protocol}}"
            echo ""
            echo -e " Quantumult X: vmess=$ip:443, method=chacha20-poly1305, password=${uuid}, obfs=wss, obfs-host=${vm_domain}, obfs-uri=${path}?ed=2048, fast-open=false, udp-relay=true, tag=${out_name}"
            echo ""
            v2rayn_link="$(build_v2rayn_vmess_ws_link "$ip" "$uuid" "$vm_domain" "${path}?ed=2048" "$out_name")"
            echo -e " 通用链接: ${v2rayn_link}"
            echo ""
            echo -e " Surge: ${out_name} = vmess, ${ip}, 443, username=${uuid}, tls=true, vmess-aead=true, ws=true, ws-path=${path}?ed=2048, sni=${vm_domain}, ws-headers=Host:${vm_domain}, skip-cert-verify=false, udp-relay=true, tfo=false"
          } >> "$target_file"
          ;;
        vless-ws)
          [ -z "$uuid" ] && continue
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " Clash: - {name: ${out_name}, type: vless, server: $ip, port: 443, uuid: ${uuid}, udp: true, tls: true, network: ws, servername: ${ws_domain}, ws-opts: {path: \"${path}\", headers: {Host: ${ws_domain}}, max-early-data: 2048, early-data-header-name: Sec-WebSocket-Protocol}}"
            echo ""
            echo -e " Quantumult X: vless=$ip:443,method=none,password=${uuid},obfs=wss,obfs-host=${ws_domain},obfs-uri=${path}?ed=2048,fast-open=false,udp-relay=true,tag=${out_name}"
            echo ""
            v2rayn_link="$(build_v2rayn_vless_ws_link "$ip" "$uuid" "$ws_domain" "${path}?ed=2048" "$out_name")"
            echo -e " 通用链接: ${v2rayn_link}"
          } >> "$target_file"
          ;;
        tuic)
          [ -z "$uuid" ] && continue
          [ -z "$pass" ] && continue
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " Clash: - {name: ${out_name}, type: tuic, server: $ip, port: $port, uuid: $uuid, password: $pass, alpn: [h3], disable-sni: false, reduce-rtt: false, udp-relay-mode: native, congestion-controller: bbr, skip-cert-verify: true, sni: $sni}"
            echo ""
            v2rayn_link="$(build_v2rayn_tuic_link "$ip" "$port" "$uuid" "$pass" "$sni" "$out_name")"
            echo -e " 通用链接: ${v2rayn_link}"
            echo ""
            echo -e " Surge: ${out_name} = tuic-v5, ${ip}, ${port}, password=${pass}, sni=${sni}, uuid=${uuid}, alpn=h3, ecn=true"
          } >> "$target_file"
          ;;
        socks)
          [ -z "$name" ] && continue
          [ -z "$pass" ] && continue
          {
            echo -e "\n${W}[${out_name}]${NC}"
            echo -e " 参数: server=${ip}  port=${port}  username=${name}  password=${pass}"
          } >> "$target_file"
          ;;
      esac
    done < <(echo "$inbound" | jq -c '.users[]?')
  done < <(echo "$json" | jq -c "${JQ_PROTOCOL_SORT}"'[.inbounds[]?] | sort_by(protocol_sort_index(.tag // "")) | .[]')

  echo -e "\n${C}直连节点${NC}"
  if [ -s "$direct_tmp" ]; then
    cat "$direct_tmp"
  else
    echo -e "  ${Y}当前没有直连节点。${NC}"
  fi

  local user_file printed=0 user_name
  while IFS= read -r -d '' user_file; do
    printed=1
    user_name="$(basename "$user_file" .tmp)"
    echo -e "\n${C}${user_name}节点${NC}"
    cat "$user_file"
  done < <(find "$user_dir" -maxdepth 1 -type f -name '*.tmp' -print0 | sort -z)

  if [ "$printed" -eq 0 ]; then
    echo -e "\n${C}用户节点${NC}"
    echo -e "  ${Y}当前没有用户节点。${NC}"
  fi

  echo ""
  pause
}

# >>>>>>>>> END MODULE: 70_export.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 80_installer.sh <<<<<<<<<<<
# ============================================================
# 模块: 80_installer.sh
# 职责: sing-box 安装/更新/卸载、systemd 服务、cron、系统工具
# 依赖: 00_base.sh, 01_utils.sh, 10_config.sh, 50_v2ray_api.sh
# ============================================================

# ---------- 依赖安装 ----------

ensure_deps_for_installer() {
  require_root
  [ "$PKG_MANAGER" = "unknown" ] && { err "未找到受支持的包管理器（apt-get 或 apk）。"; exit 1; }
  say "安装必要依赖..."
  local _PKG_INSTALL_QUIET=1
  install_pkg curl
  install_pkg jq
  install_pkg openssl
  install_pkg tar
  # bash 是本脚本的硬依赖：Alpine / 极简系统默认只有 busybox ash。
  # 引导段（00_base.sh 顶部）已尝试装过一次，这里兜底确保后续能正常升级。
  install_pkg bash || true
  case "$PKG_MANAGER" in
    apt)
      install_pkg ca-certificates; install_pkg gnupg; install_pkg gzip; install_pkg util-linux
      ;;
    apk)
      install_pkg ca-certificates
      install_pkg gcompat
      # flock 在不同 Alpine 版本里可能由独立包或 util-linux 提供，
      # 两者都失败时不阻断安装（缺少会被 with_manager_lock 拦下并提示）。
      install_pkg flock || install_pkg util-linux || true
      ;;
  esac
}

version_ge() {
  # version_ge A B → true if A >= B
  local a="${1#v}" b="${2#v}"
  if sort -V </dev/null >/dev/null 2>&1; then
    [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" = "$b" ]
    return $?
  fi
  awk -v a="$a" -v b="$b" '
    function clean(v) { sub(/[-+].*/, "", v); return v }
    BEGIN {
      split(clean(a), av, ".")
      split(clean(b), bv, ".")
      for (i = 1; i <= 4; i++) {
        ai = av[i] + 0
        bi = bv[i] + 0
        if (ai > bi) exit 0
        if (ai < bi) exit 1
      }
      exit 0
    }
  '
}

ensure_sagernet_repo() { :; }

# ---------- 版本管理 ----------

get_release_latest_tag() {
  local repo="${SINGBOX_RELEASE_REPO:-Tangfffyx/sing-box}"
  curl -fsSL --connect-timeout 10 --max-time 20 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty'
}

normalize_release_tag() {
  local v="${1:-}"
  v="${v#v}"
  echo "$v"
}

# 远端版本缓存：菜单摘要只读这个文件，永不发起网络请求，避免阻塞交互。
# 写入由后台 cron 和安装/更新流程负责。
refresh_upstream_tag_cache() {
  local tag="${1:-}"
  if [ -z "$tag" ]; then
    tag="$(get_release_latest_tag)"
  fi
  [ -n "$tag" ] || return 1
  mkdir -p "$(dirname "$UPSTREAM_TAG_CACHE_FILE")" >/dev/null 2>&1 || true
  local now tmp
  now="$(date +%s)"
  tmp="${UPSTREAM_TAG_CACHE_FILE}.tmp.$$"
  if jq -nc --arg tag "$tag" --argjson now "$now" '{tag:$tag, fetched_at:$now}' > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$UPSTREAM_TAG_CACHE_FILE" || { rm -f "$tmp"; return 1; }
    return 0
  fi
  rm -f "$tmp" >/dev/null 2>&1 || true
  return 1
}

# 读缓存中的 upstream 版本号（已 strip "v" 前缀）。
# 缓存不存在或过期返回空字符串，调用方据此显示"未知"。
get_cached_upstream_version() {
  [ -s "$UPSTREAM_TAG_CACHE_FILE" ] || return 0
  local now fetched age tag
  now="$(date +%s)"
  fetched="$(jq -r '.fetched_at // 0' "$UPSTREAM_TAG_CACHE_FILE" 2>/dev/null || echo 0)"
  [[ "$fetched" =~ ^[0-9]+$ ]] || fetched=0
  age=$((now - fetched))
  [ "$age" -le "$UPSTREAM_TAG_CACHE_MAX_AGE_SECS" ] || return 0
  tag="$(jq -r '.tag // ""' "$UPSTREAM_TAG_CACHE_FILE" 2>/dev/null || true)"
  [ -n "$tag" ] || return 0
  normalize_release_tag "$tag"
}

get_candidate_version() {
  normalize_release_tag "$(get_release_latest_tag)"
}

get_installed_version() {
  local stamp ver
  if [ -s "$SINGBOX_VERSION_STAMP" ]; then
    stamp="$(cat "$SINGBOX_VERSION_STAMP" 2>/dev/null || true)"
    stamp="${stamp#v}"
    [ -n "$stamp" ] && { echo "$stamp"; return 0; }
  fi
  if [ -x "$SINGBOX_BIN" ]; then
    ver="$("$SINGBOX_BIN" version 2>/dev/null | awk '/^sing-box version / {print $3; exit}')"
    ver="${ver#v}"
    [ "$ver" != "unknown" ] && [ -n "$ver" ] && { echo "$ver"; return 0; }
  fi
  echo ""
}

show_versions() {
  local inst cand
  inst="$(get_installed_version)"
  cand="$(get_candidate_version)"
  echo -e "${W}-------- 版本信息 --------${NC}"
  echo -e " 当前版本 : ${inst:-未安装}"
  echo -e " 最新版本 : ${cand:-无}"
  echo -e "${W}--------------------------${NC}"
}

# 完整性探针：所有关键组件都就位才算真正装好
# 用于区分"版本号匹配"与"组件齐全"，避免半完成状态被误判为已安装
is_install_complete() {
  [ -x "$SINGBOX_BIN" ] || return 1
  [ -s "$SINGBOX_VERSION_STAMP" ] || return 1
  user_db_exists || return 1
  _cron_job_installed "$PERIODIC_SYNC_CRON_MARK" || return 1
  _cron_job_installed "$DAILY_MAINTENANCE_CRON_MARK" || return 1
  # 6.0.8 及以前的老 cron 残留也算"组件不一致"，引导用户清理。
  ! _cron_job_installed "$USER_WATCH_CRON_MARK" || return 1
  ! _cron_job_installed "$LOG_MAINTAIN_CRON_MARK" || return 1
  # TG 功能已移除，但旧版本装过的 cron 仍要能识别并清理，故用字面量而非已删除的变量。
  ! _cron_job_installed "sb.sh --tg-agent-sync" || return 1
  ! _cron_job_installed "$UPSTREAM_REFRESH_CRON_MARK" || return 1
  singbox_service_active || return 1
  return 0
}

# ---------- 脚本自身管理 ----------

resolve_current_script_file() {
  local current="${SCRIPT_SELF:-${BASH_SOURCE[0]:-$0}}"
  local fd_path
  if [[ "$0" == /dev/fd/* ]] || [[ "$0" == /proc/self/fd/* ]] || [[ "$current" == /dev/fd/* ]] || [[ "$current" == /proc/self/fd/* ]]; then
    fd_path="$(readlink -f "$current" 2>/dev/null || true)"
    [ -n "$fd_path" ] && [ -r "$fd_path" ] && { echo "$fd_path"; return 0; }
    return 1
  fi
  current="$(readlink -f "$current" 2>/dev/null || echo "$current")"
  [ -r "$current" ] || return 1
  echo "$current"
}

write_local_script_entrypoint() {
  mkdir -p /usr/local/bin
  local source_file
  source_file="$(resolve_current_script_file)" || {
    warn "快捷命令 s 安装失败：无法读取当前脚本。"
    return 1
  }
  if [ "$source_file" != "$SB_TARGET_SCRIPT" ]; then
    cp -f "$source_file" "$SB_TARGET_SCRIPT" || {
      warn "快捷命令 s 安装失败：无法写入 $SB_TARGET_SCRIPT"
      return 1
    }
  fi
  chmod +x "$SB_TARGET_SCRIPT" >/dev/null 2>&1 || true
  install_sb_shortcut
}

install_sb_shortcut() {
  cat > "$SB_SHORTCUT" <<'EOF2'
#!/bin/sh
exec bash /root/sb.sh "$@"
EOF2
  chmod +x "$SB_SHORTCUT" >/dev/null 2>&1 || true
}

ensure_local_script_entrypoint_once() {
  [ -s "$SB_TARGET_SCRIPT" ] && [ -x "$SB_SHORTCUT" ] && return 0
  write_local_script_entrypoint >/dev/null 2>&1 || true
}

ensure_sb_shortcut() {
  write_local_script_entrypoint
}

# ---------- 日志维护 ----------

maintain_script_log_file() {
  local log_file="${1:-$SCRIPT_LOG_FILE}" max_bytes="${2:-$LOG_MAX_BYTES}"
  [ -n "$log_file" ] || return 0
  [ -f "$log_file" ] || return 0
  [ -s "$log_file" ] || return 0

  local size tmp
  size="$(wc -c < "$log_file" 2>/dev/null || echo 0)"
  [[ "$size" =~ ^[0-9]+$ ]] || size=0
  [ "$size" -le "$max_bytes" ] && return 0

  tmp="$(mktemp)"
  tail -c "$max_bytes" "$log_file" > "$tmp" 2>/dev/null || {
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  }
  cat "$tmp" > "$log_file"
  rm -f "$tmp" >/dev/null 2>&1 || true
  return 0
}

maintain_logs() {
  maintain_script_log_file "$SCRIPT_LOG_FILE" "$LOG_MAX_BYTES" || true
  return 0
}

config_force_access_log_settings() {
  [ -s "$CONFIG_FILE" ] || return 0
  mkdir -p /var/log/sing-box >/dev/null 2>&1 || true
  local json updated
  json="$(config_load)" || return 1
  updated="$(echo "$json" | jq '.log = (.log // {}) | .log.level = "info" | .log.output = "/var/log/sing-box/access.log" | .log.timestamp = true')" || return 1
  config_apply "$updated" || return 1
}

# ---------- Cron 管理 ----------

_cron_job_match_pattern() {
  local mark="$1"
  case "$mark" in
    "$USER_WATCH_CRON_MARK") echo "--user-watch" ;;
    "$LOG_MAINTAIN_CRON_MARK") echo "--maintain-logs" ;;
    "sb.sh --tg-agent-sync") echo "--tg-agent-sync" ;;
    "$UPSTREAM_REFRESH_CRON_MARK") echo "--refresh-upstream" ;;
    "$PERIODIC_SYNC_CRON_MARK") echo "--periodic-sync" ;;
    "$DAILY_MAINTENANCE_CRON_MARK") echo "--daily-maintenance" ;;
    *) echo "$mark" ;;
  esac
}

_cron_job_installed() {
  local mark="$1" pattern
  has_cmd crontab || return 1
  pattern="$(_cron_job_match_pattern "$mark")"
  crontab -l 2>/dev/null | awk -v p="$pattern" '
    /^[[:space:]]*#/ { next }
    index($0, p) { found=1 }
    END { exit !found }
  '
}

_crond_daemon_active() {
  case "$INIT_SYSTEM" in
    systemd)
      systemctl is-active --quiet crond 2>/dev/null || systemctl is-active --quiet cron 2>/dev/null
      ;;
    openrc)
      rc-service crond status >/dev/null 2>&1 || rc-service cron status >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

_ensure_crond_running() {
  # 1. 确保 crontab 命令可用，不可用时按包管理器装对应包
  if ! has_cmd crontab; then
    case "$PKG_MANAGER" in
      apt) install_pkg cron 2>/dev/null || install_pkg cronie 2>/dev/null || return 1 ;;
      apk) install_pkg cronie 2>/dev/null || install_pkg dcron 2>/dev/null || return 1 ;;
      *) return 1 ;;
    esac
  fi

  # 2. 已运行直接通过
  _crond_daemon_active && return 0

  # 3. 启动 daemon（systemd / openrc 兼容 crond 和 cron 两种服务名）
  case "$INIT_SYSTEM" in
    systemd)
      systemctl start crond >/dev/null 2>&1 || systemctl start cron >/dev/null 2>&1 || true
      systemctl enable crond >/dev/null 2>&1 || systemctl enable cron >/dev/null 2>&1 || true
      ;;
    openrc)
      rc-service crond start >/dev/null 2>&1 || rc-service cron start >/dev/null 2>&1 || true
      rc-update add crond default >/dev/null 2>&1 || rc-update add cron default >/dev/null 2>&1 || true
      ;;
    *) return 1 ;;
  esac

  # 4. 等待 daemon 稳定后再次验证
  sleep 1
  _crond_daemon_active
}

cron_job_status_line() {
  local label="$1" mark="$2"
  local installed daemon_state
  if _cron_job_installed "$mark"; then
    installed="${G}已安装${NC}"
  else
    installed="${R}未安装${NC}"
  fi
  if _crond_daemon_active; then
    daemon_state="${G}运行中${NC}"
  else
    daemon_state="${R}未运行${NC}"
  fi
  printf '  %b%s%b : %b  定时服务 %b\n' "$W" "$label" "$NC" "$installed" "$daemon_state"
}

_install_cron_job() {
  local mark="$1" schedule="$2" cmd="$3"
  # 先让 _ensure_crond_running 负责装 cron 包 + 启动 daemon
  _ensure_crond_running || { err "cron 服务不可用（未能自动安装或启动 crond）。"; return 1; }
  # 到这里 crontab 命令必然可用（_ensure_crond_running 会主动安装）
  local tmp pattern
  pattern="$(_cron_job_match_pattern "$mark")"
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | awk -v p="$pattern" 'index($0, p) == 0 { print }' > "$tmp" || true
  echo "${schedule} ${cmd} >/dev/null 2>&1" >> "$tmp"
  crontab "$tmp" || { rm -f "$tmp"; err "crontab 写入失败。"; return 1; }
  rm -f "$tmp"
  _cron_job_installed "$mark" || { err "crontab 写入后验证失败：未找到 mark $mark"; return 1; }
  return 0
}

_remove_cron_job() {
  local mark="$1"
  has_cmd crontab || return 0
  local tmp pattern
  pattern="$(_cron_job_match_pattern "$mark")"
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | awk -v p="$pattern" 'index($0, p) == 0 { print }' > "$tmp" || true
  if [ -s "$tmp" ]; then
    crontab "$tmp"
  else
    crontab -r 2>/dev/null || true
  fi
  rm -f "$tmp"
}

install_log_maintain_cron() { _install_cron_job "$LOG_MAINTAIN_CRON_MARK" "$LOG_MAINTAIN_CRON_SCHEDULE" "bash ${SB_TARGET_SCRIPT} --maintain-logs"; }
remove_log_maintain_cron()  { _remove_cron_job "$LOG_MAINTAIN_CRON_MARK"; }
install_user_watch_cron()   { _install_cron_job "$USER_WATCH_CRON_MARK" "$USER_WATCH_CRON_SCHEDULE" "bash ${SB_TARGET_SCRIPT} --user-watch"; }
remove_user_watch_cron()    { _remove_cron_job "$USER_WATCH_CRON_MARK"; }
install_upstream_refresh_cron() { _install_cron_job "$UPSTREAM_REFRESH_CRON_MARK" "$UPSTREAM_REFRESH_CRON_SCHEDULE" "bash ${SB_TARGET_SCRIPT} --refresh-upstream"; }
remove_upstream_refresh_cron()  { _remove_cron_job "$UPSTREAM_REFRESH_CRON_MARK"; }
install_periodic_sync_cron()    { _install_cron_job "$PERIODIC_SYNC_CRON_MARK" "$PERIODIC_SYNC_CRON_SCHEDULE" "bash ${SB_TARGET_SCRIPT} --periodic-sync"; }
remove_periodic_sync_cron()     { _remove_cron_job "$PERIODIC_SYNC_CRON_MARK"; }
install_daily_maintenance_cron(){ _install_cron_job "$DAILY_MAINTENANCE_CRON_MARK" "$DAILY_MAINTENANCE_CRON_SCHEDULE" "bash ${SB_TARGET_SCRIPT} --daily-maintenance"; }
remove_daily_maintenance_cron() { _remove_cron_job "$DAILY_MAINTENANCE_CRON_MARK"; }

# ---------- 旧版 Telegram 组件清理（TG 模块已移除） ----------
# 保留字面量：这些常量在本版本已删除，但旧版本装过的 cron / systemd 单元 /
# python 脚本仍可能留在机器上，升级时必须清掉，否则会每分钟拉起一个
# 已经不存在的入口（墓志铭 exit 0 会让它空跑，但仍然浪费 fork 与内存）。
remove_legacy_tg_cron() {
  _remove_cron_job "sb.sh --tg-agent-sync" >/dev/null 2>&1 || true
}

cleanup_legacy_tg_service() {
  local unit="/etc/systemd/system/sb-tg-bot.service"
  case "$INIT_SYSTEM" in
    systemd)
      systemctl stop sb-tg-bot >/dev/null 2>&1 || true
      systemctl disable sb-tg-bot >/dev/null 2>&1 || true
      rm -f "$unit" /usr/lib/systemd/system/sb-tg-bot.service >/dev/null 2>&1 || true
      systemctl daemon-reload >/dev/null 2>&1 || true
      ;;
    openrc)
      openrc_stop_service sb-tg-bot >/dev/null 2>&1 || true
      rm -f /etc/init.d/sb-tg-bot >/dev/null 2>&1 || true
      ;;
    *)
      rm -f "$unit" >/dev/null 2>&1 || true
      ;;
  esac
}

# 6.0.9 起合并定时任务的执行入口。
# periodic-sync：跑 user_watch（到期/配额巡检）。
# daily-maintenance：本地凌晨一次，跑 log 截尾 + 上游版本号刷新缓存。
# 两个 runner 内部都用 `|| true` 隔离故障，避免一步挂导致另一步不跑。
periodic_sync_run() {
  user_watch_run || true
}

daily_maintenance_run() {
  maintain_logs || true
  refresh_upstream_tag_cache >/dev/null 2>&1 || true
}

# ---------- 服务管理（systemd / OpenRC） ----------

remove_all_singbox_service_units() {
  case "$INIT_SYSTEM" in
    systemd)
      systemctl stop sing-box >/dev/null 2>&1 || true
      systemctl disable sing-box >/dev/null 2>&1 || true
      rm -f /etc/systemd/system/sing-box.service \
            /usr/lib/systemd/system/sing-box.service \
            /lib/systemd/system/sing-box.service >/dev/null 2>&1 || true
      systemctl daemon-reload >/dev/null 2>&1 || true
      ;;
    openrc)
      if openrc_service_exists sing-box; then
        openrc_stop_service sing-box >/dev/null 2>&1 || true
      fi
      openrc_disable_service sing-box default >/dev/null 2>&1 || true
      find /etc/runlevels -type l -name sing-box -exec rm -f {} + 2>/dev/null || true
      rm -f /etc/init.d/sing-box >/dev/null 2>&1 || true
      ;;
  esac
}

write_managed_singbox_service() {
  mkdir -p /var/lib/sing-box /etc/sing-box
  case "$INIT_SYSTEM" in
    systemd)
      mkdir -p /etc/systemd/system
      cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SINGBOX_BIN} -D /var/lib/sing-box -c ${CONFIG_FILE} run
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
# ---- 低内存 VPS 适配（128MB 可用）----
# GOMEMLIMIT 让 Go 运行时在接近上限时主动放弃内存换 CPU，而不是等被 OOM
# killer 杀掉。设 48MiB：128MB 机器要留出内核、ssh、cron 和 shell 的余量。
# GOGC=50 降低堆增长目标，进一步压低峰值（代价是 GC 更频繁、CPU 略增）。
# 若你的机器内存更大，可把 GOMEMLIMIT 调到总内存的 40%~50%。
Environment=GOMEMLIMIT=48MiB
Environment=GOGC=50
# 内存吃紧时优先保内核进程：被 swap 掉也比被 OOM 杀掉好。
# 注意 MemoryMax 是硬上限，触发会直接 SIGKILL，故不设置，避免压测时误杀。
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
      ;;
    openrc)
      cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
description="sing-box service"
command="${SINGBOX_BIN}"
command_args="-D /var/lib/sing-box -c ${CONFIG_FILE} run"
command_background=true
pidfile="/run/sing-box.pid"
# 低内存 VPS 适配（128MB 可用）：限制 Go 运行时堆上限并提高 GC 频率，
# 与 systemd 单元的 GOMEMLIMIT / GOGC 保持一致。
export GOMEMLIMIT="48MiB"
export GOGC="50"
depend() {
  need net
  after firewall
}
EOF
      chmod +x /etc/init.d/sing-box
      ;;
  esac
}

ensure_command_compat_links() {
  mkdir -p /usr/bin
  ln -sf "${SINGBOX_BIN}" /usr/bin/sing-box
}

migrate_legacy_script_name() {
  if [ -f /root/sing-box.sh ]; then
    rm -f /root/sing-box.sh
  fi
  if has_cmd crontab; then
    local tmp
    tmp="$(mktemp)"
    crontab -l 2>/dev/null | grep -v 'sing-box\.sh --user-watch\|sing-box\.sh --maintain-logs' > "$tmp" || true
    if [ -s "$tmp" ]; then
      crontab "$tmp"
    fi
    rm -f "$tmp"
  fi
}

is_script_managed_environment() {
  case "$INIT_SYSTEM" in
    systemd)
      [ -f /etc/systemd/system/sing-box.service ] || return 1
      grep -Fq "ExecStart=${SINGBOX_BIN} -D /var/lib/sing-box -c /etc/sing-box/config.json run" /etc/systemd/system/sing-box.service 2>/dev/null || return 1
      ;;
    openrc)
      [ -f /etc/init.d/sing-box ] || return 1
      grep -Fq "${SINGBOX_BIN}" /etc/init.d/sing-box 2>/dev/null || return 1
      ;;
    *) return 1 ;;
  esac
  [ -f /usr/local/bin/s ] && grep -Fq 'exec bash /root/sb.sh "$@"' /usr/local/bin/s 2>/dev/null || return 1
  return 0
}

refresh_command_cache() {
  hash -r 2>/dev/null || true
}

singbox_command_exists() {
  refresh_command_cache
  command -v sing-box >/dev/null 2>&1
}

prepare_script_runtime() {
  migrate_legacy_script_name || return 1
  write_managed_singbox_service || return 1
  ensure_command_compat_links || return 1
  mkdir -p /var/log/sing-box || return 1
  if [ "$INIT_SYSTEM" = "systemd" ]; then systemctl daemon-reload || return 1; fi
  return 0
}

# ---------- 安装/更新 sing-box ----------

install_or_update_singbox() {
  clear
  print_rect_title "sing-box 安装/更新"

  ensure_deps_for_installer

  local arch file tag latest_ver inst ans tmp_dir base_url download_url sha_url managed_env
  arch="$(uname -m)"
  case "$arch" in
    x86_64) file="sing-box-linux-amd64.tar.gz" ;;
    aarch64|arm64) file="sing-box-linux-arm64.tar.gz" ;;
    *)
      err "不支持的架构：$arch"
      pause
      return 1
      ;;
  esac

  tag="$(get_release_latest_tag)"
  latest_ver="$(normalize_release_tag "$tag")"

  refresh_command_cache
  managed_env="0"
  inst=""
  if is_script_managed_environment; then
    managed_env="1"
    inst="$(get_installed_version)"
  fi

  if [ -z "${latest_ver:-}" ]; then
    err "未获取到 GitHub Release 最新版本。"
    pause
    return 1
  fi

  if [ "${managed_env}" != "1" ] && singbox_command_exists; then
    warn "检测到已有非本脚本安装的 sing-box 环境，请先执行“卸载 sing-box”后再安装。"
    pause >&2
    return 0
  fi

  if [ "${managed_env}" = "1" ]; then
    echo -e "当前版本：${G}${inst:-未知}${NC}"
    echo -e "最新版本：${G}${latest_ver}${NC}"
    if [ -n "${inst:-}" ] && version_ge "$inst" "$latest_ver"; then
      if is_install_complete; then
        config_apply "$(config_load)" || { pause; return 1; }
        ok "当前已是最新版本。"
        pause
        return 0
      fi
      warn "版本号匹配但部分组件缺失。"
      read -r -p "是否重新安装以补齐组件？[Y/n]: " ans
      case "${ans:-Y}" in
        [Nn]*) return 0 ;;
      esac
    elif [ -n "${inst:-}" ]; then
      read -r -p "检测到新版本，是否升级？[Y/n]: " ans
      case "${ans:-Y}" in
        [Nn]*) return 0 ;;
      esac
    else
      echo -e "当前状态：${Y}本脚本环境，但未识别到已安装版本${NC}"
      echo -e "将安装版本：${G}${latest_ver}${NC}"
    fi
  else
    echo -e "当前状态：${Y}未安装 sing-box${NC}"
    echo -e "将安装版本：${G}${latest_ver}${NC}"
  fi

  if [ "${managed_env}" = "1" ] && [ -x "$SINGBOX_BIN" ]; then
    sync_user_usage_counters || { pause; return 1; }
  fi

  tmp_dir="$(make_disk_tmp_dir sb-install)" || {
    err "创建临时目录失败。"
    pause
    return 1
  }
  base_url="https://github.com/${SINGBOX_RELEASE_REPO:-Tangfffyx/sing-box}/releases/download/${tag}"
  download_url="${base_url}/${file}"
  sha_url="${base_url}/sha256sum.txt"

  say "下载 sing-box..."
  if ! download_file "$download_url" "$tmp_dir/$file" 20 3; then
    rm -rf "$tmp_dir"
    err "下载失败，请检查网络或稍后重试。"
    pause
    return 1
  fi

  if curl -fsSL --connect-timeout 20 --retry 3 "$sha_url" -o "$tmp_dir/sha256sum.txt" >/dev/null 2>&1; then
    expected_sha="$(awk -v f="$file" '{n=$2; sub(/^.*\//,"",n); if (n==f) {print $1; exit}}' "$tmp_dir/sha256sum.txt")"
    actual_sha="$(sha256sum "$tmp_dir/$file" | awk '{print $1}')"
    if [ -z "$expected_sha" ] || [ "$expected_sha" != "$actual_sha" ]; then
      rm -rf "$tmp_dir"
      err "校验失败。"
      pause
      return 1
    fi
  else
    warn "未获取到校验文件。"
    if ! ask_confirm_yes "输入 YES 确认跳过校验继续安装，其它任意输入取消: "; then
      rm -rf "$tmp_dir"
      err "已取消安装。"
      pause
      return 1
    fi
  fi

  tar -xzf "$tmp_dir/$file" -C "$tmp_dir" || {
    rm -rf "$tmp_dir"
    err "解压失败。"
    pause
    return 1
  }

  [ -f "$tmp_dir/sing-box" ] || {
    rm -rf "$tmp_dir"
    err "安装包中未找到 sing-box 可执行文件。"
    pause
    return 1
  }

  # staging 验证：在替换正式位置之前先验证 with_v2ray_api，避免坏二进制进入 $SINGBOX_BIN
  chmod +x "$tmp_dir/sing-box" 2>/dev/null || true
  if ! "$tmp_dir/sing-box" version 2>/dev/null | grep -q 'with_v2ray_api'; then
    rm -rf "$tmp_dir"
    err "下载的 sing-box 未检测到 with_v2ray_api。"
    if [ "$PKG_MANAGER" = "apk" ]; then
      warn "Alpine 环境提示：若报 'cannot execute' 错误，请手动执行：apk add gcompat"
    fi
    pause
    return 1
  fi

  if ! ensure_grpcurl_logged || ! ensure_v2ray_api_proto_files; then
    rm -rf "$tmp_dir"
    err "统计组件未就绪，已取消升级。"
    pause
    return 1
  fi
  if ! with_manager_lock install_candidate_singbox "$tmp_dir/sing-box" "$tag"; then
    rm -rf "$tmp_dir"
    pause
    return 1
  fi
  rm -rf "$tmp_dir"
  # 内核事务已提交；可重试的菜单/cron 初始化不影响已验证的内核。
  ensure_sb_shortcut || true
  ensure_user_manager_ready || warn "用户数据库初始化失败，用户管理菜单进入时会重试初始化。"
  install_periodic_sync_cron || warn "cron 定时任务安装失败：实时同步（环境: ${PKG_MANAGER}/${INIT_SYSTEM}）。is_install_complete 探针会引导后续修复。"
  install_daily_maintenance_cron || warn "cron 定时任务安装失败：日常维护（环境: ${PKG_MANAGER}/${INIT_SYSTEM}）。is_install_complete 探针会引导后续修复。"
  # 清理 6.0.8 及以前残留的老 cron（墓志铭入口让它们不出错，但应清掉避免无意义触发）
  remove_user_watch_cron || true
  remove_log_maintain_cron || true
  remove_legacy_tg_cron || true
  remove_upstream_refresh_cron || true
  refresh_upstream_tag_cache "$tag" >/dev/null 2>&1 || true
  user_manager_background_sync || warn "用户管理后台同步初始化失败。下次 periodic-sync cron 会重试。"

  ok "安装完成。"
  pause
}

# 调用方持管理锁。候选文件在正式路径之外完成校验；保留最近一次成功版本。
install_candidate_singbox() {
  local candidate="$1" tag="$2" next_config old_config next_bin old_bin stamp_tmp had_config=0 had_bin=0
  mkdir -p "$SINGBOX_INSTALL_DIR" "$(dirname "$CONFIG_FILE")" || return 1
  if [ -e "$CONFIG_FILE" ]; then
    jq -e 'type == "object"' "$CONFIG_FILE" >/dev/null || { err "现有配置无效，已取消升级。"; return 1; }
    had_config=1
  fi
  next_config="$(mktemp "${CONFIG_FILE}.upgrade.XXXXXX")" || return 1
  if [ "$had_config" = 1 ]; then
    config_normalize "$(cat "$CONFIG_FILE")" > "$next_config" || { rm -f "$next_config"; return 1; }
  else
    config_normalize "$(config_min_template)" > "$next_config" || { rm -f "$next_config"; return 1; }
  fi
  if ! "$candidate" check -c "$next_config"; then
    rm -f "$next_config"
    err "新内核不接受当前配置，正式文件未替换。"
    return 1
  fi
  sync_user_usage_counters || { rm -f "$next_config"; return 1; }
  old_config="$(mktemp "${CONFIG_FILE}.rollback.XXXXXX")" || { rm -f "$next_config"; return 1; }
  if [ "$had_config" = 1 ]; then
    cp -p "$CONFIG_FILE" "$old_config" || { rm -f "$old_config" "$next_config"; return 1; }
  fi
  next_bin="$(mktemp "${SINGBOX_BIN}.new.XXXXXX")" || { rm -f "$old_config" "$next_config"; return 1; }
  old_bin="$(mktemp "${SINGBOX_BIN}.rollback.XXXXXX")" || { rm -f "$next_bin" "$old_config" "$next_config"; return 1; }
  if [ -x "$SINGBOX_BIN" ]; then
    had_bin=1
    cp -p "$SINGBOX_BIN" "$old_bin" || { rm -f "$old_bin" "$next_bin" "$old_config" "$next_config"; return 1; }
  fi
  if ! install -m 755 "$candidate" "$next_bin"; then
    rm -f "$old_bin" "$next_bin" "$old_config" "$next_config"
    return 1
  fi
  stamp_tmp="$(mktemp "${SINGBOX_VERSION_STAMP}.tmp.XXXXXX")" || {
    rm -f "$old_bin" "$next_bin" "$old_config" "$next_config"; return 1;
  }
  if ! printf '%s\n' "$tag" > "$stamp_tmp"; then
    rm -f "$stamp_tmp" "$old_bin" "$next_bin" "$old_config" "$next_config"; return 1
  fi
  if mv -f "$next_bin" "$SINGBOX_BIN" && mv -f "$next_config" "$CONFIG_FILE" &&
      prepare_script_runtime && _RESTART_SINGBOX_QUIET_OK=1 reload_or_restart_singbox_safe &&
      mv -f "$stamp_tmp" "$SINGBOX_VERSION_STAMP"; then
    if [ "$had_bin" = 1 ]; then
      mv -f "$old_bin" "${SINGBOX_BIN}.bak" || warn "旧内核保留于 $old_bin"
    else
      rm -f "$old_bin"
    fi
    if [ "$had_config" = 1 ]; then
      mv -f "$old_config" "${CONFIG_FILE}.bak.upgrade" || warn "旧配置保留于 $old_config"
    else
      rm -f "$old_config"
    fi
    case "$INIT_SYSTEM" in
      systemd) systemctl enable sing-box >/dev/null 2>&1 || warn "设置自启失败。" ;;
      openrc) openrc_enable_service sing-box default >/dev/null 2>&1 || warn "设置自启失败。" ;;
    esac
    return 0
  fi
  err "升级未通过运行检查，正在恢复旧内核及配置。"
  rm -f "$next_bin" "$next_config" "$stamp_tmp"
  if [ "$had_config" = 1 ]; then
    mv -f "$old_config" "$CONFIG_FILE" || { err "配置回滚失败，备份：$old_config"; return 1; }
  else
    rm -f "$CONFIG_FILE" "$old_config"
  fi
  if [ "$had_bin" = 1 ]; then
    mv -f "$old_bin" "$SINGBOX_BIN" || { err "内核回滚失败，备份：$old_bin"; return 1; }
    _RESTART_SINGBOX_QUIET_OK=1 reload_or_restart_singbox_safe || err "旧内核恢复后启动失败，请检查服务日志。"
  else
    case "$INIT_SYSTEM" in
      systemd) systemctl stop sing-box >/dev/null 2>&1 || true ;;
      openrc) rc-service sing-box stop >/dev/null 2>&1 || true ;;
    esac
    rm -f "$SINGBOX_BIN" "$old_bin"
  fi
  return 1
}

# ---------- 时间同步 ----------

chrony_service_name() {
  case "$INIT_SYSTEM" in
    systemd)
      if systemctl cat chrony >/dev/null 2>&1; then
        echo "chrony"
      elif systemctl cat chronyd >/dev/null 2>&1; then
        echo "chronyd"
      else
        echo "chrony"
      fi
      ;;
    openrc)
      if openrc_service_exists chronyd; then
        echo "chronyd"
      elif openrc_service_exists chrony; then
        echo "chrony"
      fi
      ;;
  esac
}

chrony_service_running() {
  local service="$1"
  case "$INIT_SYSTEM" in
    systemd) systemctl is-active --quiet "$service" 2>/dev/null ;;
    openrc)  openrc_service_running "$service" ;;
    *)       return 1 ;;
  esac
}

chrony_service_start() {
  local service="$1"
  case "$INIT_SYSTEM" in
    systemd)
      systemctl reset-failed "$service" >/dev/null 2>&1 || true
      systemctl start "$service"
      ;;
    openrc)
      openrc_start_service "$service"
      ;;
    *) return 1 ;;
  esac
}

chrony_service_enable() {
  local service="$1"
  case "$INIT_SYSTEM" in
    systemd) systemctl enable "$service" >/dev/null 2>&1 || true ;;
    openrc)  openrc_enable_service "$service" default >/dev/null 2>&1 || true ;;
  esac
}

chrony_timeout() {
  run_with_timeout "$@"
}

chronyc_tracking_ready() {
  chrony_timeout 3 chronyc tracking >/dev/null 2>&1
}

chrony_service_status() {
  local service="$1"
  if chrony_service_running "$service"; then
    ok "chrony: 运行中"
  else
    warn "chrony: 未运行"
  fi
}

chrony_prepare_for_service_control() {
  local service="$1"
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl stop systemd-timesyncd >/dev/null 2>&1 || true
    systemctl disable systemd-timesyncd >/dev/null 2>&1 || true
    systemctl reset-failed "$service" >/dev/null 2>&1 || true
  fi
}

chrony_repair_service() {
  local service="$1"
  chrony_prepare_for_service_control "$service"
  if chrony_service_start "$service" >/dev/null 2>&1; then
    sleep 1
    chrony_service_running "$service"
    return
  fi

  case "$INIT_SYSTEM" in
    systemd) systemctl stop "$service" >/dev/null 2>&1 || true ;;
    openrc)  openrc_stop_service "$service" >/dev/null 2>&1 || true ;;
  esac
  pkill -9 chronyd >/dev/null 2>&1 || true
  rm -f /run/chrony/chronyd.pid >/dev/null 2>&1 || true
  chrony_service_start "$service" >/dev/null 2>&1 || return 1
  sleep 1
  chrony_service_running "$service"
}

sync_system_time_chrony() {
  require_root
  clear
  echo -e "${R}--- 一键同步系统时间 ---${NC}"
  if ! has_cmd chronyc; then
    warn "未检测到 chrony，开始安装..."
    install_pkg chrony || { err "chrony 安装失败。"; pause; return 1; }
    local installed_service
    installed_service="$(chrony_service_name)"
    [ -n "$installed_service" ] && chrony_service_enable "$installed_service"
  fi
  has_cmd chronyc || { err "chrony 安装后仍未找到 chronyc，无法继续校时。"; pause; return 1; }

  local chrony_service
  chrony_service="$(chrony_service_name)"
  if [ -z "$chrony_service" ]; then
    err "chrony 已安装，但未找到可用服务（OpenRC 通常应为 chronyd）。"
    warn "当前可能是 Alpine/LXC 精简环境，缺少 chrony 的 OpenRC 服务脚本。"
    warn "如果这是 LXC 容器，请在宿主机校准时间，容器会跟随宿主机时间。"
    pause
    return 1
  fi

  if ! chrony_service_running "$chrony_service" || ! chronyc_tracking_ready; then
    warn "开始修复 chrony 服务状态..."
    if ! chrony_repair_service "$chrony_service"; then
      err "chrony 服务未能启动：${chrony_service}"
      warn "当前环境可能不允许容器主动校时，请在宿主机校准时间。"
      chrony_service_status "$chrony_service"
      pause
      return 1
    fi
    chrony_service_enable "$chrony_service"
  fi

  if ! chronyc_tracking_ready; then
    err "chrony 服务已启动，但无法读取同步状态。"
    warn "当前环境可能不允许容器主动校时，请在宿主机校准时间。"
    chrony_service_status "$chrony_service"
    pause
    return 1
  fi

  local step_out
  if step_out="$(chrony_timeout 5 chronyc -a makestep 2>&1)"; then
    ok "时间同步完成。"
  else
    warn "当前环境可能不允许容器主动校时，请在宿主机校准时间。"
    [ -n "$step_out" ] && ui_echo "$step_out"
  fi
  chrony_service_status "$chrony_service"
  pause
}

# ---------- 卸载 ----------


print_full_cleanup_hint() {
  echo
  echo "如需彻底删除脚本与相关配置，可在退出脚本后手动执行："
  echo "rm -f /root/sb.sh"
  echo "rm -f /usr/local/bin/s"
  echo "rm -rf /etc/sing-box-manager"
  echo "rm -rf /etc/sing-box"
  echo "rm -rf /var/log/sing-box"
  echo "rm -f /var/lock/singbox-manager.lock /var/lock/singbox-tg-agent.lock"
  echo "rm -rf /var/lock/singbox-tg-agent.lock.d"
}


uninstall_singbox_keep_config() {
  require_root
  clear
  print_rect_title "卸载 sing-box"
  echo "该操作将停止并删除 sing-box 运行组件："
  echo "  - sing-box 服务"
  echo "  - sing-box 主程序"
  echo "  - 流量统计/日志维护定时任务"
  echo "  - TG Bot 服务与上报任务"
  echo
  echo "以下内容会保留："
  echo "  - sing-box 配置：/etc/sing-box"
  echo "  - 用户数据与 TG 配置：/etc/sing-box-manager"
  echo "  - 日志文件：/var/log/sing-box"
  echo "  - 管理脚本入口：/root/sb.sh、/usr/local/bin/s"
  echo
  ask_confirm_yes "输入 YES 确认卸载，其它任意输入取消: " || { warn "已取消卸载。"; pause; return 0; }

  sync_user_usage_counters || true
  remove_periodic_sync_cron || true
  remove_daily_maintenance_cron || true
  remove_user_watch_cron || true
  remove_log_maintain_cron || true
  remove_legacy_tg_cron || true
  remove_upstream_refresh_cron || true
  rm -f "$UPSTREAM_TAG_CACHE_FILE" >/dev/null 2>&1 || true
  cleanup_legacy_tg_service || true
  remove_all_singbox_service_units
  # 清理官方包可能创建的系统用户/组
  if has_cmd deluser; then
    deluser --system sing-box >/dev/null 2>&1 || true
  else
    userdel sing-box >/dev/null 2>&1 || true
  fi
  if has_cmd delgroup; then
    delgroup --system sing-box >/dev/null 2>&1 || true
  else
    groupdel sing-box >/dev/null 2>&1 || true
  fi
  rm -f "$SINGBOX_BIN" /usr/bin/sing-box "$SINGBOX_VERSION_STAMP" "$GRPCURL_BIN" >/dev/null 2>&1 || true
  rm -rf /var/tmp/sb-install.* >/dev/null 2>&1 || true
  refresh_command_cache
  if pkg_installed sing-box || pkg_installed sing-box-beta; then
    case "$PKG_MANAGER" in
      apt)
        pkg_installed sing-box && apt-get remove -y sing-box >/dev/null 2>&1 || true
        pkg_installed sing-box-beta && apt-get remove -y sing-box-beta >/dev/null 2>&1 || true
        pkg_installed sing-box && apt-get purge -y sing-box >/dev/null 2>&1 || true
        pkg_installed sing-box-beta && apt-get purge -y sing-box-beta >/dev/null 2>&1 || true
        ;;
      apk)
        pkg_installed sing-box && apk del sing-box >/dev/null 2>&1 || true
        pkg_installed sing-box-beta && apk del sing-box-beta >/dev/null 2>&1 || true
        ;;
    esac
  fi
  refresh_command_cache
  ok "卸载完成，配置和用户数据已保留。"
  print_full_cleanup_hint
  pause
}

# >>>>>>>>> END MODULE: 80_installer.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 90_protocol_menu.sh <<<<<<<<<<<
# ============================================================
# 模块: 90_protocol_menu.sh
# 职责: 协议管理菜单、安装/卸载协议、规范化接管
# 依赖: 00_base.sh, 10_config.sh, 20_protocol.sh, 30_route.sh
# ============================================================

# ---------- 协议状态摘要 ----------

protocol_status_summary() {
  local json="$1"
  local all_lines proto label ports
  all_lines="$(protocol_entry_inventory "$json")"

  for proto in "${SUPPORTED_PROTOCOLS[@]}"; do
    label="$proto"
    # \001 八进制而非 \x01：busybox awk（Alpine 默认）不认 \xHH 转义。
    ports="$(printf '%s\n' "$all_lines" | awk -F '\001' -v p="$proto" 'NF >= 3 && $2 == p { print $3 }' | sort -n | uniq | paste -sd'|' -)"

    if [ -n "$ports" ]; then
      printf '%s\t%s\t%s\n' "$label" "已安装" "$ports"
    else
      printf '%s\t%s\t%s\n' "$label" "未安装" ""
    fi
  done
}

protocol_entry_table() {
  local json="$1"
  protocol_entry_inventory "$json" | sort_tsv_by_protocol 1
}

# ---------- 规范化接管 ----------

normalize_takeover(){
  init_manager_env || { pause; return 0; }
  clear
  local json work_json
  local -a inv_lines=() issue_lines=() action_lines=()
  local -A target_seen=()
  local tag_updates=0 direct_updates=0 skipped=0

  json="$(config_load)"
  work_json="$json"
  mapfile -t inv_lines < <(protocol_entry_inventory_ext "$json")

  echo -e "${C}--- 规范化接管 ---${NC}"

  if [ ${#inv_lines[@]} -eq 0 ]; then
    warn "未识别到可接管的核心协议对象。"
    pause
    return 0
  fi

  local line idx oldtag proto port target current_count
  for line in "${inv_lines[@]}"; do
    IFS=$'\x01' read -r idx oldtag proto port <<< "$line"
    target="$(entry_key_from_parts "$proto" "$port")" || continue
    target_seen["$target"]=$(( ${target_seen["$target"]:-0} + 1 ))
  done

  for line in "${inv_lines[@]}"; do
    IFS=$'\x01' read -r idx oldtag proto port <<< "$line"
    target="$(entry_key_from_parts "$proto" "$port")" || continue

    if [ "${target_seen[$target]:-0}" -gt 1 ]; then
      issue_lines+=("主入站目标名冲突：${proto}:${port} -> ${target}（已跳过）")
      skipped=$((skipped+1))
      continue
    fi

    current_count="$(echo "$work_json" | jq -r --arg t "$target" --argjson idx "$idx" '[.inbounds | to_entries[] | select((.value.tag // "") == $t and .key != $idx)] | length')"
    if [ "$current_count" -gt 0 ]; then
      issue_lines+=("主入站目标 tag 已被其它对象占用：${target}（已跳过）")
      skipped=$((skipped+1))
      continue
    fi

    if [ "$oldtag" != "$target" ]; then
      work_json="$(echo "$work_json" | jq --argjson idx "$idx" --arg t "$target" '.inbounds[$idx].tag = $t')" || {
        err "规范化主入站 tag 失败：$proto:$port"
        pause
        return 1
      }
      action_lines+=("主入站：${oldtag:-<空>} -> ${target}")
      tag_updates=$((tag_updates+1))
    fi

    local -a user_lines=() direct_candidates=()
    local user_line uidx uname direct_old

    mapfile -t user_lines < <(echo "$work_json" | jq -r --argjson idx "$idx" '.inbounds[$idx].users // [] | to_entries[] | [.key, (.value.name // .value.username // "")] | join("\u0001")')

    for user_line in "${user_lines[@]}"; do
      IFS=$'\x01' read -r uidx uname <<< "$user_line"
      if [ "$proto" != "socks" ] && [[ "$uname" != *"@"* ]] && [[ "$uname" != *"-to-"* ]]; then
        direct_candidates+=("$uidx:$uname")
      fi
    done

    if [ ${#direct_candidates[@]} -eq 1 ]; then
      direct_old="${direct_candidates[0]#*:}"
      uidx="${direct_candidates[0]%%:*}"
      if [ "$direct_old" != "$target" ]; then
        work_json="$(echo "$work_json" | jq --argjson idx "$idx" --argjson uidx "$uidx" --arg old "$direct_old" --arg new "$target" '
          if (.inbounds[$idx].users[$uidx].name? // "") == $old then
            .inbounds[$idx].users[$uidx].name = $new
          elif (.inbounds[$idx].users[$uidx].username? // "") == $old then
            .inbounds[$idx].users[$uidx].username = $new
          else . end
          | .route.rules |= map(
              if (.auth_user? != null) then
                .auth_user |= (
                  if type == "array" then map(if . == $old then $new else . end)
                  elif . == $old then $new
                  else . end
                )
              else . end
            )
        ')" || {
          err "规范化直连用户失败：$target"
          pause
          return 1
        }
        action_lines+=("直连用户：${direct_old:-<空>} -> ${target}")
        direct_updates=$((direct_updates+1))
      fi
    elif [ ${#direct_candidates[@]} -gt 1 ]; then
      issue_lines+=("主入站存在多个直连候选用户，未自动规范化：${target}")
      skipped=$((skipped+1))
    fi

  done

  echo -e "${B}--------------------------------------------------------${NC}"
  echo -e "${C}预览结果${NC}"
  echo -e "  主入站规范化：${tag_updates}"
  echo -e "  直连用户规范化：${direct_updates}"
  if [ ${#action_lines[@]} -gt 0 ]; then
    echo -e "${B}--------------------------------------------------------${NC}"
    echo -e "${C}计划执行${NC}"
    local a
    for a in "${action_lines[@]}"; do
      echo -e "  - ${a}"
    done
  fi
  if [ ${#issue_lines[@]} -gt 0 ]; then
    echo -e "${B}--------------------------------------------------------${NC}"
    echo -e "${Y}发现但未自动处理${NC}"
    local it
    for it in "${issue_lines[@]}"; do
      echo -e "  - ${it}"
    done
  fi

  if [ $tag_updates -eq 0 ] && [ $direct_updates -eq 0 ]; then
    warn "没有可自动规范化的对象。"
    pause
    return 0
  fi

  echo ""
  ask_confirm_yes "输入 YES 确认执行规范化接管，其它任意输入取消: " || { warn "已取消规范化接管。"; pause; return 0; }

  work_json="$(route_rebuild "$work_json")" || {
    err "规范化接管后重建路由失败，已取消写入。"
    pause
    return 1
  }

  if config_apply "$work_json"; then
    ok "规范化接管完成。"
  else
    err "规范化接管应用失败。"
    pause
    return 1
  fi

  pause
}

# ---------- 协议安装菜单 ----------

prompt_password_or_return() {
  local prompt="${1:-Password（回车随机生成）: }" outvar="$2" val
  read -r -p "$prompt" val
  printf -v "$outvar" '%s' "${val:-}"
  return 0
}

prompt_ss2022_password_or_return() {
  local outvar="$1" val
  read -r -p "Password（回车随机生成）: " val
  if [ -n "${val:-}" ] && ! ss2022_prepare_password_pair "$val" >/dev/null 2>&1; then
    warn "Shadowsocks 2022 Password 必须是解码后 16 字节的 base64；如需分别设置服务端/用户密码，请使用 base64:base64。"
    return 1
  fi
  printf -v "$outvar" '%s' "${val:-}"
  return 0
}

protocol_install_menu() {
  local json="$1"
  local updated_json="$json"
  local choice_arr sel
  local -a added_node_keys=()
  local -a reality_meta_tags=()
  local -a reality_meta_pubs=()
  echo -e "\n${C}可安装协议（多个用 + 连接，如 1+3+5）:${NC}"
  echo -e "  [1] vless-reality"
  echo -e "  [2] anytls"
  echo -e "  [3] shadowsocks"
  echo -e "  [4] socks"
  echo -e "  [5] trojan"
  echo -e "  [6] vmess-ws"
  echo -e "  [7] vless-ws"
  echo -e "  [8] tuic"
  read -r -p "请输入要安装的协议编号（回车返回）: " sel
  mapfile -t choice_arr < <(parse_plus_selections "${sel:-}")
  [ ${#choice_arr[@]} -eq 0 ] && { warn "未选择任何协议，已返回上一级。"; pause; return 0; }

  local c port listen sni path priv sid entry_key inbound pub generated_pair uuid pass method server_pass user_pass username
  for c in "${choice_arr[@]}"; do
    if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 1 ] || [ "$c" -gt 8 ]; then
      warn "无效协议编号：$c，已返回上一级。"
      pause
      return 0
    fi
  done

  for c in "${choice_arr[@]}"; do
    case "$c" in
      1)
        ask_port_or_return "Reality 监听端口 (默认: 443): " "443" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts vless-reality "$port")"
        while port_conflict_for_protocol "$updated_json" vless-reality "$port" "$entry_key"; do
          warn "端口 ${port} 已被占用，请更换。"
          ask_port_or_return "Reality 监听端口 (默认: 443): " "443" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts vless-reality "$port")"
        done
        read -r -p "Private Key（回车自动生成）: " priv
        pub=""
        if [ -z "$priv" ]; then
          generated_pair="$(generate_reality_keypair_auto 2>/dev/null || true)"
          priv="${generated_pair%%$'\t'*}"
          pub="${generated_pair#*$'\t'}"
          if [ -z "$priv" ] || [ -z "$pub" ]; then
            warn "自动生成 Reality 密钥对失败，已返回上一级。"
            pause
            return 0
          fi
          param_echo "Private Key" "$priv"
          param_echo "Public Key" "$pub"
        else
          read -r -p "Public Key（必填，与 Private Key 配对，回车返回）: " pub
          if [ -z "$pub" ]; then
            warn "手动输入 Private Key 时必须同时提供 Public Key，已返回上一级。"
            pause
            return 0
          fi
        fi
        read -r -p "Short ID (回车随机生成8位hex): " sid
        if [ -z "$sid" ]; then
          sid="$(openssl rand -hex 4 2>/dev/null || true)"
          if [ -z "$sid" ]; then sid="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8)"; fi
          param_echo "Short ID" "$sid"
        fi
        sni="$(choose_tls_domain "Reality")" || return 0
        inbound="$(build_vless_reality_inbound "$port" "$sni" "$priv" "$sid")"
        uuid="$(echo "$inbound" | jq -r '.users[0].uuid // empty')"
        param_echo "UUID" "$uuid"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        if [ -n "$pub" ]; then
          reality_meta_tags+=("$entry_key")
          reality_meta_pubs+=("$pub")
        fi
        ;;
      2)
        ask_port_or_return "AnyTLS 端口 (默认: 443): " "443" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts anytls "$port")"
        while port_conflict_for_protocol "$updated_json" anytls "$port" "$entry_key"; do
          warn "端口 ${port} 已被占用，请更换。"
          ask_port_or_return "AnyTLS 端口 (默认: 443): " "443" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts anytls "$port")"
        done
        sni="$(choose_tls_domain "AnyTLS")" || return 0
        prompt_password_or_return "Password（回车随机生成）: " pass || { pause; return 0; }
        if ! inbound="$(build_anytls_inbound "$port" "$sni" "$pass")"; then
          err "生成 AnyTLS 配置失败：证书文件未能生成，已返回上一级。"
          pause
          return 0
        fi
        pass="$(echo "$inbound" | jq -r '.users[0].password // empty')"
        param_echo "Password" "$pass"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        ;;
      3)
        ask_port_or_return "Shadowsocks 监听端口 (默认: 8080): " "8080" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts shadowsocks "$port")"
        while port_conflict_for_protocol "$updated_json" shadowsocks "$port" "$entry_key"; do
          warn "端口 ${port} 已被同层协议占用，请更换。"
          ask_port_or_return "Shadowsocks 监听端口 (默认: 8080): " "8080" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts shadowsocks "$port")"
        done
        prompt_ss2022_password_or_return pass || { pause; return 0; }
        if ! inbound="$(build_ss_inbound "$port" "$pass")"; then
          err "生成 Shadowsocks 配置失败，已返回上一级。"
          pause
          return 0
        fi
        method="$(echo "$inbound" | jq -r '.method // empty')"
        server_pass="$(echo "$inbound" | jq -r '.password // empty')"
        user_pass="$(echo "$inbound" | jq -r '.users[0].password // empty')"
        if [ -n "$server_pass" ] && [ "$server_pass" != "$user_pass" ]; then
          pass="${server_pass}:${user_pass}"
        else
          pass="$user_pass"
        fi
        param_echo "Method" "$method"
        param_echo "Password" "$pass"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        ;;
      4)
        ask_port_or_return "SOCKS 监听端口 (默认: 1080): " "1080" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts socks "$port")"
        while port_conflict_for_protocol "$updated_json" socks "$port" "$entry_key"; do
          warn "端口 ${port} 已被同层协议占用，请更换。"
          ask_port_or_return "SOCKS 监听端口 (默认: 1080): " "1080" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts socks "$port")"
        done
        prompt_password_or_return "Password（回车随机生成）: " pass || { pause; return 0; }
        [ -n "$pass" ] || pass="$(random_b64_password 12)"
        if ! inbound="$(build_socks_inbound "$port" "$pass")"; then
          err "生成 SOCKS 配置失败，已返回上一级。"
          pause
          return 0
        fi
        username="$(echo "$inbound" | jq -r '.users[0].username // empty')"
        pass="$(echo "$inbound" | jq -r '.users[0].password // empty')"
        param_echo "Username" "$username"
        param_echo "Password" "$pass"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        ;;
      5)
        ask_port_or_return "Trojan 端口 (默认: 443): " "443" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts trojan "$port")"
        while port_conflict_for_protocol "$updated_json" trojan "$port" "$entry_key"; do
          warn "端口 ${port} 已被占用，请更换。"
          ask_port_or_return "Trojan 端口 (默认: 443): " "443" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts trojan "$port")"
        done
        sni="$(choose_tls_domain "Trojan")" || return 0
        prompt_password_or_return "Password（回车随机生成）: " pass || { pause; return 0; }
        if ! inbound="$(build_trojan_inbound "$port" "$sni" "$pass")"; then
          err "生成 Trojan 配置失败：证书文件未能生成，已返回上一级。"
          pause
          return 0
        fi
        pass="$(echo "$inbound" | jq -r '.users[0].password // empty')"
        param_echo "Password" "$pass"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        ;;
      6)
        read -r -p "vmess-ws 监听地址 (默认: 127.0.0.1): " listen; listen="${listen:-127.0.0.1}"
        ask_port_or_return "vmess-ws 监听端口 (默认: 8001): " "8001" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts vmess-ws "$port")"
        while port_conflict_for_protocol "$updated_json" vmess-ws "$port" "$entry_key"; do
          warn "端口 ${port} 已被占用，请更换。"
          ask_port_or_return "vmess-ws 监听端口 (默认: 8001): " "8001" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts vmess-ws "$port")"
        done
        read -r -p "WS Path (回车随机生成): " path; path="$(normalize_ws_path "${path:-}")"
        param_echo "WS Path" "$path"
        inbound="$(build_vmess_ws_inbound "$port" "$listen" "$path")"
        uuid="$(echo "$inbound" | jq -r '.users[0].uuid // empty')"
        param_echo "UUID" "$uuid"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        ;;
      7)
        read -r -p "vless-ws 监听地址 (默认: 127.0.0.1): " listen; listen="${listen:-127.0.0.1}"
        ask_port_or_return "vless-ws 监听端口 (默认: 8002): " "8002" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts vless-ws "$port")"
        while port_conflict_for_protocol "$updated_json" vless-ws "$port" "$entry_key"; do
          warn "端口 ${port} 已被占用，请更换。"
          ask_port_or_return "vless-ws 监听端口 (默认: 8002): " "8002" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts vless-ws "$port")"
        done
        read -r -p "WS Path (回车随机生成): " path; path="$(normalize_ws_path "${path:-}")"
        param_echo "WS Path" "$path"
        inbound="$(build_vless_ws_inbound "$port" "$listen" "$path")"
        uuid="$(echo "$inbound" | jq -r '.users[0].uuid // empty')"
        param_echo "UUID" "$uuid"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        ;;
      8)
        ask_port_or_return "TUIC 端口（默认443，可与TCP协议的443端口并存）: " "443" port || { warn "已返回上一级。"; pause; return 0; }
        entry_key="$(entry_key_from_parts tuic "$port")"
        while port_conflict_for_protocol "$updated_json" tuic "$port" "$entry_key"; do
          warn "端口 ${port} 已被其它 TUIC 占用，请更换。"
          ask_port_or_return "TUIC 端口（默认443，可与TCP协议的443端口并存）: " "443" port || { warn "已返回上一级。"; pause; return 0; }
          entry_key="$(entry_key_from_parts tuic "$port")"
        done
        sni="$(choose_tls_domain "TUIC")" || return 0
        prompt_password_or_return "Password（回车随机生成）: " pass || { pause; return 0; }
        if ! inbound="$(build_tuic_inbound "$port" "$sni" "$pass")"; then
          err "生成 TUIC 配置失败：证书文件未能生成，已返回上一级。"
          pause
          return 0
        fi
        uuid="$(echo "$inbound" | jq -r '.users[0].uuid // empty')"
        pass="$(echo "$inbound" | jq -r '.users[0].password // empty')"
        param_echo "UUID" "$uuid"
        param_echo "Password" "$pass"
        updated_json="$(echo "$updated_json" | jq --arg ek "$entry_key" --argjson inb "$inbound" '.inbounds |= map(select(.tag != $ek)) | .inbounds += [$inb]')"
        added_node_keys+=("$entry_key")
        ;;
    esac
  done

  updated_json="$(route_rebuild "$updated_json")"
  # 构造候选 meta：把所有 reality 公钥写进去，与 config 一起原子提交
  local candidate_meta i
  candidate_meta="$(meta_load 2>/dev/null)" || candidate_meta='{}'
  [ -n "$candidate_meta" ] || candidate_meta='{}'
  for i in "${!reality_meta_tags[@]}"; do
    candidate_meta="$(echo "$candidate_meta" | jq \
      --arg t "${reality_meta_tags[$i]}" --arg pk "${reality_meta_pubs[$i]}" \
      '.[$t] = ((.[$t] // {}) + {public_key:$pk, private_key_auto_generated:true})')" || {
      err "构造 reality meta 失败。"
      pause
      return 1
    }
  done
  local _install_ok=0
  if user_db_exists; then
    local db_json node_key
    sync_user_usage_counters || true
    db_json="$(user_db_load)"
    for node_key in "${added_node_keys[@]}"; do
      db_json="$(user_db_on_node_added "$db_json" "$node_key")"
    done
    if _USER_KEEP_LATEST_DB=1 _USER_MANAGER_APPLY_QUIET_OK=1 user_manager_apply_changes "$db_json" "$updated_json" "$candidate_meta"; then
      _install_ok=1
    else
      warn "协议安装/更新失败，已返回上一级。"
    fi
  else
    if _CONFIG_APPLY_QUIET_OK=1 config_and_meta_apply "$updated_json" "$candidate_meta"; then
      _install_ok=1
    else
      warn "协议安装/更新失败，已返回上一级。"
    fi
  fi
  if [ "$_install_ok" -eq 1 ]; then
    ok "协议已安装/更新。"
  fi
  pause
  return 0
}

# ---------- 协议卸载菜单 ----------

protocol_remove_menu() {
  local json="$1"
  local lines=() choice_arr updated_json="$json" c entry_key related sel
  mapfile -t lines < <(protocol_entry_table "$json")
  if [ ${#lines[@]} -eq 0 ]; then
    warn "当前没有可卸载的协议。"
    pause
    return 0
  fi
  echo -e "\n${R}已安装协议如下（多个用 + 连接，如 1+2）:${NC}"
  local i=1
  for line in "${lines[@]}"; do
    IFS=$'\x01' read -r entry_key type port <<< "$line"
    echo -e " [$i] ${entry_key}"
    i=$((i+1))
  done
  read -r -p "请输入要卸载的协议编号（回车返回）: " sel
  mapfile -t choice_arr < <(parse_plus_selections "${sel:-}")
  [ ${#choice_arr[@]} -eq 0 ] && { warn "未选择任何协议。"; pause; return 0; }

  for c in "${choice_arr[@]}"; do
    if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 1 ] || [ "$c" -gt "${#lines[@]}" ]; then
      warn "无效协议编号：$c，已返回上一级。"
      pause
      return 0
    fi
  done

  local _cert_files_to_clean=()
  for c in "${choice_arr[@]}"; do
    IFS=$'\x01' read -r entry_key _ <<< "${lines[$((c-1))]}"
    local _crt _key
    _crt="$(echo "$updated_json" | jq -r --arg ek "$entry_key" '.inbounds[]? | select((.tag // "") == $ek) | .tls.certificate_path // empty' | head -n1)"
    _key="$(echo "$updated_json" | jq -r --arg ek "$entry_key" '.inbounds[]? | select((.tag // "") == $ek) | .tls.key_path // empty' | head -n1)"
    [ -n "$_crt" ] && [[ "$_crt" == /etc/sing-box/* ]] && _cert_files_to_clean+=("$_crt")
    [ -n "$_key" ] && [[ "$_key" == /etc/sing-box/* ]] && _cert_files_to_clean+=("$_key")
    updated_json="$(remove_inbound_by_entry_key "$updated_json" "$entry_key")" || {
      err "删除协议失败，已中止，未写入配置。"
      pause
      return 1
    }
  done

  updated_json="$(route_rebuild "$updated_json")" || {
    err "重建路由失败，已中止，未写入配置。"
    pause
    return 1
  }
  local _apply_ok=0
  if user_db_exists; then
    local db_json
    sync_user_usage_counters || true
    db_json="$(user_db_load)"
    if _USER_KEEP_LATEST_DB=1 _USER_MANAGER_APPLY_QUIET_OK=1 user_manager_apply_changes "$db_json" "$updated_json"; then
      _apply_ok=1
    else
      warn "协议卸载失败，已返回上一级。"
    fi
  else
    if _CONFIG_APPLY_QUIET_OK=1 config_apply "$updated_json"; then
      _apply_ok=1
    else
      warn "协议卸载失败，已返回上一级。"
    fi
  fi
  if [ "$_apply_ok" -eq 1 ] && [ ${#_cert_files_to_clean[@]} -gt 0 ]; then
    for _f in "${_cert_files_to_clean[@]}"; do
      rm -f "$_f" >/dev/null 2>&1 || true
    done
  fi
  [ "$_apply_ok" -eq 1 ] && ok "协议已卸载。"
  pause
  return 0
}

# ---------- 协议管理主菜单 ----------

protocol_manager() {
  init_manager_env || { pause; return 0; }
  while true; do
    clear
    local json
    json="$(config_load)"
    print_rect_title "协议管理"
    local _proto_tmp
    _proto_tmp="$(mktemp)"
    if protocol_status_summary "$json" >"$_proto_tmp" && [ -s "$_proto_tmp" ]; then
      local proto_width=15 proto_pad status_color port_text
      echo -e "${C}当前状态${NC}"
      echo -e "${B}--------------------------------------------------------${NC}"
      while IFS=$'\t' read -r proto status ports; do
        proto_pad=$(printf "%-${proto_width}s" "$proto")
        if [ "$status" = "已安装" ]; then
          status_color="$G"
        else
          status_color="$Y"
        fi
        if [ -n "$ports" ]; then
          port_text="（端口${ports//|/|端口}）"
          printf "  - %b%s%b  %b【%s】%b%b%s%b\n" "$W" "$proto_pad" "$NC" "$status_color" "$status" "$NC" "$C" "$port_text" "$NC"
        else
          printf "  - %b%s%b  %b【%s】%b\n" "$W" "$proto_pad" "$NC" "$status_color" "$status" "$NC"
        fi
      done < "$_proto_tmp"
    else
      echo -e "${Y}当前没有任何协议。${NC}"
    fi
    rm -f "$_proto_tmp" >/dev/null 2>&1 || true
    echo -e "${B}--------------------------------------------------------${NC}"
    echo -e "  ${C}1.${NC} 安装协议"
    echo -e "  ${C}2.${NC} 卸载协议"
    echo -e "  ${R}0.${NC} 返回主菜单"
    read -r -p "请选择操作: " act
    case "${act:-}" in
      1) protocol_install_menu "$json" || true ;;
      2) protocol_remove_menu "$json" || true ;;
      0|q|Q|"") return 0 ;;
      *) warn "无效输入：$act"; sleep 1 ;;
    esac
  done
}

# ---------- 其它工具入口 ----------

clear_config_json() {
  init_manager_env || { pause; return 0; }
  clear
  echo -e "${Y}--- 清空/重置配置文件 ---${NC}"
  echo -e "${Y}注意：该操作将清空当前 config.json。${NC}"
  ask_confirm_yes || { warn "已取消清空/重置。"; pause; return 0; }
  # 原子提交：config 重置 + meta 清理在同一把锁内一起做，避免分裂。
  # del(.warp, .relay) 用于清理旧版本遗留的分流状态；本版本已无这两个功能。
  local empty_config empty_meta
  empty_config="$(config_min_template)"
  empty_meta="$(meta_load 2>/dev/null | jq 'del(.warp, .relay)' 2>/dev/null)"
  [ -n "$empty_meta" ] || empty_meta='{}'
  if config_and_meta_apply "$empty_config" "$empty_meta"; then
    ok "配置已清空，分流状态已重置。"
  else
    err "配置或分流状态清空失败。"
  fi
  pause
}

view_realtime_log() {
  clear
  print_rect_title "查看实时日志"
  if [ ! -f "$SCRIPT_LOG_FILE" ]; then
    warn "当前暂无日志文件：$SCRIPT_LOG_FILE"
    pause
    return 0
  fi

  echo -e "${Y}正在显示最近 10 行日志，并进入实时跟踪；按 Ctrl+C 返回菜单。${NC}"

  local old_trap
  old_trap="$(trap -p INT || true)"

  trap 'echo ""; trap - INT; return 0' INT
  tail -n 10 -f "$SCRIPT_LOG_FILE"
  trap - INT

  if [ -n "$old_trap" ]; then
    eval "$old_trap"
  fi

  echo ""
  return 0
}

view_config_formatted() {
  init_manager_env || { pause; return 0; }
  clear
  echo -e "${C}--- 查看格式化配置 ---${NC}"
  sing-box format -c "$CONFIG_FILE" || err "sing-box format 执行失败。"
  echo ""
  pause
}

singbox_status_summary() {
  local _status _version _state _upstream _suffix
  case "$INIT_SYSTEM" in
    systemd)
      _state="$(systemctl is-active sing-box 2>/dev/null || true)"
      case "$_state" in
        active) _status="${G}运行中${NC}" ;;
        failed) _status="${Y}异常${NC}" ;;
        activating) _status="${Y}启动中${NC}" ;;
        *) _status="${R}已停止${NC}" ;;
      esac
      ;;
    openrc)
      _state="$(rc-service sing-box status 2>&1 || true)"
      case "$_state" in
        *crashed*) _status="${Y}异常${NC}" ;;
        *started*|*running*) _status="${G}运行中${NC}" ;;
        *stopped*) _status="${R}已停止${NC}" ;;
        *)
          if singbox_service_active; then
            _status="${G}运行中${NC}"
          else
            _status="${R}已停止${NC}"
          fi
          ;;
      esac
      ;;
    *)
      if singbox_service_active; then
        _status="${G}运行中${NC}"
      else
        _status="${R}已停止${NC}"
      fi
      ;;
  esac
  _version=""
  if [ -x "$SINGBOX_BIN" ]; then
    _version="$("$SINGBOX_BIN" version 2>/dev/null | awk '/^sing-box version / {print $3; exit}')"
  fi
  [ -n "$_version" ] || _version="未知"

  _suffix=""
  _upstream="$(get_cached_upstream_version 2>/dev/null || true)"
  if [ "$_version" != "未知" ] && [ -n "$_upstream" ]; then
    if [ "$_version" != "$_upstream" ] && version_ge "$_upstream" "$_version"; then
      _suffix="  ${Y}(有新版 ${_upstream})${NC}"
    fi
  elif [ "$_version" != "未知" ] && [ -z "$_upstream" ]; then
    _suffix="  ${Y}(新版检测: 未知)${NC}"
  fi

  printf '  %bsing-box%b : %b  版本 %b%s%b%b\n' "$W" "$NC" "$_status" "$G" "$_version" "$NC" "$_suffix"
}

singbox_start() {
  clear
  print_rect_title "启动 sing-box"
  case "$INIT_SYSTEM" in
    systemd)
      if systemctl start sing-box; then
        sleep 1
        if systemctl is-active --quiet sing-box 2>/dev/null; then
          ok "sing-box 已启动并正常运行。"
        else
          err "启动命令已执行，但服务未能正常运行，请检查配置或日志。"
        fi
      else
        err "启动失败，请检查配置或日志。"
      fi
      ;;
    openrc)
      if openrc_start_service sing-box >/dev/null 2>&1; then
        sleep 1
        if openrc_service_running sing-box; then
          ok "sing-box 已启动并正常运行。"
        else
          err "启动命令已执行，但服务未能正常运行，请检查配置或日志。"
        fi
      else
        err "启动失败，请检查配置或日志。"
      fi
      ;;
    *) err "未识别的 init 系统，无法启动 sing-box。" ;;
  esac
  echo ""
  pause
}

singbox_stop() {
  clear
  print_rect_title "停止 sing-box"
  case "$INIT_SYSTEM" in
    systemd)
      systemctl stop sing-box && ok "sing-box 已停止。" || err "停止失败。"
      ;;
    openrc)
      openrc_stop_service sing-box >/dev/null 2>&1 && ok "sing-box 已停止。" || err "停止失败。"
      ;;
    *) err "未识别的 init 系统，无法停止 sing-box。" ;;
  esac
  echo ""
  pause
}

system_tools_menu() {
  while true; do
    clear
    print_rect_title "系统工具"
    singbox_status_summary
    cron_job_status_line "实时同步" "$PERIODIC_SYNC_CRON_MARK"
    cron_job_status_line "日常维护" "$DAILY_MAINTENANCE_CRON_MARK"
    echo -e "${B}----------------------------------------${NC}"
    echo -e "  ${C}1.${NC} 启动 sing-box"
    echo -e "  ${C}2.${NC} 停止 sing-box"
    echo -e "  ${C}3.${NC} 查看 sing-box 实时日志"
    echo -e "  ${C}4.${NC} 查看 config 配置文件"
    echo -e "  ${C}5.${NC} 清空/重置 config 配置文件"
    echo -e "  ${C}6.${NC} 一键校准系统时间"
    echo -e "  ${C}7.${NC} 规范化接管旧配置"
    echo -e "  ${R}0.${NC} 返回主菜单"
    read -r -p "请选择操作: " act
    case "${act:-}" in
      1) singbox_start ;;
      2) singbox_stop ;;
      3) view_realtime_log ;;
      4) view_config_formatted ;;
      5) clear_config_json ;;
      6) sync_system_time_chrony ;;
      7) normalize_takeover ;;
      0|q|Q|"") return 0 ;;
      *) warn "无效输入：$act"; sleep 1 ;;
    esac
  done
}

# >>>>>>>>> END MODULE: 90_protocol_menu.sh <<<<<<<<<<<

# >>>>>>>>> BEGIN MODULE: 99_main.sh <<<<<<<<<<<
# ============================================================
# 模块: 99_main.sh
# 职责: 主菜单 + CLI 入口路由
# 依赖: 所有其它模块
# ============================================================

main_menu() {
  ensure_local_script_entrypoint_once
  while true; do
    clear
    print_rect_title "Sing-box Elite 管理系统  V${SCRIPT_VERSION}"
    singbox_status_summary
    echo -e "${B}--------------------------------------------------------${NC}"
    echo -e "  ${C}1.${NC} 安装/更新 sing-box"
    echo -e "  ${C}2.${NC} 系统工具"
    echo -e "  ${C}3.${NC} 协议管理"
    echo -e "  ${C}4.${NC} 导出节点配置"
    echo -e "  ${C}5.${NC} 用户管理"
    echo -e "  ${C}6.${NC} 卸载 sing-box"
    echo -e "  ${R}0.${NC} 退出系统"
    echo -e "${B}--------------------------------------------------------${NC}"
    read -r -p "请选择操作指令: " opt
    case "${opt:-}" in
      1) install_or_update_singbox ;;
      2) system_tools_menu || true ;;
      3) protocol_manager || true ;;
      4) export_configs || true ;;
      5) user_manager_menu || true ;;
      6) uninstall_singbox_keep_config ;;
      0|q|Q) exit 0 ;;
      *) warn "无效输入：$opt"; sleep 1 ;;
    esac
  done
}

# ====================================================
# CLI 入口路由
# ====================================================
if [[ "${1:-}" == "--periodic-sync" ]]; then
  periodic_sync_run
  exit 0
fi

if [[ "${1:-}" == "--daily-maintenance" ]]; then
  daily_maintenance_run
  exit 0
fi

# 6.0.8 及以前的 4 个老入口已合并到上面两个 runner。
# 保留为静默墓志铭，避免老 cron 跑过来掉进 main_menu 死循环 / 刷邮箱。
# --tg-agent-sync 额外保留：TG 模块已从本版本移除，但从旧版升级上来、cron
# 清理还没跑到的那几分钟里，这个入口仍可能被触发，必须静默退出而不是进主菜单。
# is_install_complete 探针会在用户进 1.安装/更新 时引导清理这些老 cron。
if [[ "${1:-}" == "--user-watch" ]] || [[ "${1:-}" == "--maintain-logs" ]] || \
   [[ "${1:-}" == "--tg-agent-sync" ]] || [[ "${1:-}" == "--refresh-upstream" ]]; then
  exit 0
fi

main_menu

# >>>>>>>>> END MODULE: 99_main.sh <<<<<<<<<<<
