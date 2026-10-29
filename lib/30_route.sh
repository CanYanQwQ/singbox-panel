#!/usr/bin/env bash
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
