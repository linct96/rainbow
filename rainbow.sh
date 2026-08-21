#!/usr/bin/env bash

set -Eeuo pipefail

readonly SING_BOX_REPO="SagerNet/sing-box"
readonly XRAY_REPO="XTLS/Xray-core"
readonly RAINBOW_URL="https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh"
readonly RAINBOW_BIN="/usr/local/bin/rb"
readonly RAINBOW_HOME="${HOME:-/root}/rainbow"
readonly SING_BOX_HOME="$RAINBOW_HOME/sing-box"
readonly XRAY_HOME="$RAINBOW_HOME/xray"
readonly SING_BOX_SERVICE="rainbow-sing-box"
readonly XRAY_SERVICE="rainbow-xray"

log() {
  printf '[安装] %s\n' "$*"
}

die() {
  printf '[错误] %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "请使用 root 用户运行：sudo bash $0"
}

require_commands() {
  local command_name
  for command_name in curl jq sha256sum systemctl install; do
    command -v "$command_name" >/dev/null 2>&1 || die "缺少依赖：${command_name}"
  done
}

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *) die "不支持的系统架构：$(uname -m)，当前仅支持 amd64 和 arm64" ;;
  esac
}

install_rainbow_command() {
  local source_file=${BASH_SOURCE[0]} action="安装"

  if [[ -e "$RAINBOW_BIN" && "$source_file" -ef "$RAINBOW_BIN" ]]; then
    return
  fi

  if [[ -e "$RAINBOW_BIN" ]]; then
    action="更新"
  fi

  download_rainbow
  log "rb 命令已${action}：${RAINBOW_BIN}"
}

download_rainbow() {
  local update_file="$TMP_DIR/rainbow.sh"

  download "$RAINBOW_URL" "$update_file"
  bash -n "$update_file" || die "更新脚本语法检查失败"
  install -d -m 0755 /usr/local/bin
  install -m 0755 "$update_file" "$RAINBOW_BIN"
}

show_installation_status() {
  local product binary_path

  printf '%s\n' '当前安装状态：'
  for product in sing-box xray; do
    binary_path="$RAINBOW_HOME/$product/$product"
    if [[ -x "$binary_path" ]]; then
      printf '  %-8s 已安装（路径：%s）\n' "$product" "$binary_path"
    else
      printf '  %-8s 未安装（路径：-）\n' "$product"
    fi
  done
  printf '\n'
}

select_action() {
  printf '%s\n' \
    '请选择操作：' \
    '1) sing-box' \
    '2) Xray' \
    '3) 搭建 X-ray 节点' \
    '4) 更新 rainbow'

  while true; do
    read -r -p '请输入 [1/2/3/4]：' choice
    case "$choice" in
      1) ACTION="install"; PRODUCT="sing-box"; REPO="$SING_BOX_REPO"; return ;;
      2) ACTION="install"; PRODUCT="xray"; REPO="$XRAY_REPO"; return ;;
      3) ACTION="node"; return ;;
      4) ACTION="update"; return ;;
      *) printf '无效选项，请输入 1、2、3 或 4。\n' >&2 ;;
    esac
  done
}

read_version() {
  local input latest_json
  read -r -p "请输入 ${PRODUCT} 版本号（直接回车安装最新版）：" input

  if [[ -z "$input" ]]; then
    log "正在查询最新版本"
    latest_json=$(curl --retry 3 -fsSL "https://api.github.com/repos/${REPO}/releases/latest") \
      || die "查询最新版本失败"
    VERSION=$(jq -r '.tag_name // empty' <<<"$latest_json")
    [[ -n "$VERSION" ]] || die "未获取到最新版本号"
  else
    VERSION="${input#v}"
    [[ "$VERSION" =~ ^[0-9]+([.][0-9A-Za-z-]+)+$ ]] \
      || die "版本号格式错误，例如：1.13.19 或 v1.13.19"
    VERSION="v${VERSION}"
  fi

  VERSION_NUMBER="${VERSION#v}"
  log "准备安装 ${PRODUCT} ${VERSION}"
}

