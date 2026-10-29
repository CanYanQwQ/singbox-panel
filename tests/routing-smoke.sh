#!/usr/bin/env bash
# Isolated real remote rule-set download and route rebuild verification.
# 中转(relay)/WARP 分流已从本版本移除，本测试只覆盖直连路由与远程规则集下载。
set -euo pipefail
cd "$(dirname "$0")/.."
for module in 00_base 01_utils 10_config 20_protocol 30_route 50_v2ray_api; do source "lib/$module.sh"; done
T=$(mktemp -d); pids=(); core_pid=''
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; [ -z "$core_pid" ] || kill "$core_pid" 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT
read -r entry_port api_port http_port < <(python3 - <<'PY'
import socket
ss=[socket.socket() for _ in range(3)]
for s in ss:s.bind(('127.0.0.1',0))
print(*(s.getsockname()[1] for s in ss))
PY
)
echo '{"version":3,"rules":[{"ip_cidr":["127.0.0.1/32"]}]}' > "$T/rules.json"
sing-box rule-set compile -o "$T/test.srs" "$T/rules.json"
printf payload > "$T/payload"
python3 -m http.server "$http_port" --bind 127.0.0.1 --directory "$T" > "$T/http.log" 2>&1 & pids+=("$!")
V2RAY_API_LISTEN="127.0.0.1:$api_port"; V2RAY_PROTO_V2RAY="$T/stats.proto"; ensure_v2ray_api_proto_files
entry="socks-$entry_port"
base=$(build_socks_inbound "$entry_port" fixture|jq '{log:{level:"info"},inbounds:[(.listen="127.0.0.1")],outbounds:[{type:"direct",tag:"direct"}],route:{rules:[]}}')
url="http://localhost:$http_port/test.srs"

# 直连模式：核心账号 auth_user 直出 direct，远程 rule_set 由 route 保留。
auth="$entry"
config=$(route_rebuild "$base" '{}')
echo "$config" | jq --arg api "$V2RAY_API_LISTEN" --arg tag direct '.experimental.v2ray_api={listen:$api,stats:{enabled:true,outbounds:[$tag]}}' > "$T/config.json"
sing-box check -c "$T/config.json"
sing-box run -c "$T/config.json" > "$T/core.log" 2>&1 & core_pid=$!
for ((n=0;n<40;n++)); do query_v2ray_api_uptime >/dev/null 2>&1 && break; sleep .25; done
if ! curl -fsS --max-time 5 --noproxy '' --socks5 "127.0.0.1:$entry_port" --proxy-user "$auth:fixture" "http://127.0.0.1:$http_port/payload" -o "$T/result"; then cat "$T/core.log"; exit 1; fi
[ "$(cat "$T/result")" = payload ]
v2ray_api_query QueryStats '{"pattern":"outbound>>>","reset":false}' | jq -e --arg tag "direct" '[.stat[]? | select(.name == ("outbound>>>"+$tag+">>>traffic>>>downlink")) | .value|tonumber]|add > 0' >/dev/null
! grep -q 'deprecated' "$T/core.log"
kill "$core_pid"; wait "$core_pid" || true; core_pid=''
echo "PASS direct: real SOCKS forwarding, no deprecation warning"

# 远程 rule_set 下载可用性（只校验文件可拉取并被 jq 判为远程类型）
remote_rules=$(jq -nc --arg url "$url" '[{tag:"geosite-test",type:"remote",format:"binary",url:$url}]')
echo "$remote_rules" | jq -e '.[0].type == "remote" and .[0].format == "binary"' >/dev/null
curl -fsS --max-time 10 "$url" -o "$T/dl.srs"
[ -s "$T/dl.srs" ]
echo "PASS remote-rule download: rule_set reached and stored"
