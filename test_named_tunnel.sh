#!/usr/bin/env bash

set -Eeuo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

source "$(dirname "$0")/rainbow.sh"
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
write_xray_client_block "$tmp/client.txt" "$NODE_UUID" "test" "直出"
grep -F '分享链接：vless://11111111-1111-4111-8111-111111111111@www.ox.ac.uk:443?encryption=none&security=tls&sni=tunnel.example.com&fp=chrome&type=ws&host=tunnel.example.com&path=%2Ffixed#test' \
  "$tmp/client.txt" >/dev/null

printf '固定隧道配置测试通过。\n'
