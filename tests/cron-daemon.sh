#!/usr/bin/env bash
# cron 守护进程探测的回归测试。
#
# 背景：旧实现只尝试 crond / cron 两个服务名，而 Alpine 上 apk add dcron
# 装的 init 脚本叫 dcron，于是 rc-service crond start 必然失败，
# 安装时就会打印「cron 服务不可用」，随后两个 cron 任务都装不上。
#
# 本测试把 lib/80_installer.sh 里 _crond_* 系列函数切出来，
# 在受控的假环境里逐个场景验证，不依赖真实的 cron / init 系统。
set -u
cd "$(dirname "$0")/.." || exit 1

SRC="lib/80_installer.sh"
fail=0
pass=0

ok()  { pass=$((pass + 1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then ok "$desc"; else bad "$desc (want=[$want] got=[$got])"; fi
}

# ---- 从真实源码里切出待测函数，保证测的是线上实现 ----
extract() {
  awk -v fn="$1" '
    index($0, fn "() {") == 1 { inside = 1 }
    inside { print }
    inside && $0 == "}" { exit }
  ' "$SRC"
}

BLOCK=""
for fn in _crond_service_exists _crond_pidfile_alive _crond_process_alive \
          _crond_daemon_active _crond_start_and_enable _crond_spawn_fallback \
          _ensure_crond_running; do
  chunk="$(extract "$fn")"
  if [ -z "$chunk" ]; then
    printf 'FATAL: 未能从 %s 中切出 %s\n' "$SRC" "$fn"
    exit 1
  fi
  BLOCK="$BLOCK
$chunk"
done

CANDIDATES="$(grep -m1 '^_CROND_SERVICE_CANDIDATES=' "$SRC")"
[ -n "$CANDIDATES" ] || { printf 'FATAL: 未找到 _CROND_SERVICE_CANDIDATES\n'; exit 1; }

# ---- 运行环境桩 ----
has_cmd()     { command -v "$1" >/dev/null 2>&1; }
warn()        { :; }
err()         { :; }
install_pkg() { return 1; }
sleep()       { :; }

INIT_SYSTEM=""
PKG_MANAGER=""
AVAILABLE_SERVICES=""   # 模拟 /etc/init.d 下存在哪些服务脚本
RUNNING_SERVICES=""     # 模拟哪些服务已启动
PIDFILE_ALIVE=1         # 0=pidfile 探针认为守护进程活着
PROC_ALIVE=1            # 0=进程表探针认为 cron 守护进程活着
CHECK_CALLS=0           # 进程表探针被调用的次数
SPAWN_WORKS=1           # 0=直接起进程的兜底会失败
START_LOG=""

_mark_started() {
  local svc="$1"
  START_LOG="$START_LOG $svc"
  case " $AVAILABLE_SERVICES " in
    *" $svc "*) RUNNING_SERVICES="$RUNNING_SERVICES $svc"; return 0 ;;
    *) return 1 ;;
  esac
}

rc-service() {
  local svc="$1" action="${2:-}"
  case "$action" in
    start)  _mark_started "$svc" ;;
    status) case " $RUNNING_SERVICES " in *" $svc "*) return 0 ;; *) return 1 ;; esac ;;
  esac
  return 1
}

rc-update() { return 0; }

systemctl() {
  # 真实调用形如 `systemctl is-active --quiet crond`，服务名是最后一个非选项参数
  local action="$1" svc="" a
  shift
  for a in "$@"; do case "$a" in -*) ;; *) svc="$a" ;; esac; done
  case "$action" in
    is-active) case " $RUNNING_SERVICES " in *" $svc "*) return 0 ;; *) return 1 ;; esac ;;
    start)     _mark_started "$svc" ;;
    enable)    return 0 ;;
  esac
  return 1
}

reset_env() {
  INIT_SYSTEM="$1"; PKG_MANAGER="$2"
  AVAILABLE_SERVICES="$3"; RUNNING_SERVICES="${4:-}"
  # 两个探针都用 shell 返回值语义：0=认为守护进程活着，1=认为没在跑
  PIDFILE_ALIVE=1; PROC_ALIVE=1; CHECK_CALLS=0
  SPAWN_WORKS=1; START_LOG=""
}