download() {
  local url=$1 output=$2
  curl --retry 3 -fL "$url" -o "$output" \
    || die "下载失败：${url}"
}

update_rainbow() {
  download_rainbow
  log "rainbow 已更新：${RAINBOW_BIN}"
}

verify_sha256() {
  local file=$1 expected=$2 actual
  actual=$(sha256sum "$file" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || die "SHA-256 校验失败"
}

install_sing_box() {
  local archive_name archive_url api_url digest expected extracted_dir
  archive_name="sing-box-${VERSION_NUMBER}-linux-${ARCH}.tar.gz"
  archive_url="https://github.com/${SING_BOX_REPO}/releases/download/${VERSION}/${archive_name}"
  api_url="https://api.github.com/repos/${SING_BOX_REPO}/releases/tags/${VERSION}"

  download "$archive_url" "$TMP_DIR/$archive_name"
  digest=$(curl --retry 3 -fsSL "$api_url" \
    | jq -r --arg name "$archive_name" '.assets[] | select(.name == $name) | .digest // empty') \
    || die "获取校验值失败"
  if [[ "$digest" == sha256:* ]]; then
    expected=${digest#sha256:}
    verify_sha256 "$TMP_DIR/$archive_name" "$expected"
  else
    log "该历史版本未提供 SHA-256，跳过校验"
  fi

  tar -xzf "$TMP_DIR/$archive_name" -C "$TMP_DIR"
  extracted_dir="$TMP_DIR/sing-box-${VERSION_NUMBER}-linux-${ARCH}"
  install -d -m 0755 "$SING_BOX_HOME"
  install -m 0755 "$extracted_dir/sing-box" "$SING_BOX_HOME/sing-box"

  if [[ ! -e "$SING_BOX_HOME/config.json" ]]; then
    install -m 0644 /dev/null "$SING_BOX_HOME/config.json"
    printf '%s\n' '{"log":{"level":"info"},"inbounds":[]}' > "$SING_BOX_HOME/config.json"
  fi

  install -m 0644 /dev/null "/etc/systemd/system/${SING_BOX_SERVICE}.service"
  cat > "/etc/systemd/system/${SING_BOX_SERVICE}.service" <<EOF
[Unit]
Description=Rainbow sing-box service
After=network.target

[Service]
ExecStart=$SING_BOX_HOME/sing-box run -c $SING_BOX_HOME/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  "$SING_BOX_HOME/sing-box" check -c "$SING_BOX_HOME/config.json"
  systemctl daemon-reload
  systemctl enable "$SING_BOX_SERVICE"
  systemctl restart "$SING_BOX_SERVICE"
  "$SING_BOX_HOME/sing-box" version
  systemctl --no-pager --full status "$SING_BOX_SERVICE" || true
}

install_xray() {
  local xray_arch archive_name archive_url digest_url expected
  command -v unzip >/dev/null 2>&1 || die "安装 Xray 需要 unzip"

  case "$ARCH" in
    amd64) xray_arch="64" ;;
    arm64) xray_arch="arm64-v8a" ;;
  esac

  archive_name="Xray-linux-${xray_arch}.zip"
  archive_url="https://github.com/${XRAY_REPO}/releases/download/${VERSION}/${archive_name}"
  digest_url="${archive_url}.dgst"

  download "$archive_url" "$TMP_DIR/$archive_name"
  download "$digest_url" "$TMP_DIR/$archive_name.dgst"
  expected=$(awk -F '= ' '/^SHA2-256= / {print $2; exit}' "$TMP_DIR/$archive_name.dgst")
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "未获取到有效的 SHA-256 校验值"
  verify_sha256 "$TMP_DIR/$archive_name" "${expected,,}"

  unzip -q "$TMP_DIR/$archive_name" -d "$TMP_DIR/xray"
  install -d -m 0755 "$XRAY_HOME"
  install -m 0755 "$TMP_DIR/xray/xray" "$XRAY_HOME/xray"
  install -m 0644 "$TMP_DIR/xray/geoip.dat" "$TMP_DIR/xray/geosite.dat" "$XRAY_HOME/"

  if [[ ! -e "$XRAY_HOME/config.json" ]]; then
    install -m 0644 /dev/null "$XRAY_HOME/config.json"
    printf '%s\n' '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom"}]}' \
      > "$XRAY_HOME/config.json"
  fi

  install -m 0644 /dev/null "/etc/systemd/system/${XRAY_SERVICE}.service"
  cat > "/etc/systemd/system/${XRAY_SERVICE}.service" <<EOF
[Unit]
Description=Rainbow Xray service
After=network.target

[Service]
Environment=XRAY_LOCATION_ASSET=$XRAY_HOME
ExecStart=$XRAY_HOME/xray run -config $XRAY_HOME/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  "$XRAY_HOME/xray" run -test -config "$XRAY_HOME/config.json"
  systemctl daemon-reload
  systemctl enable "$XRAY_SERVICE"
  systemctl restart "$XRAY_SERVICE"
  "$XRAY_HOME/xray" version
  systemctl --no-pager --full status "$XRAY_SERVICE" || true
}

