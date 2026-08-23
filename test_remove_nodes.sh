#!/usr/bin/env bash

set -Eeuo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"

source "$(dirname "$0")/rainbow.sh"

parse_node_selection '1, 3 3' 4
[[ "${SELECTED_NODE_INDEXES[*]}" == "1 3" ]]
! parse_node_selection '0 2' 4
! parse_node_selection '1 x' 4

cat > "$tmp/xray.json" <<'EOF'
{
  "inbounds": [
    {"tag": "rainbow-vless-xhttp"},
    {"tag": "rainbow-vless-tcp"},
    {"tag": "custom"}
  ],
  "routing": {"rules": [
    {"user": ["rainbow-xhttp-warp"], "outboundTag": "rainbow-warp"},
    {"user": ["rainbow-tcp-warp"], "outboundTag": "rainbow-warp"}
  ]},
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "rainbow-warp", "protocol": "wireguard"}
  ]
}
EOF

write_xray_removal_config "$tmp/xray.json" "$tmp/xray-1.json" '["xhttp"]'
jq -e '
  ([.inbounds[].tag] == ["rainbow-vless-tcp", "custom"])
  and ([.routing.rules[].user[0]] == ["rainbow-tcp-warp"])
  and any(.outbounds[]; .tag == "rainbow-warp")
' "$tmp/xray-1.json" >/dev/null

write_xray_removal_config "$tmp/xray-1.json" "$tmp/xray-2.json" '["tcp"]'
jq -e '
  ([.inbounds[].tag] == ["custom"])
  and (.routing.rules | length == 0)
  and (all(.outbounds[]; .tag != "rainbow-warp"))
' "$tmp/xray-2.json" >/dev/null

cat > "$tmp/sing-box.json" <<'EOF'
{
  "inbounds": [
    {"tag": "rainbow-anytls"},
    {"tag": "rainbow-tuic"},
    {"tag": "custom"}
  ],
  "route": {"rules": [
    {"auth_user": ["rainbow-anytls-warp"], "outbound": "rainbow-warp"},
    {"auth_user": ["rainbow-tuic-warp"], "outbound": "rainbow-warp"}
  ]},
  "endpoints": [
    {"tag": "rainbow-warp", "type": "wireguard"},
    {"tag": "custom-endpoint", "type": "wireguard"}
  ]
}
EOF

write_sing_box_removal_config "$tmp/sing-box.json" "$tmp/sing-box-1.json" '["anytls"]'
jq -e '
  ([.inbounds[].tag] == ["rainbow-tuic", "custom"])
  and ([.route.rules[].auth_user[0]] == ["rainbow-tuic-warp"])
  and any(.endpoints[]; .tag == "rainbow-warp")
' "$tmp/sing-box-1.json" >/dev/null

write_sing_box_removal_config "$tmp/sing-box-1.json" "$tmp/sing-box-2.json" '["tuic"]'
jq -e '
  ([.inbounds[].tag] == ["custom"])
  and (.route.rules | length == 0)
  and (all(.endpoints[]; .tag != "rainbow-warp"))
' "$tmp/sing-box-2.json" >/dev/null

install -d -m 0700 "$XRAY_HOME" "$SING_BOX_HOME"
install -m 0600 "$tmp/xray.json" "$XRAY_HOME/config.json"
install -m 0600 "$tmp/sing-box.json" "$SING_BOX_HOME/config.json"
discover_removable_nodes
[[ "$REMOVE_NODE_COUNT" == "4" ]]
[[ "${REMOVE_NODE_TYPES[*]}" == "xhttp tcp tuic anytls" ]]

select_action <<< "8" >/dev/null
[[ "$ACTION" == "remove-nodes" ]]

printf '批量卸载节点测试通过。\n'