eval "$CANDIDATES"
eval "$BLOCK"

# 三个探针依赖真实文件系统 / 真实进程，测试里换成受控桩
_crond_service_exists() {
  case " $AVAILABLE_SERVICES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}
_crond_pidfile_alive() { return "$PIDFILE_ALIVE"; }
# 真实实现会扫 ps 进程表 / /proc；测试里用 PROC_ALIVE 控制返回值，
# 并记录调用次数，用来断言「pidfile 没命中时才轮到进程表」这条顺序。
_crond_process_alive() { CHECK_CALLS=$((CHECK_CALLS + 1)); return "$PROC_ALIVE"; }
_crond_spawn_fallback() {
  [ "$SPAWN_WORKS" = "0" ] && return 1
  RUNNING_SERVICES="$RUNNING_SERVICES crond"
  return 0
}

echo "== 场景 1: Alpine + dcron（旧代码失败的真实机型） =="
reset_env openrc apk "dcron"
if _ensure_crond_running; then
  ok "dcron 服务被发现并启动"
else
  bad "dcron 未被识别（这正是用户报告的 bug）"
fi
assert_eq "启动的是 dcron 而不是 crond" " dcron" "$START_LOG"

echo "== 场景 2: Alpine + cronie（服务名 crond） =="
reset_env openrc apk "crond"
if _ensure_crond_running; then ok "crond 启动成功"; else bad "crond 未能启动"; fi
assert_eq "启动的是 crond" " crond" "$START_LOG"

echo "== 场景 3: Debian + cron（服务名 cron） =="
reset_env systemd apt "cron"
if _ensure_crond_running; then ok "cron 启动成功"; else bad "cron 未能启动"; fi
assert_eq "启动的是 cron" " cron" "$START_LOG"

echo "== 场景 4: 已经在跑，不应重复启动 =="
reset_env openrc apk "crond" "crond"
if _ensure_crond_running; then ok "已运行直接返回 0"; else bad "已运行时返回了非 0"; fi
assert_eq "没有多余 start 调用" "" "$START_LOG"

echo "== 场景 5: 只有 dcron 在跑（跨服务名探测） =="
reset_env openrc apk "crond dcron" "dcron"
if _crond_daemon_active; then ok "能通过 dcron 判定守护进程存活"; else bad "dcron 在跑却判定为未运行"; fi

echo "== 场景 6: 极简镜像无 init 脚本，靠进程兜底 =="
reset_env unknown unknown ""
PIDFILE_ALIVE=1; PROC_ALIVE=1   # 两个探针都认为没在跑
SPAWN_WORKS=1
if _ensure_crond_running; then ok "无 init 脚本时兜底成功"; else bad "兜底路径未触发"; fi

echo "== 场景 7: 什么都没有，必须干净失败 =="
reset_env unknown unknown ""
PIDFILE_ALIVE=1; PROC_ALIVE=1
SPAWN_WORKS=0
if _ensure_crond_running; then
  bad "无 cron 可用时不该返回成功"
else
  ok "无 cron 可用时返回失败（由调用方打印指引）"
fi

echo "== 场景 8: pidfile 兜底探测 =="
reset_env openrc apk "crond"
PIDFILE_ALIVE=0
if _crond_daemon_active; then ok "服务未起但 pidfile 存活时判定运行中"; else bad "pidfile 兜底未生效"; fi

echo "== 场景 9: busybox crond 不写 pidfile，必须靠进程表判定 =="
reset_env openrc apk "dcron"
PIDFILE_ALIVE=1; PROC_ALIVE=0      # pidfile 探针失败，进程表探针命中
if _crond_daemon_active; then
  ok "无 pidfile 时靠进程表判定守护进程存活"
else
  bad "进程表兜底未生效（busybox crond 不写 pidfile）"
fi

echo "== 场景 10: pidfile 命中时不应再去扫进程表 =="
reset_env openrc apk "crond"
PIDFILE_ALIVE=0; PROC_ALIVE=0
_crond_daemon_active >/dev/null 2>&1
assert_eq "pidfile 已命中，进程表未被调用" "0" "$CHECK_CALLS"

echo
printf '结果: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
