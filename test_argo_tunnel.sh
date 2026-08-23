#!/usr/bin/env bash

set -Eeuo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"

source "$(dirname "$0")/rainbow.sh"
install -d -m 0700 "$XRAY_HOME"
printf '{"inbounds":[],"outbounds":[],"routing":{"rules":[]}}\n' > "$tmp/base.json"

NODE_TYPE="ws-named-tunnel"
NODE_PORT=32123
NODE_UUID="11111111-1111-4111-8111-111111111111"
NODE_WARP_UUID=""
WARP_MODE="direct"
NODE_PATH="/fixed"
NODE_SERVER_NAME="tunnel.example.com"
NODE_ADDRESS="www.ox.ac.uk"
NODE_PRIVATE_KEY=""
NODE_PUBLIC_KEY=""
NODE_SHORT_ID=""

write_xray_node_config "$tmp/base.json" "$tmp/config.json"
jq -e '
  .inbounds | length == 1
  and .[0].tag == "rainbow-vless-ws-named-tunnel"
  and .[0].listen == "127.0.0.1"
  and .[0].port == 32123
  and .[0].streamSettings.network == "ws"
  and .[0].streamSettings.security == "none"
  and .[0].streamSettings.wsSettings.path == "/fixed"
' "$tmp/config.json" >/dev/null

NODE_PORT=443
printf 'test\n' > "$NODE_PREFIX_FILE"
save_xray_client_info >/dev/null
grep -Fx '类型：test-Rainbow-ARGO' "$XRAY_HOME/client-ws-named-tunnel.txt" >/dev/null
grep -F '#test-Rainbow-ARGO' "$XRAY_HOME/client-ws-named-tunnel.txt" >/dev/null

QUICK_CALLED=0
NAMED_CALLED=0
read_quick_tunnel_node_details() { QUICK_CALLED=1; }
read_named_tunnel_node_details() { NAMED_CALLED=1; }

NODE_TYPE="ws-tunnel"
read_tunnel_node_details <<< "" >/dev/null
[[ "$NODE_TYPE" == "ws-tunnel" && "$QUICK_CALLED" == "1" ]]

read_tunnel_node_details <<< "test-token" >/dev/null
[[ "$NODE_TYPE" == "ws-named-tunnel" && "$NAMED_CALLED" == "1" \
  && "$NODE_TUNNEL_TOKEN" == "test-token" ]]

printf 'Argo 隧道配置测试通过。\n'