random_hex() {
  od -An -N "$1" -tx1 /dev/urandom | tr -d ' \n'
}

port_in_use() {
  ss -H -ltn | awk -v port="$1" '
    {
      endpoint = $4
      sub(/^.*:/, "", endpoint)
      if (endpoint == port) found = 1
    }
    END { exit !found }
  '
}

random_high_port() {
  local i port

  for ((i = 0; i < 100; i++)); do
    port=$((10000 + $(od -An -N 4 -tu4 /dev/urandom) % 55536))
    if ! port_in_use "$port"; then
      printf '%s\n' "$port"
      return
    fi
  done

  return 1
}

read_node_port() {
  local input port

  while true; do
    read -r -p '请输入监听端口（直接回车随机生成）：' input
    if [[ -z "$input" ]]; then
      NODE_PORT=$(random_high_port) || {
        printf '未找到可用的随机端口。\n' >&2
        return 1
      }
      printf '已选择随机端口：%s\n' "$NODE_PORT"
      return
    fi

    if [[ ! "$input" =~ ^[0-9]+$ || ${#input} -gt 5 ]]; then
      printf '端口必须是 1 到 65535 之间的整数。\n' >&2
    else
      port=$((10#$input))
      if ((port < 1 || port > 65535)); then
        printf '端口必须是 1 到 65535 之间的整数。\n' >&2
      elif port_in_use "$port"; then
        printf '端口 %s 已被占用。\n' "$port" >&2
      else
        NODE_PORT=$port
        return
      fi
    fi
  done
}

detect_public_ipv4() {
  local address
  address=$(curl --retry 2 --connect-timeout 5 -4 -fsSL https://api.ipify.org 2>/dev/null) || return 1
  [[ "$address" =~ ^([0-9]{1,3}[.]){3}[0-9]{1,3}$ ]] || return 1
  printf '%s\n' "$address"
}

read_node_details() {
  local default_address input

  read_node_port || return
  default_address=$(detect_public_ipv4 || true)

  while true; do
    if [[ -n "$default_address" ]]; then
      read -r -p "请输入节点地址（直接回车使用 ${default_address}）：" input
      NODE_ADDRESS=${input:-$default_address}
    else
      read -r -p '请输入节点 IP 或域名：' NODE_ADDRESS
    fi
    [[ "$NODE_ADDRESS" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && break
    printf '节点地址格式错误。\n' >&2
  done

  read -r -p '请输入 REALITY 伪装域名（直接回车使用 www.apple.com）：' input
  NODE_SERVER_NAME=${input:-www.apple.com}
  [[ "$NODE_SERVER_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || {
    printf '伪装域名格式错误。\n' >&2
    return 1
  }

  NODE_PATH=""
  if [[ "$NODE_TYPE" == "xhttp" ]]; then
    read -r -p '请输入 XHTTP 路径（直接回车随机生成）：' input
    NODE_PATH=${input:-/$(random_hex 4)}
    [[ "$NODE_PATH" == /* ]] || NODE_PATH="/$NODE_PATH"
    [[ "$NODE_PATH" =~ ^/[A-Za-z0-9._~/-]*$ ]] || {
      printf 'XHTTP 路径只能包含字母、数字、/、-、_、. 和 ~。\n' >&2
      return 1
    }
    printf 'XHTTP 路径：%s\n' "$NODE_PATH"
  fi
}

generate_xray_credentials() {
  local key_output

  NODE_UUID=$("$XRAY_HOME/xray" uuid)
  key_output=$("$XRAY_HOME/xray" x25519)
  NODE_PRIVATE_KEY=$(awk -F ': *' 'tolower($1) ~ /^private[[:space:]]*key$/ {print $2; exit}' \
    <<<"$key_output")
  NODE_PUBLIC_KEY=$(awk -F ': *' \
    'tolower($1) ~ /^(password|public[[:space:]]*key)/ {print $2; exit}' <<<"$key_output")
  NODE_SHORT_ID=$(random_hex 8)

  [[ "$NODE_UUID" =~ ^[0-9a-fA-F-]{36}$ && -n "$NODE_PRIVATE_KEY" && -n "$NODE_PUBLIC_KEY" ]] \
    || return 1
}

write_xray_node_config() {
  local config_file=$1 flow network

  if [[ "$NODE_TYPE" == "xhttp" ]]; then
    network="xhttp"
    flow=""
  else
    network="tcp"
    flow="xtls-rprx-vision"
  fi

  jq -n \
    --argjson port "$NODE_PORT" \
    --arg uuid "$NODE_UUID" \
    --arg flow "$flow" \
    --arg network "$network" \
    --arg path "$NODE_PATH" \
    --arg target "${NODE_SERVER_NAME}:443" \
    --arg server_name "$NODE_SERVER_NAME" \
    --arg private_key "$NODE_PRIVATE_KEY" \
    --arg short_id "$NODE_SHORT_ID" '
      {
        log: {loglevel: "warning"},
        inbounds: [{
          listen: "0.0.0.0",
          port: $port,
          protocol: "vless",
          settings: {
            clients: [{id: $uuid, flow: $flow}],
            decryption: "none"
          },
          streamSettings: ({
            network: $network,
            security: "reality",
            realitySettings: {
              show: false,
              target: $target,
              xver: 0,
              serverNames: [$server_name],
              privateKey: $private_key,
              shortIds: [$short_id]
            }
          } + if $network == "xhttp" then {
            xhttpSettings: {path: $path}
          } else {} end),
          sniffing: {
            enabled: true,
            destOverride: ["http", "tls", "quic"]
          }
        }],
        outbounds: [
          {protocol: "freedom", tag: "direct"},
          {protocol: "blackhole", tag: "block"}
        ]
      }
    ' > "$config_file"
}

save_xray_client_info() {
  local encoded_path label uri

  if [[ "$NODE_TYPE" == "xhttp" ]]; then
    encoded_path=$(jq -rn --arg value "$NODE_PATH" '$value | @uri')
    label="Rainbow-XHTTP"
    uri="vless://${NODE_UUID}@${NODE_ADDRESS}:${NODE_PORT}?encryption=none&security=reality&sni=${NODE_SERVER_NAME}&fp=chrome&pbk=${NODE_PUBLIC_KEY}&sid=${NODE_SHORT_ID}&type=xhttp&path=${encoded_path}&mode=auto#${label}"
  else
    label="Rainbow-TCP"
    uri="vless://${NODE_UUID}@${NODE_ADDRESS}:${NODE_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${NODE_SERVER_NAME}&fp=chrome&pbk=${NODE_PUBLIC_KEY}&sid=${NODE_SHORT_ID}&type=tcp&headerType=none#${label}"
  fi

  install -m 0600 /dev/null "$XRAY_HOME/client.txt"
  printf '%s\n' \
    "类型：$label" \
    "地址：$NODE_ADDRESS" \
    "端口：$NODE_PORT" \
    "伪装域名：$NODE_SERVER_NAME" \
    "XHTTP 路径：${NODE_PATH:--}" \
    "UUID：$NODE_UUID" \
    "Public Key：$NODE_PUBLIC_KEY" \
    "Short ID：$NODE_SHORT_ID" \
    "分享链接：$uri" > "$XRAY_HOME/client.txt"

  printf '\n节点搭建完成：\n'
  cat "$XRAY_HOME/client.txt"
  printf '客户端信息已保存至：%s\n\n' "$XRAY_HOME/client.txt"
}

setup_xray_node() {
  local backup_file config_file="$TMP_DIR/xray-node-config.json"
  local service_file="/etc/systemd/system/${XRAY_SERVICE}.service"

  if [[ ! -x "$XRAY_HOME/xray" || ! -f "$XRAY_HOME/config.json" \
    || ! -f "$service_file" ]] \
    || ! grep -qx "ExecStart=$XRAY_HOME/xray run -config $XRAY_HOME/config.json" "$service_file"; then
    printf '请先通过 Rainbow 安装 Xray。\n' >&2
    return 1
  fi
  command -v ss >/dev/null 2>&1 || {
    printf '搭建节点需要 ss 命令。\n' >&2
    return 1
  }

  read_node_details || return
  generate_xray_credentials || {
    printf '生成 Xray 凭据失败。\n' >&2
    return 1
  }
  write_xray_node_config "$config_file"
  "$XRAY_HOME/xray" run -test -config "$config_file" || {
    printf 'Xray 配置验证失败，原配置未修改。\n' >&2
    return 1
  }

  backup_file=$(mktemp "$XRAY_HOME/config.json.backup.XXXXXX")
  install -m 0600 "$XRAY_HOME/config.json" "$backup_file"
  install -m 0600 "$config_file" "$XRAY_HOME/config.json"
  if ! systemctl restart "$XRAY_SERVICE"; then
    install -m 0600 "$backup_file" "$XRAY_HOME/config.json"
    systemctl restart "$XRAY_SERVICE" || true
    printf 'Xray 启动失败，已恢复原配置：%s\n' "$backup_file" >&2
    return 1
  fi

  log "原配置已备份：$backup_file"
  save_xray_client_info
}

manage_xray_nodes() {
  local choice

  while true; do
    printf '%s\n' \
      '请选择 X-ray 节点类型：' \
      '1) VLESS + REALITY + XHTTP' \
      '2) VLESS + REALITY + TCP' \
      '0) 返回'
    read -r -p '请输入 [0/1/2]：' choice
    case "$choice" in
      1) NODE_TYPE="xhttp"; setup_xray_node || true ;;
      2) NODE_TYPE="tcp"; setup_xray_node || true ;;
      0) return ;;
      *) printf '无效选项，请输入 0、1 或 2。\n' >&2 ;;
    esac
  done
}

main() {
  require_root
  require_commands

  TMP_DIR=$(mktemp -d)
  readonly TMP_DIR
  trap 'rm -rf "$TMP_DIR"' EXIT

  install_rainbow_command

  while true; do
    show_installation_status
    select_action

    if [[ "$ACTION" == "update" ]]; then
      update_rainbow
      continue
    fi
    if [[ "$ACTION" == "node" ]]; then
      manage_xray_nodes
      continue
    fi

    detect_arch
    read_version

    case "$PRODUCT" in
      sing-box) install_sing_box ;;
      xray) install_xray ;;
    esac

    log "${PRODUCT} ${VERSION} 安装完成"
  done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
