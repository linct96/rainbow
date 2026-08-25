#!/usr/bin/env bash

set -Eeuo pipefail

readonly SING_BOX_REPO="SagerNet/sing-box"
readonly XRAY_REPO="XTLS/Xray-core"
readonly WGCF_REPO="ViRb3/wgcf"
readonly LEGO_REPO="go-acme/lego"
readonly CLOUDFLARED_REPO="cloudflare/cloudflared"
readonly RAINBOW_URL="https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh"
readonly RAINBOW_BIN="/usr/local/bin/rb"
readonly RAINBOW_HOME="${HOME:-/root}/rainbow"
readonly NODE_PREFIX_FILE="$RAINBOW_HOME/node-prefix"
readonly SING_BOX_HOME="$RAINBOW_HOME/sing-box"
readonly XRAY_HOME="$RAINBOW_HOME/xray"
readonly WARP_HOME="$XRAY_HOME/warp"
readonly WGCF_BIN="$WARP_HOME/wgcf"
readonly WGCF_ACCOUNT="$WARP_HOME/wgcf-account.toml"
readonly WGCF_PROFILE="$WARP_HOME/wgcf-profile.conf"
readonly TLS_HOME="$RAINBOW_HOME/tls"
readonly SELF_SIGNED_TLS_HOME="$TLS_HOME/self-signed"
readonly SELF_SIGNED_TLS_CERT="$SELF_SIGNED_TLS_HOME/cert.pem"
readonly SELF_SIGNED_TLS_KEY="$SELF_SIGNED_TLS_HOME/key.pem"
readonly ACME_TLS_HOME="$TLS_HOME/acme"
readonly ACME_TLS_CERT="$ACME_TLS_HOME/cert.pem"
readonly ACME_TLS_KEY="$ACME_TLS_HOME/key.pem"
readonly TLS_DOMAIN_FILE="$TLS_HOME/domain"
readonly LEGACY_TLS_CERT="$TLS_HOME/cert.pem"
readonly LEGACY_TLS_KEY="$TLS_HOME/key.pem"
readonly LEGACY_TLS_MODE_FILE="$TLS_HOME/mode"
readonly LEGACY_SING_BOX_TLS_HOME="$SING_BOX_HOME/tls"
readonly ACME_HOME="$RAINBOW_HOME/acme"
readonly ACME_BIN="$ACME_HOME/lego"
readonly ACME_DATA_HOME="$ACME_HOME/data"
readonly ACME_CF_TOKEN_FILE="$ACME_HOME/cf-token"
readonly ACME_SERVICE="rainbow-acme"
readonly ACME_TIMER="rainbow-acme.timer"
readonly SELF_SIGNED_TLS_SERVER_NAME="rainbow.local"
readonly SING_BOX_SERVICE="rainbow-sing-box"
readonly XRAY_SERVICE="rainbow-xray"
readonly CLOUDFLARED_HOME="$RAINBOW_HOME/cloudflared"
readonly CLOUDFLARED_BIN="$CLOUDFLARED_HOME/cloudflared"
readonly CLOUDFLARED_LOG="$CLOUDFLARED_HOME/quick-tunnel.log"
readonly CLOUDFLARED_HOST_FILE="$CLOUDFLARED_HOME/hostname"
readonly CLOUDFLARED_ADDRESS_FILE="$CLOUDFLARED_HOME/client-address"
readonly CLOUDFLARED_SERVICE="rainbow-cloudflared-quick"
readonly CLOUDFLARED_NAMED_TOKEN_FILE="$CLOUDFLARED_HOME/named-token"
readonly CLOUDFLARED_NAMED_HOST_FILE="$CLOUDFLARED_HOME/named-hostname"
readonly CLOUDFLARED_NAMED_SERVICE="rainbow-cloudflared-named"

SING_BOX_TLS_CERT="$SELF_SIGNED_TLS_CERT"
SING_BOX_TLS_KEY="$SELF_SIGNED_TLS_KEY"
SING_BOX_TLS_IS_PUBLIC=0
SING_BOX_TLS_SERVER_NAME="$SELF_SIGNED_TLS_SERVER_NAME"

INFO_COLOR=""
INFO_RESET_COLOR=""
WARN_COLOR=""
WARN_RESET_COLOR=""
ERROR_COLOR=""
ERROR_RESET_COLOR=""
if [[ -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  [[ -t 1 ]] && INFO_COLOR=$'\033[32m' && INFO_RESET_COLOR=$'\033[0m'
  [[ -t 2 ]] && WARN_COLOR=$'\033[33m' && ERROR_COLOR=$'\033[31m' \
    && WARN_RESET_COLOR=$'\033[0m' && ERROR_RESET_COLOR=$'\033[0m'
fi
readonly INFO_COLOR INFO_RESET_COLOR WARN_COLOR WARN_RESET_COLOR ERROR_COLOR \
  ERROR_RESET_COLOR

info() {
  printf '%s[INFO]%s %s\n' "$INFO_COLOR" "$INFO_RESET_COLOR" "$*"
}

warn() {
  printf '%s[WARN]%s %s\n' "$WARN_COLOR" "$WARN_RESET_COLOR" "$*" >&2
}

error() {
  printf '%s[ERROR]%s %s\n' "$ERROR_COLOR" "$ERROR_RESET_COLOR" "$*" >&2
}

die() {
  error "$*"
  exit 1
}

clear_screen() {
  if [[ -t 1 ]]; then
    printf '\033[2J\033[H'
  fi
}

show_header() {
  printf 'Rainbow - %s\n\n' "$1"
}

pause_menu() {
  [[ -t 0 ]] || return 0
  printf '\n'
  read -r -p '按 Enter 键返回菜单...' _
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "请使用 root 用户运行：sudo bash $0"
}

require_commands() {
  local command_name
  for command_name in curl jq sha256sum systemctl install tar unzip openssl; do
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
  local action="安装"

  if [[ -e "$RAINBOW_BIN" && "$0" -ef "$RAINBOW_BIN" ]]; then
    return
  fi

  if [[ -e "$RAINBOW_BIN" ]]; then
    action="更新"
  fi

  download_rainbow
  info "rb 命令已${action}：${RAINBOW_BIN}"
}

download_rainbow() {
  local update_file="$TMP_DIR/rainbow.sh"

  download "$RAINBOW_URL" "$update_file"
  bash -n "$update_file" || die "更新脚本语法检查失败"
  install -d -m 0755 /usr/local/bin
  install -m 0755 "$update_file" "$RAINBOW_BIN"
}

show_installation_status() {
  local product binary_path tunnel_status="未配置"

  printf '%s\n' '当前安装状态：'
  for product in sing-box xray; do
    binary_path="$RAINBOW_HOME/$product/$product"
    if [[ -x "$binary_path" ]]; then
      printf '  %-8s 已安装（路径：%s）\n' "$product" "$binary_path"
    else
      printf '  %-8s 未安装（路径：-）\n' "$product"
    fi
  done
  if systemctl is-active --quiet "$CLOUDFLARED_SERVICE"; then
    tunnel_status="运行中"
    [[ ! -s "$CLOUDFLARED_HOST_FILE" ]] \
      || tunnel_status+="（$(<"$CLOUDFLARED_HOST_FILE")）"
  elif systemctl is-active --quiet "$CLOUDFLARED_NAMED_SERVICE"; then
    tunnel_status="运行中"
    [[ ! -s "$CLOUDFLARED_NAMED_HOST_FILE" ]] \
      || tunnel_status+="（$(<"$CLOUDFLARED_NAMED_HOST_FILE")）"
  elif systemctl cat "$CLOUDFLARED_SERVICE" >/dev/null 2>&1 \
    || systemctl cat "$CLOUDFLARED_NAMED_SERVICE" >/dev/null 2>&1; then
    tunnel_status="未运行"
  fi
  printf '  %-8s %s\n' '隧道' "$tunnel_status"
  show_tls_status
  printf '  %-8s %s\n' '节点前缀' "$(get_node_prefix)"
  printf '\n'
}

get_node_prefix() {
  local prefix

  if [[ -s "$NODE_PREFIX_FILE" ]]; then
    IFS= read -r prefix < "$NODE_PREFIX_FILE"
  fi
  printf '%s\n' "${prefix:-$(hostname)}"
}

configure_node_prefix() {
  local default_prefix input

  default_prefix=$(hostname)
  show_header '节点名称设置'
  printf '当前节点前缀：%s\n' "$(get_node_prefix)"
  read -r -p "请输入节点前缀（直接回车使用 ${default_prefix}）：" input
  input=${input:-$default_prefix}

  install -d -m 0700 "$RAINBOW_HOME"
  printf '%s\n' "$input" > "$NODE_PREFIX_FILE"
  chmod 0600 "$NODE_PREFIX_FILE"
  printf '节点名称将使用：%s-{协议}\n' "$input"
}

show_tls_status() {
  local domain="-" self_signed_status acme_status
  if [[ -s "$SELF_SIGNED_TLS_CERT" && -s "$SELF_SIGNED_TLS_KEY" ]]; then
    self_signed_status="已配置"
  elif [[ -e "$SELF_SIGNED_TLS_CERT" || -e "$SELF_SIGNED_TLS_KEY" ]]; then
    self_signed_status="状态异常"
  else
    self_signed_status="未配置"
  fi
  [[ -s "$TLS_DOMAIN_FILE" ]] && IFS= read -r domain < "$TLS_DOMAIN_FILE"
  if [[ -s "$ACME_TLS_CERT" && -s "$ACME_TLS_KEY" ]]; then
    acme_status="${domain}，已配置"
  elif [[ -e "$ACME_TLS_CERT" || -e "$ACME_TLS_KEY" ]]; then
    acme_status="${domain}，状态异常"
  else
    acme_status="未配置"
  fi
  printf '  %-8s 自签证书（%s），ACME（%s）\n' \
    'TLS' "$self_signed_status" "$acme_status"
}

select_action() {
  printf '%s\n' \
    '请选择操作：' \
    '1) 查看所有节点' \
    '2) 搭建 X-ray 节点' \
    '3) 搭建 sing-box 节点' \
    '4) 编辑节点' \
    '5) 卸载节点' \
    '6) 证书管理' \
    '7) 设置节点名称前缀' \
    '99) 一键卸载' \
    '0) 退出脚本' \
    ''

  while true; do
    read -r -p '请输入 [0/1/2/3/4/5/6/7/99]：' choice
    case "$choice" in
      1) ACTION="show-nodes"; return ;;
      2) ACTION="xray-node"; return ;;
      3) ACTION="sing-box-node"; return ;;
      4) ACTION="edit-node"; return ;;
      5) ACTION="remove-nodes"; return ;;
      6) ACTION="tls"; return ;;
      7) ACTION="node-prefix"; return ;;
      99) ACTION="uninstall"; return ;;
      0) exit ;;
      *) printf '无效选项，请输入 0、1、2、3、4、5、6、7 或 99。\n' >&2 ;;
    esac
  done
}

read_latest_version() {
  local latest_json
  info "正在查询 ${PRODUCT} 最新版本"
  latest_json=$(curl --retry 3 -fsSL "https://api.github.com/repos/${REPO}/releases/latest") \
    || die "查询 ${PRODUCT} 最新版本失败"
  VERSION=$(jq -r '.tag_name // empty' <<<"$latest_json")
  [[ -n "$VERSION" ]] || die "未获取到 ${PRODUCT} 最新版本号"
  VERSION_NUMBER="${VERSION#v}"
  info "准备安装 ${PRODUCT} ${VERSION}"
}

download() {
  local url=$1 output=$2
  curl --retry 3 -fL "$url" -o "$output" \
    || die "下载失败：${url}"
}

uninstall_rainbow() {
  local answer unit

  printf '%s\n' \
    '此操作将停止并删除 Rainbow 管理的 Xray、sing-box、节点配置和 rb 命令。' \
    '删除后无法恢复。'
  read -r -p '请输入 UNINSTALL 确认卸载：' answer
  [[ "$answer" == "UNINSTALL" ]] || {
    printf '已取消卸载。\n'
    return 1
  }

  for unit in "$ACME_TIMER" "$ACME_SERVICE" "$CLOUDFLARED_SERVICE" \
    "$CLOUDFLARED_NAMED_SERVICE" \
    "$XRAY_SERVICE" "$SING_BOX_SERVICE"; do
    systemctl cat "$unit" >/dev/null 2>&1 || continue
    systemctl disable --now "$unit" || {
      printf '停止服务 %s 失败，卸载已中止。\n' "$unit" >&2
      return 1
    }
  done

  rm -f "/etc/systemd/system/${XRAY_SERVICE}.service" \
    "/etc/systemd/system/${SING_BOX_SERVICE}.service" \
    "/etc/systemd/system/${CLOUDFLARED_SERVICE}.service" \
    "/etc/systemd/system/${CLOUDFLARED_NAMED_SERVICE}.service" \
    "/etc/systemd/system/${ACME_SERVICE}.service" \
    "/etc/systemd/system/${ACME_TIMER}" || return
  systemctl daemon-reload || return
  rm -rf -- "$RAINBOW_HOME" || return
  rm -f -- "$RAINBOW_BIN" || return
  printf 'Rainbow 已卸载。\n'
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
    warn "该历史版本未提供 SHA-256，跳过校验"
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

install_cloudflared() {
  local actual release_json asset_name asset_url digest expected

  detect_arch
  asset_name="cloudflared-linux-${ARCH}"
  info '正在查询 cloudflared 最新版本'
  release_json=$(curl --retry 3 -fsSL \
    "https://api.github.com/repos/${CLOUDFLARED_REPO}/releases/latest") \
    || {
      printf '查询 cloudflared 最新版本失败。\n' >&2
      return 1
    }
  asset_url=$(jq -r --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")
  digest=$(jq -r --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .digest // empty' <<<"$release_json")
  [[ -n "$asset_url" && "$asset_url" != "null" ]] || {
    printf '未找到 cloudflared 安装包：%s\n' "$asset_name" >&2
    return 1
  }
  [[ "$digest" == sha256:* ]] || {
    printf 'cloudflared Release 未提供 SHA-256 校验值。\n' >&2
    return 1
  }

  curl --retry 3 -fL "$asset_url" -o "$TMP_DIR/$asset_name" || {
    printf '下载 cloudflared 失败。\n' >&2
    return 1
  }
  expected=${digest#sha256:}
  actual=$(sha256sum "$TMP_DIR/$asset_name" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || {
    printf 'cloudflared SHA-256 校验失败。\n' >&2
    return 1
  }
  install -d -m 0700 "$CLOUDFLARED_HOME"
  install -m 0755 "$TMP_DIR/$asset_name" "$CLOUDFLARED_BIN"
  "$CLOUDFLARED_BIN" version
}

rainbow_is_initialized() {
  [[ -x "$XRAY_HOME/xray" && -f "$XRAY_HOME/config.json" \
    && -f "/etc/systemd/system/${XRAY_SERVICE}.service" \
    && -x "$SING_BOX_HOME/sing-box" && -f "$SING_BOX_HOME/config.json" \
    && -f "/etc/systemd/system/${SING_BOX_SERVICE}.service" \
    && -x "$WGCF_BIN" && -s "$WGCF_ACCOUNT" && -s "$WGCF_PROFILE" \
    && -s "$SELF_SIGNED_TLS_CERT" && -s "$SELF_SIGNED_TLS_KEY" ]]
}

initialize_rainbow() {
  detect_arch
  info "开始初始化 Rainbow"

  PRODUCT="xray"
  REPO="$XRAY_REPO"
  read_latest_version
  install_xray

  PRODUCT="sing-box"
  REPO="$SING_BOX_REPO"
  read_latest_version
  install_sing_box

  ensure_warp_profile || die "初始化 WARP 配置失败"
  ensure_self_signed_certificate || die "初始化自签证书失败"
  info "Rainbow 初始化完成"
}

random_hex() {
  od -An -N "$1" -tx1 /dev/urandom | tr -d ' \n'
}

port_in_use() {
  local flags="-ltn" port=$1 protocol=${2:-tcp}
  [[ "$protocol" == "udp" ]] && flags="-lun"

  ss -H "$flags" | awk -v port="$port" '
    {
      endpoint = $4
      sub(/^.*:/, "", endpoint)
      if (endpoint == port) found = 1
    }
    END { exit !found }
  '
}

random_high_port() {
  local i port protocol=${1:-tcp}

  for ((i = 0; i < 100; i++)); do
    port=$((10000 + $(od -An -N 4 -tu4 /dev/urandom) % 55536))
    if ! port_in_use "$port" "$protocol"; then
      printf '%s\n' "$port"
      return
    fi
  done

  return 1
}

read_node_port() {
  local input port protocol=${1:-tcp}

  while true; do
    read -r -p '请输入监听端口（直接回车随机生成）：' input
    if [[ -z "$input" ]]; then
      NODE_PORT=$(random_high_port "$protocol") || {
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
      elif port_in_use "$port" "$protocol"; then
        printf '端口 %s 已被占用。\n' "$port" >&2
      else
        NODE_PORT=$port
        return
      fi
    fi
  done
}

valid_cf_https_port() {
  [[ "$1" =~ ^(443|2053|2083|2087|2096|8443)$ ]]
}

read_cf_https_port() {
  local input port

  while true; do
    read -r -p '请输入 Cloudflare HTTPS 端口 [443]：' input
    input=${input:-443}
    if ! valid_cf_https_port "$input"; then
      printf '仅支持 Cloudflare HTTPS 端口：443、2053、2083、2087、2096、8443。\n' >&2
      continue
    fi
    port=$((10#$input))
    if port_in_use "$port" \
      && ! jq -e --argjson port "$port" '
        any(.inbounds[]?; .tag == "rainbow-vless-ws" and .port == $port)
      ' "$XRAY_HOME/config.json" >/dev/null; then
      printf '端口 %s 已被占用。\n' "$port" >&2
      continue
    fi
    NODE_PORT=$port
    return
  done
}

detect_public_ipv4() {
  local address
  address=$(curl --retry 2 --connect-timeout 5 -4 -fsSL https://api.ipify.org 2>/dev/null) || return 1
  [[ "$address" =~ ^([0-9]{1,3}[.]){3}[0-9]{1,3}$ ]] || return 1
  printf '%s\n' "$address"
}

read_node_address() {
  local default_address input
  default_address=$(detect_public_ipv4 || true)

  while true; do
    if [[ -n "$default_address" ]]; then
      read -r -p "请输入节点地址（直接回车使用 ${default_address}）：" input
      NODE_ADDRESS=${input:-$default_address}
    else
      read -r -p '请输入节点 IP 或域名：' NODE_ADDRESS
    fi
    [[ "$NODE_ADDRESS" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && return
    printf '节点地址格式错误。\n' >&2
  done
}

read_node_details() {
  local input

  if [[ "$NODE_TYPE" == "ws" ]]; then
    read_ws_node_details
    return
  fi
  if [[ "$NODE_TYPE" == "ws-tunnel" || "$NODE_TYPE" == "ws-named-tunnel" ]]; then
    read_tunnel_node_details
    return
  fi

  read_node_port || return
  read_node_address

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

valid_domain_prefix() {
  [[ ${#1} -ge 1 && ${#1} -le 63 \
    && "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]
}

read_ws_node_details() {
  local input root_domain

  valid_acme_certificate || {
    printf 'VLESS + WebSocket 节点必须先配置有效的 ACME 证书。\n' >&2
    return 1
  }
  IFS= read -r root_domain < "$TLS_DOMAIN_FILE"
  read_cf_https_port || return

  while true; do
    printf '当前证书根域名：%s\n' "$root_domain"
    read -r -p '请输入 CDN 域名前缀 [cdn]：' input
    input=$(normalize_domain "${input:-cdn}")
    if valid_domain_prefix "$input"; then
      NODE_DOMAIN_PREFIX=$input
      break
    fi
    printf '域名前缀只能包含小写字母、数字和连字符，且不能以连字符开头或结尾。\n' >&2
  done

  NODE_SERVER_NAME="${NODE_DOMAIN_PREFIX}.${root_domain}"
  NODE_ADDRESS=$NODE_SERVER_NAME
  openssl x509 -in "$ACME_TLS_CERT" -noout -checkhost "$NODE_SERVER_NAME" \
    >/dev/null || {
      printf '当前 ACME 证书不包含域名：%s\n' "$NODE_SERVER_NAME" >&2
      return 1
    }
  printf '完整节点域名：%s\n' "$NODE_SERVER_NAME"

  command -v getent >/dev/null 2>&1 || {
    printf '校验优选域名需要 getent 命令。\n' >&2
    return 1
  }
  while true; do
    read -r -p "请输入优选域名（直接回车使用 ${NODE_SERVER_NAME}）：" input
    input=$(normalize_domain "$input")
    NODE_ADDRESS=${input:-$NODE_SERVER_NAME}
    if ! valid_domain "$NODE_ADDRESS"; then
      printf '优选域名格式错误，请勿输入协议、路径或端口。\n' >&2
    elif ! getent ahosts "$NODE_ADDRESS" >/dev/null 2>&1; then
      printf '优选域名无法解析：%s\n' "$NODE_ADDRESS" >&2
    else
      break
    fi
  done
  printf '%s\n' \
    "客户端连接地址：$NODE_ADDRESS" \
    "TLS SNI / WebSocket Host：$NODE_SERVER_NAME"

  read -r -p '请输入 WebSocket 路径（直接回车随机生成）：' input
  NODE_PATH=${input:-/$(random_hex 4)}
  [[ "$NODE_PATH" == /* ]] || NODE_PATH="/$NODE_PATH"
  [[ "$NODE_PATH" =~ ^/[A-Za-z0-9._~/-]*$ ]] || {
    printf 'WebSocket 路径只能包含字母、数字、/、-、_、. 和 ~。\n' >&2
    return 1
  }
  printf '%s\n' \
    "WebSocket 路径：$NODE_PATH" \
    '' \
    '请在 Cloudflare 添加并开启小黄云：' \
    "  类型：A" \
    "  名称：$NODE_DOMAIN_PREFIX" \
    '  内容：服务器公网 IP' \
    '  代理状态：已代理（开启小黄云）' \
    "  完整域名：$NODE_SERVER_NAME" \
    "  端口：$NODE_PORT" \
    '  SSL/TLS 模式：Full (strict)'
}

read_quick_tunnel_node_details() {
  local input

  read_node_port || return
  NODE_SERVER_NAME=""
  read -r -p '请输入 WebSocket 路径（直接回车随机生成）：' input
  NODE_PATH=${input:-/$(random_hex 4)}
  [[ "$NODE_PATH" == /* ]] || NODE_PATH="/$NODE_PATH"
  [[ "$NODE_PATH" =~ ^/[A-Za-z0-9._~/-]*$ ]] || {
    printf 'WebSocket 路径只能包含字母、数字、/、-、_、. 和 ~。\n' >&2
    return 1
  }

  while true; do
    read -r -p '请输入优选域名（直接回车使用临时隧道域名）：' input
    input=$(normalize_domain "$input")
    if [[ -z "$input" ]]; then
      NODE_ADDRESS=$input
      break
    elif ! valid_domain "$input"; then
      printf '优选域名格式错误，请勿输入协议、路径或端口。\n' >&2
    elif ! command -v getent >/dev/null 2>&1 \
      || ! getent ahosts "$input" >/dev/null 2>&1; then
      printf '优选域名无法解析：%s\n' "$input" >&2
    else
      NODE_ADDRESS=$input
      break
    fi
  done
  printf '%s\n' \
    "本地监听端口：$NODE_PORT" \
    "WebSocket 路径：$NODE_PATH" \
    '临时隧道域名将在 cloudflared 启动后生成。'
}

read_tunnel_node_details() {
  read -r -s -p '请输入 Cloudflare Tunnel Token（留空创建临时隧道）：' \
    NODE_TUNNEL_TOKEN
  printf '\n'

  if [[ -z "$NODE_TUNNEL_TOKEN" ]]; then
    NODE_TYPE="ws-tunnel"
    read_quick_tunnel_node_details
  else
    NODE_TYPE="ws-named-tunnel"
    if ! read_named_tunnel_node_details; then
      NODE_TUNNEL_TOKEN=""
      return 1
    fi
  fi
}

read_named_tunnel_node_details() {
  local input root_domain

  [[ -s "$TLS_DOMAIN_FILE" ]] || {
    printf '未找到可复用的根域名，请先通过证书管理配置域名。\n' >&2
    return 1
  }
  IFS= read -r root_domain < "$TLS_DOMAIN_FILE"
  valid_domain "$root_domain" || {
    printf '已保存的根域名格式错误：%s\n' "$root_domain" >&2
    return 1
  }
  read_node_port || return

  while true; do
    printf '当前根域名：%s\n' "$root_domain"
    read -r -p '请输入固定隧道子域名前缀 [tunnel]：' input
    input=$(normalize_domain "${input:-tunnel}")
    if valid_domain_prefix "$input"; then
      NODE_SERVER_NAME="${input}.${root_domain}"
      break
    fi
    printf '子域名前缀只能包含小写字母、数字和连字符，且不能以连字符开头或结尾。\n' >&2
  done

  read -r -p '请输入 WebSocket 路径（直接回车随机生成）：' input
  NODE_PATH=${input:-/$(random_hex 4)}
  [[ "$NODE_PATH" == /* ]] || NODE_PATH="/$NODE_PATH"
  [[ "$NODE_PATH" =~ ^/[A-Za-z0-9._~/-]*$ ]] || {
    printf 'WebSocket 路径只能包含字母、数字、/、-、_、. 和 ~。\n' >&2
    return 1
  }

  while true; do
    read -r -p "请输入优选域名（直接回车使用 ${NODE_SERVER_NAME}）：" input
    input=$(normalize_domain "$input")
    NODE_ADDRESS=${input:-$NODE_SERVER_NAME}
    if ! valid_domain "$NODE_ADDRESS"; then
      printf '优选域名格式错误，请勿输入协议、路径或端口。\n' >&2
    elif [[ -n "$input" ]] && { ! command -v getent >/dev/null 2>&1 \
      || ! getent ahosts "$input" >/dev/null 2>&1; }; then
      printf '优选域名无法解析：%s\n' "$input" >&2
    else
      break
    fi
  done

  printf '%s\n' \
    "完整隧道域名：$NODE_SERVER_NAME" \
    "本地回源地址：http://127.0.0.1:$NODE_PORT" \
    "WebSocket 路径：$NODE_PATH" \
    '' \
    '请在该 Tunnel 的 Published application 中添加：' \
    "  Hostname：$NODE_SERVER_NAME" \
    "  Service：http://127.0.0.1:$NODE_PORT"
  if [[ -t 0 ]]; then
    read -r -p '配置完成后按 Enter 继续...' _
  fi
}

select_warp_mode() {
  local choice

  printf '%s\n' \
    '' \
    '请选择该节点的 WARP 出站模式：' \
    '1) 仅启用直连节点（默认）' \
    '2) 同时创建直出和 WARP 节点' \
    '3) 仅创建 WARP 节点' \
    ''
  while true; do
    read -r -p '请输入 [1/2/3]（直接回车选择 1）：' choice
    case "${choice:-1}" in
      1) WARP_MODE="direct"; return ;;
      2) WARP_MODE="both"; return ;;
      3) WARP_MODE="warp"; return ;;
      *) printf '无效选项，请输入 1、2 或 3。\n' >&2 ;;
    esac
  done
}

select_vless_encryption() {
  local choice

  VLESS_ENCRYPTION_ENABLED=0
  NODE_ENCRYPTION="none"
  NODE_DECRYPTION="none"
  [[ "$NODE_TYPE" == ws* ]] || return
  printf '%s\n' \
    '' \
    '是否启用 VLESS ENC：' \
    '1) 不启用（默认，兼容性最好）' \
    '2) 启用（仅支持新版 Xray 内核客户端）' \
    ''
  while true; do
    read -r -p '请输入 [1/2]（直接回车选择 1）：' choice
    case "${choice:-1}" in
      1) return ;;
      2) VLESS_ENCRYPTION_ENABLED=1; return ;;
      *) printf '无效选项，请输入 1 或 2。\n' >&2 ;;
    esac
  done
}

install_wgcf() {
  local release_json tag version asset_name asset_url expected actual

  detect_arch
  info "正在查询 wgcf 最新版本"
  release_json=$(curl --retry 3 -fsSL "https://api.github.com/repos/${WGCF_REPO}/releases/latest") || {
    printf '查询 wgcf 最新版本失败。\n' >&2
    return 1
  }
  tag=$(jq -r '.tag_name // empty' <<<"$release_json")
  version=${tag#v}
  asset_name="wgcf_${version}_linux_${ARCH}"
  asset_url=$(jq -r --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")
  expected=$(jq -r --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .digest // empty' <<<"$release_json")
  expected=${expected#sha256:}
  [[ -n "$version" && -n "$asset_url" ]] || {
    printf '未找到适用于当前架构的 wgcf 安装包。\n' >&2
    return 1
  }

  curl --retry 3 -fL "$asset_url" -o "$TMP_DIR/$asset_name" || {
    printf '下载 wgcf 失败。\n' >&2
    return 1
  }
  actual=$(sha256sum "$TMP_DIR/$asset_name" | awk '{print $1}')
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ && "$actual" == "$expected" ]] || {
    printf 'wgcf SHA-256 校验失败。\n' >&2
    return 1
  }

  install -d -m 0700 "$WARP_HOME"
  install -m 0755 "$TMP_DIR/$asset_name" "$WGCF_BIN"
  info "wgcf ${tag} 已安装"
}

read_wgcf_profile_value() {
  local key=$1
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      sub("^[^=]*=[[:space:]]*", "")
      sub("[[:space:]]*$", "")
      gsub("\\r", "")
      print
      exit
    }
  ' "$WGCF_PROFILE"
}

load_wgcf_profile() {
  [[ -s "$WGCF_PROFILE" ]] || return 1

  WARP_PRIVATE_KEY=$(read_wgcf_profile_value PrivateKey)
  WARP_ADDRESSES=$(read_wgcf_profile_value Address)
  WARP_PUBLIC_KEY=$(read_wgcf_profile_value PublicKey)
  WARP_ALLOWED_IPS=$(read_wgcf_profile_value AllowedIPs)
  WARP_ENDPOINT=$(read_wgcf_profile_value Endpoint)
  [[ -n "$WARP_PRIVATE_KEY" && -n "$WARP_ADDRESSES" && -n "$WARP_PUBLIC_KEY" \
    && -n "$WARP_ENDPOINT" ]] || return 1
  WARP_ALLOWED_IPS=${WARP_ALLOWED_IPS:-0.0.0.0/0, ::/0}
}

detect_warp_domain_strategy() {
  WARP_DOMAIN_STRATEGY=""
  WARP_ENDPOINT_FAMILY=""
  if ip -4 route show default | grep -q .; then
    WARP_ENDPOINT_FAMILY="4"
  elif ip -6 route show default | grep -q .; then
    WARP_ENDPOINT_FAMILY="6"
  fi
  if [[ "$WARP_ENDPOINT_FAMILY" == "4" ]] && ! ip -6 route show default | grep -q .; then
    WARP_DOMAIN_STRATEGY="ForceIPv4"
  elif [[ "$WARP_ENDPOINT_FAMILY" == "6" ]]; then
    WARP_DOMAIN_STRATEGY="ForceIPv6"
  fi
}

resolve_warp_endpoint() {
  local endpoint_address resolved_address="" automatic_mtu=1280

  endpoint_address=${WARP_ENDPOINT%:*}
  endpoint_address=${endpoint_address#[}
  endpoint_address=${endpoint_address%]}
  WARP_ENDPOINT_PORT=${WARP_ENDPOINT##*:}
  [[ -n "$endpoint_address" && "$WARP_ENDPOINT_PORT" =~ ^[0-9]+$ ]] || return 1

  case "$WARP_ENDPOINT_FAMILY" in
    4)
      resolved_address=$(getent ahostsv4 "$endpoint_address" \
        | awk 'NR == 1 {print $1}' || true)
      automatic_mtu=1440
      ;;
    6)
      resolved_address=$(getent ahostsv6 "$endpoint_address" \
        | awk 'NR == 1 {print $1}' || true)
      automatic_mtu=1420
      ;;
    *) return 1 ;;
  esac

  WARP_ENDPOINT_ADDRESS=${resolved_address:-$endpoint_address}
  WARP_MTU=$automatic_mtu
  [[ -n "$resolved_address" ]] || WARP_MTU=1280
  if [[ -n "$resolved_address" ]]; then
    [[ "$WARP_ENDPOINT_FAMILY" == "4" ]] \
      && WARP_ENDPOINT="${resolved_address}:${WARP_ENDPOINT_PORT}" \
      || WARP_ENDPOINT="[${resolved_address}]:${WARP_ENDPOINT_PORT}"
  fi

  if [[ -n "${WARP_MTU_OVERRIDE:-}" ]]; then
    [[ "$WARP_MTU_OVERRIDE" =~ ^[0-9]+$ \
      && "$WARP_MTU_OVERRIDE" -ge 1280 && "$WARP_MTU_OVERRIDE" -le "$WARP_MTU" ]] || {
      printf 'WARP_MTU_OVERRIDE 必须在 1280 到 %s 之间。\n' "$WARP_MTU" >&2
      return 1
    }
    WARP_MTU=$WARP_MTU_OVERRIDE
  fi
}

ensure_warp_profile() {
  install -d -m 0700 "$WARP_HOME"
  [[ -x "$WGCF_BIN" ]] || install_wgcf || return
  load_wgcf_profile && return

  if [[ ! -s "$WGCF_ACCOUNT" ]]; then
    printf '%s\n' \
      '首次启用 WARP 需要通过 wgcf 注册 Cloudflare WARP 账户。' \
      '服务条款：https://www.cloudflare.com/application/terms/'
    "$WGCF_BIN" register --accept-tos --config "$WGCF_ACCOUNT" || {
      [[ -s "$WGCF_ACCOUNT" ]] || return 1
      info "wgcf 已生成账户，继续验证配置"
    }
    chmod 0600 "$WGCF_ACCOUNT"
  fi

  "$WGCF_BIN" generate --config "$WGCF_ACCOUNT" --profile "$WGCF_PROFILE" || return
  chmod 0600 "$WGCF_PROFILE"
  load_wgcf_profile || {
    printf 'wgcf 生成的 WireGuard 配置不完整。\n' >&2
    return 1
  }
}

generate_xray_credentials() {
  local encryption_output key_output

  NODE_UUID=$("$XRAY_HOME/xray" uuid)
  NODE_WARP_UUID=""
  if [[ "$WARP_MODE" == "both" ]]; then
    NODE_WARP_UUID=$("$XRAY_HOME/xray" uuid)
  fi
  if [[ "$NODE_TYPE" == ws* ]]; then
    NODE_PRIVATE_KEY=""
    NODE_PUBLIC_KEY=""
    NODE_SHORT_ID=""
    if [[ "${VLESS_ENCRYPTION_ENABLED:-0}" == "1" ]]; then
      encryption_output=$("$XRAY_HOME/xray" vlessenc) || return 1
      NODE_DECRYPTION=$(awk -F '"' '/"decryption"/ { value=$4 } END { print value }' \
        <<<"$encryption_output")
      NODE_ENCRYPTION=$(awk -F '"' '/"encryption"/ { value=$4 } END { print value }' \
        <<<"$encryption_output")
      [[ "$NODE_DECRYPTION" == mlkem768x25519plus.* \
        && "$NODE_ENCRYPTION" == mlkem768x25519plus.* ]] || return 1
    fi
    [[ "$NODE_UUID" =~ ^[0-9a-fA-F-]{36}$ \
      && ( -z "$NODE_WARP_UUID" || "$NODE_WARP_UUID" =~ ^[0-9a-fA-F-]{36}$ ) ]]
    return
  fi
  key_output=$("$XRAY_HOME/xray" x25519)
  NODE_PRIVATE_KEY=$(awk -F ': *' 'tolower($1) ~ /^private[[:space:]]*key$/ {print $2; exit}' \
    <<<"$key_output")
  NODE_PUBLIC_KEY=$(awk -F ': *' \
    'tolower($1) ~ /^(password|public[[:space:]]*key)/ {print $2; exit}' <<<"$key_output")
  NODE_SHORT_ID=$(random_hex 8)

  [[ "$NODE_UUID" =~ ^[0-9a-fA-F-]{36}$ && -n "$NODE_PRIVATE_KEY" \
    && -n "$NODE_PUBLIC_KEY" ]] || return 1
  [[ -z "$NODE_WARP_UUID" || "$NODE_WARP_UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || return 1
}

write_xray_node_config() {
  local current_config=$1 config_file=$2 flow listen network security tag warp_email

  case "$NODE_TYPE" in
    xhttp) network="xhttp"; security="reality"; flow="" ;;
    tcp) network="tcp"; security="reality"; flow="xtls-rprx-vision" ;;
    ws) network="ws"; security="tls"; flow="" ;;
    ws-tunnel | ws-named-tunnel) network="ws"; security="none"; flow="" ;;
  esac
  listen="0.0.0.0"
  [[ "$NODE_TYPE" != "ws-tunnel" && "$NODE_TYPE" != "ws-named-tunnel" ]] \
    || listen="127.0.0.1"
  tag="rainbow-vless-${NODE_TYPE}"
  warp_email="rainbow-${NODE_TYPE}-warp"

  jq \
    --argjson port "$NODE_PORT" \
    --arg uuid "$NODE_UUID" \
    --arg warp_uuid "$NODE_WARP_UUID" \
    --arg warp_mode "$WARP_MODE" \
    --arg decryption "${NODE_DECRYPTION:-none}" \
    --arg flow "$flow" \
    --arg listen "$listen" \
    --arg network "$network" \
    --arg security "$security" \
    --arg tag "$tag" \
    --arg warp_email "$warp_email" \
    --arg path "$NODE_PATH" \
    --arg target "${NODE_SERVER_NAME}:443" \
    --arg server_name "$NODE_SERVER_NAME" \
    --arg private_key "$NODE_PRIVATE_KEY" \
    --arg short_id "$NODE_SHORT_ID" \
    --arg certificate_file "$ACME_TLS_CERT" \
    --arg key_file "$ACME_TLS_KEY" \
    --arg warp_private_key "${WARP_PRIVATE_KEY:-}" \
    --arg warp_addresses "${WARP_ADDRESSES:-}" \
    --arg warp_public_key "${WARP_PUBLIC_KEY:-}" \
    --arg warp_allowed_ips "${WARP_ALLOWED_IPS:-}" \
    --arg warp_endpoint "${WARP_ENDPOINT:-}" \
    --arg warp_domain_strategy "${WARP_DOMAIN_STRATEGY:-}" \
    --argjson warp_mtu "${WARP_MTU:-1280}" '
      def csv:
        split(",") | map(gsub("^[ \t]+|[ \t]+$"; "")) | map(select(length > 0));

      def same_node_type:
        ((.tag // "") == $tag) or
        (
          (.tag // "") == "" and
          .protocol == "vless" and
          $network != "ws" and
          .streamSettings.security == "reality" and
          (if $network == "tcp" then
            (.streamSettings.network // "tcp") == "tcp" or
            (.streamSettings.network // "") == "raw"
          else
            .streamSettings.network == "xhttp"
          end)
        );

      def direct_client:
        {id: $uuid, flow: $flow};

      def warp_client($id):
        {id: $id, flow: $flow, email: $warp_email};

      def node_clients:
        if $warp_mode == "direct" then
          [direct_client]
        elif $warp_mode == "both" then
          [direct_client, warp_client($warp_uuid)]
        else
          [warp_client($uuid)]
        end;

      .inbounds = (
        ((.inbounds // []) | map(select(same_node_type | not))) + [{
          tag: $tag,
          listen: $listen,
          port: $port,
          protocol: "vless",
          settings: {
            clients: node_clients,
            decryption: $decryption
          },
          streamSettings: (
            {network: $network, security: $security}
            + if $network == "ws" then
                {wsSettings: ({path: $path}
                  + if $security == "tls" then {host: $server_name} else {} end)}
                + if $security == "tls" then {
                    tlsSettings: {
                      certificates: [{
                        certificateFile: $certificate_file,
                        keyFile: $key_file
                      }]
                    }
                  } else {} end
              else {
                realitySettings: {
                  show: false,
                  target: $target,
                  xver: 0,
                  serverNames: [$server_name],
                  privateKey: $private_key,
                  shortIds: [$short_id]
                }
              } end
            + if $network == "xhttp" then {xhttpSettings: {path: $path}} else {} end
          ),
          sniffing: {
            enabled: true,
            destOverride: ["http", "tls", "quic"]
          }
        }]
      )
      | .routing = (
          (.routing // {})
          | .rules = (
              (if $warp_mode == "direct" then [] else [{
                  type: "field",
                  user: [$warp_email],
                  outboundTag: "rainbow-warp"
                }] end)
              + ((.rules // []) | map(select(
                  (((.outboundTag // "") == "rainbow-warp")
                    and ((.user // []) | index($warp_email) != null)) | not
                )))
            )
        )
      | ([.routing.rules[]? | select((.outboundTag // "") == "rainbow-warp")] | length > 0)
        as $needs_warp
      | .outbounds = (
          if $warp_mode == "direct" then
            if $needs_warp then (.outbounds // [])
            else ((.outbounds // []) | map(select((.tag // "") != "rainbow-warp"))) end
          else
            ((.outbounds // []) | map(select((.tag // "") != "rainbow-warp"))) + [{
              tag: "rainbow-warp",
              protocol: "wireguard",
              settings: ({
                secretKey: $warp_private_key,
                address: ($warp_addresses | csv),
                peers: [{
                  endpoint: $warp_endpoint,
                  publicKey: $warp_public_key,
                  allowedIPs: ($warp_allowed_ips | csv)
                }],
                mtu: $warp_mtu
              } + if $warp_domain_strategy == "" then {}
                else {domainStrategy: $warp_domain_strategy} end)
            }]
          end
        )
    ' "$current_config" > "$config_file"
}

write_xray_client_block() {
  local client_file=$1 uuid=$2 label=$3 outbound=$4 encoded_encryption
  local encoded_label encoded_path uri

  encoded_label=$(jq -rn --arg value "$label" '$value | @uri')
  encoded_encryption=$(jq -rn --arg value "${NODE_ENCRYPTION:-none}" '$value | @uri')

  case "$NODE_TYPE" in
    xhttp)
      encoded_path=$(jq -rn --arg value "$NODE_PATH" '$value | @uri')
      uri="vless://${uuid}@${NODE_ADDRESS}:${NODE_PORT}?encryption=none&security=reality&sni=${NODE_SERVER_NAME}&fp=chrome&pbk=${NODE_PUBLIC_KEY}&sid=${NODE_SHORT_ID}&type=xhttp&path=${encoded_path}&mode=auto#${encoded_label}"
      ;;
    tcp)
      uri="vless://${uuid}@${NODE_ADDRESS}:${NODE_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${NODE_SERVER_NAME}&fp=chrome&pbk=${NODE_PUBLIC_KEY}&sid=${NODE_SHORT_ID}&type=tcp&headerType=none#${encoded_label}"
      ;;
    ws)
      encoded_path=$(jq -rn --arg value "$NODE_PATH" '$value | @uri')
      uri="vless://${uuid}@${NODE_ADDRESS}:${NODE_PORT}?encryption=${encoded_encryption}&security=tls&sni=${NODE_SERVER_NAME}&fp=chrome&type=ws&host=${NODE_SERVER_NAME}&path=${encoded_path}#${encoded_label}"
      ;;
    ws-tunnel | ws-named-tunnel)
      encoded_path=$(jq -rn --arg value "$NODE_PATH" '$value | @uri')
      uri="vless://${uuid}@${NODE_ADDRESS}:${NODE_PORT}?encryption=${encoded_encryption}&security=tls&sni=${NODE_SERVER_NAME}&fp=chrome&type=ws&host=${NODE_SERVER_NAME}&path=${encoded_path}#${encoded_label}"
      ;;
  esac

  printf '%s\n' \
    "类型：$label" \
    "出站：$outbound" \
    "地址：$NODE_ADDRESS" \
    "端口：$NODE_PORT" >> "$client_file"
  if [[ "$NODE_TYPE" == ws* ]]; then
    printf '%s\n' \
      "服务域名：$NODE_SERVER_NAME" \
      "WebSocket 路径：$NODE_PATH" \
      "VLESS ENC：$([[ "${NODE_ENCRYPTION:-none}" == "none" ]] \
        && printf '未启用' || printf '已启用')" \
      "UUID：$uuid" >> "$client_file"
  else
    printf '%s\n' \
      "伪装域名：$NODE_SERVER_NAME" \
      "XHTTP 路径：${NODE_PATH:--}" \
      "UUID：$uuid" \
      "Public Key：$NODE_PUBLIC_KEY" \
      "Short ID：$NODE_SHORT_ID" >> "$client_file"
  fi
  printf '分享链接：%s\n' "$uri" >> "$client_file"
}

save_vless_encryption_state() {
  local file="$XRAY_HOME/client-${NODE_TYPE}.enc"

  if [[ "${NODE_ENCRYPTION:-none}" == "none" ]]; then
    rm -f "$file"
  else
    install -m 0600 /dev/null "$file"
    printf '%s\n' "$NODE_ENCRYPTION" > "$file"
  fi
}

restore_vless_encryption_state() {
  local backup=$1 existed=$2 file=$3

  if [[ "$existed" == "1" ]]; then
    install -m 0600 "$backup" "$file"
  else
    rm -f "$file"
  fi
}

save_xray_client_info() {
  local all_clients="$XRAY_HOME/client.txt" client_file first_line label prefix

  if [[ -f "$all_clients" && ! -f "$XRAY_HOME/client-xhttp.txt" \
    && ! -f "$XRAY_HOME/client-tcp.txt" ]]; then
    IFS= read -r first_line < "$all_clients" || true
    case "$first_line" in
      '类型：Rainbow-XHTTP') install -m 0600 "$all_clients" "$XRAY_HOME/client-xhttp.txt" ;;
      '类型：Rainbow-TCP') install -m 0600 "$all_clients" "$XRAY_HOME/client-tcp.txt" ;;
    esac
  fi

  prefix=$(get_node_prefix)
  case "$NODE_TYPE" in
    xhttp) label="${prefix}-XHTTP" ;;
    tcp) label="${prefix}-TCP" ;;
    ws) label="${prefix}-CDN" ;;
    ws-tunnel | ws-named-tunnel) label="${prefix}-ARGO" ;;
  esac

  client_file="$XRAY_HOME/client-${NODE_TYPE}.txt"
  install -m 0600 /dev/null "$client_file"
  case "$WARP_MODE" in
    direct)
      write_xray_client_block "$client_file" "$NODE_UUID" "$label" "直出"
      ;;
    both)
      write_xray_client_block "$client_file" "$NODE_UUID" "$label" "直出"
      printf '\n' >> "$client_file"
      write_xray_client_block "$client_file" "$NODE_WARP_UUID" "${label}-WARP" "WARP"
      ;;
    warp)
      write_xray_client_block "$client_file" "$NODE_UUID" "${label}-WARP" "WARP"
      ;;
  esac

  refresh_xray_client_info

  printf '\n节点搭建完成：\n'
  cat "$client_file"
  printf '全部客户端信息已保存至：%s\n\n' "$all_clients"
}

refresh_xray_client_info() {
  local all_clients="$XRAY_HOME/client.txt" type

  install -m 0600 /dev/null "$all_clients"
  for type in xhttp tcp ws ws-tunnel ws-named-tunnel; do
    [[ -f "$XRAY_HOME/client-${type}.txt" ]] || continue
    [[ ! -s "$all_clients" ]] || printf '\n' >> "$all_clients"
    cat "$XRAY_HOME/client-${type}.txt" >> "$all_clients"
  done
}

refresh_quick_tunnel_client() {
  local client_file="$XRAY_HOME/client-ws-tunnel.txt" email hostname=""
  local first=1 label preferred_address="" prefix uuid

  for _ in {1..30}; do
    if [[ -s "$CLOUDFLARED_LOG" ]]; then
      hostname=$(grep -Eo '[a-z0-9-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" \
        | tail -n 1 || true)
    fi
    [[ -z "$hostname" ]] || break
    sleep 1
  done
  [[ "$hostname" =~ ^[a-z0-9-]+\.trycloudflare\.com$ ]] || {
    printf '未获取到 Cloudflare 临时隧道域名。\n' >&2
    return 1
  }
  jq -e 'any(.inbounds[]?; .tag == "rainbow-vless-ws-tunnel")' \
    "$XRAY_HOME/config.json" >/dev/null || return 1

  install -m 0600 /dev/null "$CLOUDFLARED_HOST_FILE"
  printf '%s\n' "$hostname" > "$CLOUDFLARED_HOST_FILE"
  [[ ! -s "$CLOUDFLARED_ADDRESS_FILE" ]] \
    || IFS= read -r preferred_address < "$CLOUDFLARED_ADDRESS_FILE"
  NODE_TYPE="ws-tunnel"
  NODE_ENCRYPTION="none"
  [[ ! -s "$XRAY_HOME/client-${NODE_TYPE}.enc" ]] \
    || IFS= read -r NODE_ENCRYPTION < "$XRAY_HOME/client-${NODE_TYPE}.enc"
  NODE_ADDRESS=${preferred_address:-$hostname}
  NODE_PORT=443
  NODE_SERVER_NAME=$hostname
  NODE_PATH=$(jq -r '
    .inbounds[] | select(.tag == "rainbow-vless-ws-tunnel")
    | .streamSettings.wsSettings.path
  ' "$XRAY_HOME/config.json")
  prefix=$(get_node_prefix)
  label="${prefix}-ARGO"
  install -m 0600 /dev/null "$client_file"

  while IFS=$'\t' read -r uuid email; do
    [[ -n "$uuid" ]] || continue
    [[ "$first" == "1" ]] || printf '\n' >> "$client_file"
    if [[ -n "$email" ]]; then
      write_xray_client_block "$client_file" "$uuid" "${label}-WARP" "WARP"
    else
      write_xray_client_block "$client_file" "$uuid" "$label" "直出"
    fi
    first=0
  done < <(jq -r '
    .inbounds[] | select(.tag == "rainbow-vless-ws-tunnel")
    | .settings.clients[] | [.id, (.email // "")] | @tsv
  ' "$XRAY_HOME/config.json")
  refresh_xray_client_info
  info "Cloudflare 临时隧道域名：$hostname"
}

install_quick_tunnel_service() {
  local rm_bin service_file="/etc/systemd/system/${CLOUDFLARED_SERVICE}.service" truncate_bin

  rm_bin=$(command -v rm) || return 1
  truncate_bin=$(command -v truncate) || return 1

  install -m 0644 /dev/null "$service_file"
  cat > "$service_file" <<EOF
[Unit]
Description=Rainbow Cloudflare Quick Tunnel
After=network-online.target ${XRAY_SERVICE}.service
Wants=network-online.target
Requires=${XRAY_SERVICE}.service

[Service]
ExecStartPre=$truncate_bin -s 0 $CLOUDFLARED_LOG
ExecStartPre=$rm_bin -f $CLOUDFLARED_HOST_FILE
ExecStart=$CLOUDFLARED_BIN tunnel --config /dev/null --no-autoupdate --url http://127.0.0.1:$NODE_PORT
ExecStartPost=$RAINBOW_BIN quick-tunnel-refresh
Restart=always
RestartSec=5s
TimeoutStartSec=45s
StandardOutput=append:$CLOUDFLARED_LOG
StandardError=append:$CLOUDFLARED_LOG

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$CLOUDFLARED_SERVICE"
  systemctl restart "$CLOUDFLARED_SERVICE"
}

setup_quick_tunnel_service() {
  local address_backup="$TMP_DIR/cloudflared-address.backup"
  local address_existed=0 service_backup="$TMP_DIR/cloudflared-service.backup"
  local service_existed=0 service_file="/etc/systemd/system/${CLOUDFLARED_SERVICE}.service"

  if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
    install_cloudflared || return 1
  fi
  if [[ -f "$service_file" ]]; then
    install -m 0644 "$service_file" "$service_backup"
    service_existed=1
  fi
  if [[ -f "$CLOUDFLARED_ADDRESS_FILE" ]]; then
    install -m 0600 "$CLOUDFLARED_ADDRESS_FILE" "$address_backup"
    address_existed=1
  fi
  install -d -m 0700 "$CLOUDFLARED_HOME"
  install -m 0600 /dev/null "$CLOUDFLARED_ADDRESS_FILE"
  printf '%s\n' "$NODE_ADDRESS" > "$CLOUDFLARED_ADDRESS_FILE"

  if install_quick_tunnel_service; then
    return
  fi
  if [[ "$service_existed" == "1" ]]; then
    install -m 0644 "$service_backup" "$service_file"
  else
    rm -f "$service_file"
  fi
  if [[ "$address_existed" == "1" ]]; then
    install -m 0600 "$address_backup" "$CLOUDFLARED_ADDRESS_FILE"
  else
    rm -f "$CLOUDFLARED_ADDRESS_FILE"
  fi
  systemctl daemon-reload
  return 1
}

install_named_tunnel_service() {
  local service_file="/etc/systemd/system/${CLOUDFLARED_NAMED_SERVICE}.service"

  install -m 0644 /dev/null "$service_file"
  cat > "$service_file" <<EOF
[Unit]
Description=Rainbow Cloudflare Named Tunnel
After=network-online.target ${XRAY_SERVICE}.service
Wants=network-online.target
Requires=${XRAY_SERVICE}.service

[Service]
ExecStart=$CLOUDFLARED_BIN tunnel --no-autoupdate run --token-file $CLOUDFLARED_NAMED_TOKEN_FILE
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$CLOUDFLARED_NAMED_SERVICE"
  systemctl restart "$CLOUDFLARED_NAMED_SERVICE"
  sleep 2
  systemctl is-active --quiet "$CLOUDFLARED_NAMED_SERVICE"
}

setup_named_tunnel_service() {
  local backup_dir="$TMP_DIR/named-tunnel-backup"
  local file service_file="/etc/systemd/system/${CLOUDFLARED_NAMED_SERVICE}.service"

  [[ -x "$CLOUDFLARED_BIN" ]] || install_cloudflared || return 1
  install -d -m 0700 "$backup_dir" "$CLOUDFLARED_HOME"
  for file in "$service_file" "$CLOUDFLARED_NAMED_TOKEN_FILE" \
    "$CLOUDFLARED_NAMED_HOST_FILE"; do
    [[ ! -f "$file" ]] || install -m 0600 "$file" "$backup_dir/$(basename "$file")"
  done

  printf '%s\n' "$NODE_TUNNEL_TOKEN" > "$CLOUDFLARED_NAMED_TOKEN_FILE"
  printf '%s\n' "$NODE_SERVER_NAME" > "$CLOUDFLARED_NAMED_HOST_FILE"
  chmod 0600 "$CLOUDFLARED_NAMED_TOKEN_FILE" "$CLOUDFLARED_NAMED_HOST_FILE"
  NODE_TUNNEL_TOKEN=""

  if install_named_tunnel_service; then
    return
  fi
  systemctl disable --now "$CLOUDFLARED_NAMED_SERVICE" >/dev/null 2>&1 || true
  for file in "$service_file" "$CLOUDFLARED_NAMED_TOKEN_FILE" \
    "$CLOUDFLARED_NAMED_HOST_FILE"; do
    if [[ -f "$backup_dir/$(basename "$file")" ]]; then
      if [[ "$file" == "$service_file" ]]; then
        install -m 0644 "$backup_dir/$(basename "$file")" "$file"
      else
        install -m 0600 "$backup_dir/$(basename "$file")" "$file"
      fi
    else
      rm -f "$file"
    fi
  done
  systemctl daemon-reload
  [[ ! -f "$service_file" ]] || systemctl enable --now "$CLOUDFLARED_NAMED_SERVICE" \
    >/dev/null 2>&1 || true
  return 1
}

verify_named_tunnel_route() {
  local code

  for _ in {1..4}; do
    code=$(curl --http1.1 -ksS --connect-timeout 5 --max-time 5 -o /dev/null \
      -w '%{http_code}' \
      -H 'Connection: Upgrade' \
      -H 'Upgrade: websocket' \
      -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
      -H 'Sec-WebSocket-Version: 13' \
      "https://${NODE_SERVER_NAME}${NODE_PATH}" 2>/dev/null || true)
    [[ "$code" == "101" ]] && return
    sleep 2
  done
  return 1
}

setup_xray_node() {
  local backup_file config_file="$TMP_DIR/xray-node-config.json"
  local encryption_backup="$TMP_DIR/vless-encryption.backup"
  local encryption_existed=0 encryption_file=""
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
  if [[ "$NODE_TYPE" == "ws" ]] && ! valid_acme_certificate; then
    printf 'VLESS + WebSocket 节点必须先通过证书管理配置有效的 ACME 证书。\n' >&2
    return 1
  fi

  select_warp_mode
  select_vless_encryption
  if [[ "$WARP_MODE" != "direct" ]]; then
    command -v getent >/dev/null 2>&1 || {
      printf '搭建 Xray WARP 节点需要 getent 命令。\n' >&2
      return 1
    }
    ensure_warp_profile || {
      printf 'WARP 配置失败，原配置未修改。\n' >&2
      return 1
    }
    detect_warp_domain_strategy
    resolve_warp_endpoint || {
      printf 'WARP Endpoint 解析失败，原配置未修改。\n' >&2
      return 1
    }
  fi
  read_node_details || return
  generate_xray_credentials || {
    printf '生成 Xray 凭据失败。\n' >&2
    return 1
  }
  write_xray_node_config "$XRAY_HOME/config.json" "$config_file"
  "$XRAY_HOME/xray" run -test -config "$config_file" || {
    printf 'Xray 配置验证失败，原配置未修改。\n' >&2
    return 1
  }

  backup_file=$(mktemp "$XRAY_HOME/config.json.backup.XXXXXX")
  install -m 0600 "$XRAY_HOME/config.json" "$backup_file"
  if [[ "$NODE_TYPE" == ws* ]]; then
    encryption_file="$XRAY_HOME/client-${NODE_TYPE}.enc"
    if [[ -f "$encryption_file" ]]; then
      install -m 0600 "$encryption_file" "$encryption_backup"
      encryption_existed=1
    fi
    save_vless_encryption_state || {
      restore_vless_encryption_state "$encryption_backup" "$encryption_existed" \
        "$encryption_file"
      return 1
    }
  fi
  install -m 0600 "$config_file" "$XRAY_HOME/config.json"
  if ! systemctl restart "$XRAY_SERVICE"; then
    install -m 0600 "$backup_file" "$XRAY_HOME/config.json"
    [[ -z "$encryption_file" ]] \
      || restore_vless_encryption_state "$encryption_backup" "$encryption_existed" \
        "$encryption_file"
    systemctl restart "$XRAY_SERVICE" || true
    printf 'Xray 启动失败，已恢复原配置：%s\n' "$backup_file" >&2
    return 1
  fi

  info "原配置已备份：$backup_file"
  if [[ "$NODE_TYPE" == "ws-tunnel" ]]; then
    if ! setup_quick_tunnel_service; then
      install -m 0600 "$backup_file" "$XRAY_HOME/config.json"
      restore_vless_encryption_state "$encryption_backup" "$encryption_existed" \
        "$encryption_file"
      systemctl restart "$XRAY_SERVICE" || true
      systemctl restart "$CLOUDFLARED_SERVICE" >/dev/null 2>&1 || true
      printf 'Cloudflare 临时隧道启动失败，已恢复原 Xray 配置。\n' >&2
      return 1
    fi
    printf '\n节点搭建完成：\n'
    cat "$XRAY_HOME/client-ws-tunnel.txt"
    printf '临时隧道重启后域名会变化，请重新导入最新分享链接。\n\n'
    return
  fi
  if [[ "$NODE_TYPE" == "ws-named-tunnel" ]]; then
    if ! setup_named_tunnel_service; then
      install -m 0600 "$backup_file" "$XRAY_HOME/config.json"
      restore_vless_encryption_state "$encryption_backup" "$encryption_existed" \
        "$encryption_file"
      systemctl restart "$XRAY_SERVICE" || true
      printf 'Cloudflare 固定隧道启动失败，已恢复原 Xray 配置。\n' >&2
      return 1
    fi
    NODE_PORT=443
    save_xray_client_info
    if verify_named_tunnel_route; then
      info '固定隧道 WebSocket 回源验证通过（HTTP 101）'
    else
      warn '固定隧道已启动，但域名路由尚未返回 HTTP 101，请检查 Published application 和 DNS。'
    fi
    return
  fi
  save_xray_client_info
}

show_nodes() {
  local client_file=$2 service=$1 service_name=$3

  printf '%s：\n' "$service_name"

  if ! systemctl is-active --quiet "$service"; then
    printf '  服务未运行，暂无已启用节点。\n'
  elif [[ ! -s "$client_file" ]] || ! grep -q '^分享链接：' "$client_file"; then
    printf '  暂无可展示的节点信息。\n'
  else
    awk '
      /^分享链接：/ {
        sub(/^分享链接：/, "")
        if (shown++) print ""
        print
      }
    ' "$client_file"
  fi
}

show_all_nodes() {
  clear_screen
  show_header '所有节点'

  show_nodes "$XRAY_SERVICE" "$XRAY_HOME/client.txt" 'Xray'
  printf '\n'
  show_nodes "$SING_BOX_SERVICE" "$SING_BOX_HOME/client.txt" 'sing-box'
  pause_menu
}

add_removable_node() {
  REMOVE_NODE_ENGINES+=("$1")
  REMOVE_NODE_TYPES+=("$2")
  REMOVE_NODE_LABELS+=("$3")
  REMOVE_NODE_COUNT=$((REMOVE_NODE_COUNT + 1))
}

discover_removable_nodes() {
  local label tag type

  REMOVE_NODE_ENGINES=()
  REMOVE_NODE_TYPES=()
  REMOVE_NODE_LABELS=()
  REMOVE_NODE_COUNT=0

  if [[ -f "$XRAY_HOME/config.json" ]]; then
    jq -e 'type == "object"' "$XRAY_HOME/config.json" >/dev/null || {
      printf 'Xray 配置格式错误，无法读取节点。\n' >&2
      return 1
    }
    for type in xhttp tcp ws ws-tunnel ws-named-tunnel; do
      tag="rainbow-vless-${type}"
      jq -e --arg tag "$tag" 'any(.inbounds[]?; .tag == $tag)' \
        "$XRAY_HOME/config.json" >/dev/null || continue
      case "$type" in
        xhttp) label="VLESS + REALITY + XHTTP" ;;
        tcp) label="VLESS + REALITY + TCP" ;;
        ws) label="VLESS + TLS + WebSocket CDN" ;;
        ws-tunnel) label="VLESS + WebSocket ARGO（临时）" ;;
        ws-named-tunnel) label="VLESS + WebSocket ARGO（固定）" ;;
      esac
      add_removable_node "Xray" "$type" "$label"
    done
  fi

  if [[ -f "$SING_BOX_HOME/config.json" ]]; then
    jq -e 'type == "object"' "$SING_BOX_HOME/config.json" >/dev/null || {
      printf 'sing-box 配置格式错误，无法读取节点。\n' >&2
      return 1
    }
    for type in tuic anytls hysteria2; do
      tag="rainbow-${type}"
      jq -e --arg tag "$tag" 'any(.inbounds[]?; .tag == $tag)' \
        "$SING_BOX_HOME/config.json" >/dev/null || continue
      case "$type" in
        tuic) label="TUIC" ;;
        anytls) label="AnyTLS" ;;
        hysteria2) label="Hysteria2" ;;
      esac
      add_removable_node "sing-box" "$type" "$label"
    done
  fi
}

get_managed_node_port() {
  local engine=$1 type=$2 tag

  if [[ "$engine" == "Xray" ]]; then
    tag="rainbow-vless-${type}"
    jq -er --arg tag "$tag" \
      'first(.inbounds[] | select(.tag == $tag) | .port)' \
      "$XRAY_HOME/config.json"
  else
    tag="rainbow-${type}"
    jq -er --arg tag "$tag" \
      'first(.inbounds[] | select(.tag == $tag) | .listen_port)' \
      "$SING_BOX_HOME/config.json"
  fi
}

read_edited_node_port() {
  local current_port=$1 input port protocol=$2 type=$3

  while true; do
    read -r -p "请输入新端口（当前 ${current_port}，直接回车取消）：" input
    [[ -n "$input" ]] || return 1
    if [[ ! "$input" =~ ^[0-9]+$ || ${#input} -gt 5 ]]; then
      printf '端口必须是 1 到 65535 之间的整数。\n' >&2
      continue
    fi
    port=$((10#$input))
    if ((port < 1 || port > 65535)); then
      printf '端口必须是 1 到 65535 之间的整数。\n' >&2
    elif ((port == current_port)); then
      printf '新端口与当前端口相同。\n' >&2
    elif [[ "$type" == "ws" ]] && ! valid_cf_https_port "$port"; then
      printf '仅支持 Cloudflare HTTPS 端口：443、2053、2083、2087、2096、8443。\n' >&2
    elif port_in_use "$port" "$protocol"; then
      printf '端口 %s 已被占用。\n' "$port" >&2
    else
      EDIT_NODE_PORT=$port
      return
    fi
  done
}

write_edited_client_port() {
  local client_file=$1 current_port=$2 new_port=$3 output=$4

  [[ -s "$client_file" ]] || return 1
  awk -v old_port="$current_port" -v new_port="$new_port" '
    /^端口：/ { $0 = "端口：" new_port }
    /^分享链接：/ { gsub(":" old_port, ":" new_port) }
    { print }
  ' "$client_file" > "$output"
  grep -q '^分享链接：' "$output"
}

edit_node_port() {
  local engine=$1 type=$2 current_port=$3 new_port=$4 apply_failed=0
  local backup_file client_backup="" client_file="" client_output=""
  local config_file config_output service tag

  if [[ "$engine" == "Xray" ]]; then
    config_file="$XRAY_HOME/config.json"
    config_output="$TMP_DIR/edit-xray-node.json"
    service="$XRAY_SERVICE"
    tag="rainbow-vless-${type}"
    jq --arg tag "$tag" --argjson port "$new_port" '
      .inbounds |= map(if .tag == $tag then .port = $port else . end)
    ' "$config_file" > "$config_output" \
      && "$XRAY_HOME/xray" run -test -config "$config_output" || {
        printf '修改后的 Xray 配置验证失败，原配置未修改。\n' >&2
        return 1
      }
  else
    config_file="$SING_BOX_HOME/config.json"
    config_output="$TMP_DIR/edit-sing-box-node.json"
    service="$SING_BOX_SERVICE"
    tag="rainbow-${type}"
    jq --arg tag "$tag" --argjson port "$new_port" '
      .inbounds |= map(if .tag == $tag then .listen_port = $port else . end)
    ' "$config_file" > "$config_output" \
      && "$SING_BOX_HOME/sing-box" check -c "$config_output" || {
        printf '修改后的 sing-box 配置验证失败，原配置未修改。\n' >&2
        return 1
      }
  fi

  if [[ "$type" != "ws-tunnel" && "$type" != "ws-named-tunnel" ]]; then
    if [[ "$engine" == "Xray" ]]; then
      client_file="$XRAY_HOME/client-${type}.txt"
    else
      client_file="$SING_BOX_HOME/client-${type}.txt"
    fi
    client_output="$TMP_DIR/edit-node-client.txt"
    write_edited_client_port "$client_file" "$current_port" "$new_port" \
      "$client_output" || {
        printf '节点客户端信息缺失或格式错误，原配置未修改。\n' >&2
        return 1
      }
  fi

  backup_file=$(mktemp "${config_file}.backup.XXXXXX")
  install -m 0600 "$config_file" "$backup_file" || return 1
  if [[ -n "$client_file" ]]; then
    client_backup=$(mktemp "${client_file}.backup.XXXXXX")
    install -m 0600 "$client_file" "$client_backup" || return 1
  fi

  install -m 0600 "$config_output" "$config_file" || apply_failed=1
  if [[ "$apply_failed" == "0" && -n "$client_file" ]]; then
    install -m 0600 "$client_output" "$client_file" || apply_failed=1
    if [[ "$apply_failed" == "0" ]]; then
      if [[ "$engine" == "Xray" ]]; then
        refresh_xray_client_info || apply_failed=1
      else
        refresh_sing_box_client_info || apply_failed=1
      fi
    fi
  fi
  if [[ "$apply_failed" == "0" ]] && ! systemctl restart "$service"; then
    apply_failed=1
  fi
  if [[ "$apply_failed" == "0" && "$type" == "ws-tunnel" ]]; then
    NODE_PORT=$new_port
    NODE_ADDRESS=""
    [[ ! -s "$CLOUDFLARED_ADDRESS_FILE" ]] \
      || IFS= read -r NODE_ADDRESS < "$CLOUDFLARED_ADDRESS_FILE"
    setup_quick_tunnel_service || apply_failed=1
  fi

  if [[ "$apply_failed" == "1" ]]; then
    install -m 0600 "$backup_file" "$config_file" || true
    if [[ -n "$client_backup" ]]; then
      install -m 0600 "$client_backup" "$client_file" || true
      if [[ "$engine" == "Xray" ]]; then
        refresh_xray_client_info || true
      else
        refresh_sing_box_client_info || true
      fi
    fi
    systemctl restart "$service" || true
    if [[ "$type" == "ws-tunnel" ]]; then
      systemctl daemon-reload || true
      systemctl restart "$CLOUDFLARED_SERVICE" || true
    fi
    printf '节点端口修改失败，已恢复原配置。\n' >&2
    return 1
  fi

  if [[ "$type" == "ws-named-tunnel" ]]; then
    printf '请将 Cloudflare Tunnel Published application 的 Service 修改为：\n'
    printf '  http://127.0.0.1:%s\n' "$new_port"
  fi
  info "节点端口已从 ${current_port} 修改为 ${new_port}"
}

manage_node_edit() {
  local current_port engine index input protocol type

  clear_screen
  show_header '编辑节点'
  discover_removable_nodes || return 1
  if ((REMOVE_NODE_COUNT == 0)); then
    printf '当前没有 Rainbow 管理的节点。\n'
    return
  fi

  printf '可编辑节点：\n'
  for ((index = 0; index < REMOVE_NODE_COUNT; index++)); do
    current_port=$(get_managed_node_port "${REMOVE_NODE_ENGINES[index]}" \
      "${REMOVE_NODE_TYPES[index]}") || return 1
    printf '%d) %-8s %s（端口：%s）\n' "$((index + 1))" \
      "${REMOVE_NODE_ENGINES[index]}" "${REMOVE_NODE_LABELS[index]}" "$current_port"
  done
  read -r -p '请输入要编辑的节点序号：' input
  [[ "$input" =~ ^[0-9]+$ && ${#input} -le 3 ]] || {
    printf '序号格式错误。\n' >&2
    return 1
  }
  index=$((10#$input))
  ((index >= 1 && index <= REMOVE_NODE_COUNT)) || {
    printf '序号超出范围。\n' >&2
    return 1
  }
  index=$((index - 1))
  engine=${REMOVE_NODE_ENGINES[index]}
  type=${REMOVE_NODE_TYPES[index]}
  current_port=$(get_managed_node_port "$engine" "$type") || return 1
  protocol="tcp"
  [[ "$type" != "tuic" && "$type" != "hysteria2" ]] || protocol="udp"
  command -v ss >/dev/null 2>&1 || {
    printf '编辑节点需要 ss 命令。\n' >&2
    return 1
  }
  read_edited_node_port "$current_port" "$protocol" "$type" || {
    printf '已取消编辑。\n'
    return
  }
  edit_node_port "$engine" "$type" "$current_port" "$EDIT_NODE_PORT"
}

parse_node_selection() {
  local index normalized=${1//,/ } selected=" " token max=$2

  SELECTED_NODE_INDEXES=()
  SELECTED_NODE_COUNT=0
  [[ -n "$normalized" && "$normalized" =~ ^[[:space:]0-9]+$ ]] || return 1
  for token in $normalized; do
    [[ ${#token} -le 3 ]] || return 1
    index=$((10#$token))
    ((index >= 1 && index <= max)) || return 1
    [[ "$selected" == *" $index "* ]] && continue
    SELECTED_NODE_INDEXES+=("$index")
    SELECTED_NODE_COUNT=$((SELECTED_NODE_COUNT + 1))
    selected+="$index "
  done
  ((SELECTED_NODE_COUNT > 0))
}

write_xray_removal_config() {
  local current_config=$1 config_file=$2 types_json=$3

  jq --argjson types "$types_json" '
    def selected_tag($tag):
      any($types[]; $tag == ("rainbow-vless-" + .));
    def selected_user($users):
      any($types[]; . as $type
        | ($users | index("rainbow-" + $type + "-warp")) != null);

    .inbounds = [(.inbounds // [])[] | select(selected_tag(.tag // "") | not)]
    | .routing = ((.routing // {}) | .rules = [
        (.rules // [])[] | select(selected_user(.user // []) | not)
      ])
    | ([.routing.rules[]? | select((.outboundTag // "") == "rainbow-warp")]
        | length > 0) as $needs_warp
    | if $needs_warp then .
      else .outbounds = ((.outbounds // [])
        | map(select((.tag // "") != "rainbow-warp")))
      end
  ' "$current_config" > "$config_file"
}

write_sing_box_removal_config() {
  local current_config=$1 config_file=$2 types_json=$3

  jq --argjson types "$types_json" '
    def selected_tag($tag):
      any($types[]; $tag == ("rainbow-" + .));
    def selected_user($users):
      any($types[]; . as $type
        | ($users | index("rainbow-" + $type + "-warp")) != null);

    .inbounds = [(.inbounds // [])[] | select(selected_tag(.tag // "") | not)]
    | .route = ((.route // {}) | .rules = [
        (.rules // [])[] | select(selected_user(.auth_user // []) | not)
      ])
    | ([.route.rules[]? | select((.outbound // "") == "rainbow-warp")]
        | length > 0) as $needs_warp
    | if $needs_warp then .
      else .endpoints = ((.endpoints // [])
        | map(select((.tag // "") != "rainbow-warp")))
      end
  ' "$current_config" > "$config_file"
}

remove_selected_nodes() {
  local apply_failed=0 index named_active=0 named_selected=0 quick_active=0
  local quick_selected=0 sing_backup="" sing_config="$TMP_DIR/remove-sing-box.json"
  local sing_count=0 sing_types_json type xray_backup=""
  local xray_config="$TMP_DIR/remove-xray.json" xray_count=0
  local xray_types_json
  local -a sing_types=() xray_types=()

  for index in "${SELECTED_NODE_INDEXES[@]}"; do
    index=$((index - 1))
    if [[ "${REMOVE_NODE_ENGINES[index]}" == "Xray" ]]; then
      type=${REMOVE_NODE_TYPES[index]}
      xray_types+=("$type")
      xray_count=$((xray_count + 1))
      [[ "$type" != "ws-tunnel" ]] || quick_selected=1
      [[ "$type" != "ws-named-tunnel" ]] || named_selected=1
    else
      sing_types+=("${REMOVE_NODE_TYPES[index]}")
      sing_count=$((sing_count + 1))
    fi
  done

  if ((xray_count > 0)); then
    [[ -x "$XRAY_HOME/xray" ]] || {
      printf '缺少 Rainbow 管理的 Xray，无法删除节点。\n' >&2
      return 1
    }
    xray_types_json=$(printf '%s\n' "${xray_types[@]}" | jq -Rn '[inputs]')
    write_xray_removal_config "$XRAY_HOME/config.json" "$xray_config" "$xray_types_json" \
      && "$XRAY_HOME/xray" run -test -config "$xray_config" || {
        printf '删除后的 Xray 配置验证失败，原配置未修改。\n' >&2
        return 1
      }
    xray_backup=$(mktemp "$XRAY_HOME/config.json.backup.XXXXXX")
    install -m 0600 "$XRAY_HOME/config.json" "$xray_backup" || return 1
  fi

  if ((sing_count > 0)); then
    [[ -x "$SING_BOX_HOME/sing-box" ]] || {
      printf '缺少 Rainbow 管理的 sing-box，无法删除节点。\n' >&2
      return 1
    }
    sing_types_json=$(printf '%s\n' "${sing_types[@]}" | jq -Rn '[inputs]')
    write_sing_box_removal_config "$SING_BOX_HOME/config.json" "$sing_config" \
      "$sing_types_json" && "$SING_BOX_HOME/sing-box" check -c "$sing_config" || {
        printf '删除后的 sing-box 配置验证失败，原配置未修改。\n' >&2
        return 1
      }
    sing_backup=$(mktemp "$SING_BOX_HOME/config.json.backup.XXXXXX")
    install -m 0600 "$SING_BOX_HOME/config.json" "$sing_backup" || return 1
  fi

  if [[ "$quick_selected" == "1" ]] \
    && systemctl cat "$CLOUDFLARED_SERVICE" >/dev/null 2>&1; then
    systemctl is-active --quiet "$CLOUDFLARED_SERVICE" && quick_active=1
    if ! systemctl stop "$CLOUDFLARED_SERVICE"; then
      [[ "$quick_active" == "0" ]] || systemctl restart "$CLOUDFLARED_SERVICE" || true
      return 1
    fi
  fi
  if [[ "$named_selected" == "1" ]] \
    && systemctl cat "$CLOUDFLARED_NAMED_SERVICE" >/dev/null 2>&1; then
    systemctl is-active --quiet "$CLOUDFLARED_NAMED_SERVICE" && named_active=1
    if ! systemctl stop "$CLOUDFLARED_NAMED_SERVICE"; then
      [[ "$quick_active" == "0" ]] || systemctl restart "$CLOUDFLARED_SERVICE" || true
      return 1
    fi
  fi

  if [[ -n "$xray_backup" ]] && ! install -m 0600 "$xray_config" \
    "$XRAY_HOME/config.json"; then
    apply_failed=1
  fi
  if [[ "$apply_failed" == "0" && -n "$sing_backup" ]] \
    && ! install -m 0600 "$sing_config" "$SING_BOX_HOME/config.json"; then
    apply_failed=1
  fi
  if [[ "$apply_failed" == "0" && -n "$xray_backup" ]] \
    && ! systemctl restart "$XRAY_SERVICE"; then
    apply_failed=1
  fi
  if [[ "$apply_failed" == "0" && -n "$sing_backup" ]] \
    && ! systemctl restart "$SING_BOX_SERVICE"; then
    apply_failed=1
  fi

  if [[ "$apply_failed" == "1" ]]; then
    [[ -z "$xray_backup" ]] \
      || install -m 0600 "$xray_backup" "$XRAY_HOME/config.json" || true
    [[ -z "$sing_backup" ]] \
      || install -m 0600 "$sing_backup" "$SING_BOX_HOME/config.json" || true
    [[ -z "$xray_backup" ]] || systemctl restart "$XRAY_SERVICE" || true
    [[ -z "$sing_backup" ]] || systemctl restart "$SING_BOX_SERVICE" || true
    [[ "$quick_active" == "0" ]] || systemctl restart "$CLOUDFLARED_SERVICE" || true
    [[ "$named_active" == "0" ]] \
      || systemctl restart "$CLOUDFLARED_NAMED_SERVICE" || true
    printf '节点删除失败，已恢复原配置。\n' >&2
    return 1
  fi

  for type in ${xray_types[@]+"${xray_types[@]}"}; do
    rm -f "$XRAY_HOME/client-${type}.txt" "$XRAY_HOME/client-${type}.enc"
  done
  for type in ${sing_types[@]+"${sing_types[@]}"}; do
    rm -f "$SING_BOX_HOME/client-${type}.txt"
  done
  ((xray_count == 0)) || refresh_xray_client_info
  ((sing_count == 0)) || refresh_sing_box_client_info

  if [[ "$quick_selected" == "1" ]]; then
    systemctl disable "$CLOUDFLARED_SERVICE" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${CLOUDFLARED_SERVICE}.service" \
      "$CLOUDFLARED_LOG" "$CLOUDFLARED_HOST_FILE" "$CLOUDFLARED_ADDRESS_FILE"
  fi
  if [[ "$named_selected" == "1" ]]; then
    systemctl disable "$CLOUDFLARED_NAMED_SERVICE" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${CLOUDFLARED_NAMED_SERVICE}.service" \
      "$CLOUDFLARED_NAMED_TOKEN_FILE" "$CLOUDFLARED_NAMED_HOST_FILE"
  fi
  if [[ "$quick_selected" == "1" || "$named_selected" == "1" ]]; then
    systemctl daemon-reload
  fi
}

manage_node_removal() {
  local answer index input

  clear_screen
  show_header '卸载节点'
  discover_removable_nodes || return 1
  if ((REMOVE_NODE_COUNT == 0)); then
    printf '当前没有 Rainbow 管理的节点。\n'
    return
  fi

  printf '可卸载节点：\n'
  for ((index = 0; index < REMOVE_NODE_COUNT; index++)); do
    printf '%d) %-8s %s\n' "$((index + 1))" "${REMOVE_NODE_ENGINES[index]}" \
      "${REMOVE_NODE_LABELS[index]}"
  done
  printf '\n同一协议的直出和 WARP 节点会一起删除。\n'
  read -r -p '请输入要删除的序号，多个序号使用空格或逗号分隔：' input
  parse_node_selection "$input" "$REMOVE_NODE_COUNT" || {
    printf '序号格式错误或超出范围。\n' >&2
    return 1
  }

  printf '\n将删除：\n'
  for index in "${SELECTED_NODE_INDEXES[@]}"; do
    printf '  %d) %s - %s\n' "$index" "${REMOVE_NODE_ENGINES[index - 1]}" \
      "${REMOVE_NODE_LABELS[index - 1]}"
  done
  read -r -p '请输入 DELETE 确认删除：' answer
  [[ "$answer" == "DELETE" ]] || {
    printf '已取消删除。\n'
    return 1
  }

  remove_selected_nodes || return 1
  info "已删除 ${SELECTED_NODE_COUNT} 个节点"
}

manage_xray_nodes() {
  local choice

  while true; do
    clear_screen
    show_header 'X-ray 节点'
    printf '%s\n' \
      '请选择 X-ray 节点类型：' \
      '1) VLESS + REALITY + XHTTP' \
      '2) VLESS + REALITY + TCP' \
      '3) VLESS + TLS + WebSocket + Cloudflare CDN' \
      '4) VLESS + WebSocket + Cloudflare Argo 隧道' \
      '0) 返回' \
      ''
    read -r -p '请输入 [0/1/2/3/4]：' choice
    case "$choice" in
      1) NODE_TYPE="xhttp"; setup_xray_node || true; pause_menu ;;
      2) NODE_TYPE="tcp"; setup_xray_node || true; pause_menu ;;
      3) NODE_TYPE="ws"; setup_xray_node || true; pause_menu ;;
      4) NODE_TYPE="ws-tunnel"; setup_xray_node || true; pause_menu ;;
      0) return ;;
      *) printf '无效选项，请输入 0、1、2、3 或 4。\n' >&2 ;;
    esac
  done
}

valid_domain() {
  local domain=$1 label
  local -a labels
  [[ ${#domain} -le 253 && "$domain" == *.* ]] || return 1
  IFS='.' read -r -a labels <<<"$domain"
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 \
      && "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

normalize_domain() {
  local domain=${1//$'\r'/}
  domain=${domain#"${domain%%[![:space:]]*}"}
  domain=${domain%"${domain##*[![:space:]]}"}
  domain=${domain%.}
  printf '%s\n' "$domain" | tr '[:upper:]' '[:lower:]'
}

valid_self_signed_certificate() {
  [[ -s "$SELF_SIGNED_TLS_CERT" && -s "$SELF_SIGNED_TLS_KEY" ]] \
    && openssl x509 -in "$SELF_SIGNED_TLS_CERT" -noout -checkend 0 \
      -checkhost "$SELF_SIGNED_TLS_SERVER_NAME" >/dev/null 2>&1 \
    && validate_certificate_key_pair "$SELF_SIGNED_TLS_CERT" "$SELF_SIGNED_TLS_KEY"
}

valid_acme_certificate() {
  local domain
  [[ -s "$TLS_DOMAIN_FILE" && -s "$ACME_TLS_CERT" && -s "$ACME_TLS_KEY" ]] \
    || return 1
  IFS= read -r domain < "$TLS_DOMAIN_FILE"
  valid_domain "$domain" \
    && validate_certificate_pair "$domain" "$ACME_TLS_CERT" "$ACME_TLS_KEY"
}

select_sing_box_certificate() {
  local domain prefix
  SING_BOX_TLS_CERT="$SELF_SIGNED_TLS_CERT"
  SING_BOX_TLS_KEY="$SELF_SIGNED_TLS_KEY"
  SING_BOX_TLS_IS_PUBLIC=0
  SING_BOX_TLS_SERVER_NAME="$SELF_SIGNED_TLS_SERVER_NAME"

  valid_acme_certificate || return 0
  IFS= read -r domain < "$TLS_DOMAIN_FILE"
  SING_BOX_TLS_CERT="$ACME_TLS_CERT"
  SING_BOX_TLS_KEY="$ACME_TLS_KEY"
  SING_BOX_TLS_IS_PUBLIC=1
  SING_BOX_TLS_SERVER_NAME="$domain"

  if [[ "$NODE_ADDRESS" == "$domain" ]]; then
    return
  fi
  if [[ "$NODE_ADDRESS" == *."$domain" ]]; then
    prefix=${NODE_ADDRESS%."$domain"}
    if [[ "$prefix" != *.* ]]; then
      SING_BOX_TLS_SERVER_NAME=$NODE_ADDRESS
    fi
  fi
  return 0
}

install_lego() {
  local release_json tag version asset_name asset_url expected

  [[ -x "$ACME_BIN" ]] && return
  detect_arch
  info "正在查询 lego 最新版本"
  release_json=$(curl --retry 3 -fsSL \
    "https://api.github.com/repos/${LEGO_REPO}/releases/latest") || return 1
  tag=$(jq -r '.tag_name // empty' <<<"$release_json")
  version=${tag#v}
  asset_name="lego_v${version}_linux_${ARCH}.tar.gz"
  asset_url=$(jq -r --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")
  expected=$(jq -r --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .digest // empty' <<<"$release_json")
  expected=${expected#sha256:}
  [[ -n "$version" && -n "$asset_url" && "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || return 1

  download "$asset_url" "$TMP_DIR/$asset_name"
  verify_sha256 "$TMP_DIR/$asset_name" "${expected,,}"
  tar -xzf "$TMP_DIR/$asset_name" -C "$TMP_DIR" lego
  install -d -m 0700 "$ACME_HOME" "$ACME_DATA_HOME"
  install -m 0755 "$TMP_DIR/lego" "$ACME_BIN"
  info "lego ${tag} 已安装"
}

run_lego() {
  local domain=$1 token_file=$2
  CF_DNS_API_TOKEN_FILE="$token_file" "$ACME_BIN" run \
    --accept-tos \
    --server letsencrypt \
    --dns cloudflare \
    --domains "$domain" \
    --domains "*.$domain" \
    --path "$ACME_DATA_HOME"
}

validate_certificate_pair() {
  local domain=$1 cert_file=$2 key_file=$3
  openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null || return 1
  openssl x509 -in "$cert_file" -noout -checkhost "$domain" >/dev/null || return 1
  openssl x509 -in "$cert_file" -noout -checkhost "wildcard-check.$domain" \
    >/dev/null || return 1
  validate_certificate_key_pair "$cert_file" "$key_file"
}

validate_certificate_key_pair() {
  local cert_file=$1 key_file=$2 cert_public_key key_public_key
  cert_public_key=$(openssl x509 -in "$cert_file" -pubkey -noout | sha256sum | awk '{print $1}')
  key_public_key=$(openssl pkey -in "$key_file" -pubout 2>/dev/null \
    | sha256sum | awk '{print $1}')
  [[ -n "$cert_public_key" && "$cert_public_key" == "$key_public_key" ]]
}

generate_self_signed_certificate() {
  local cert_file=$1 key_file=$2
  openssl ecparam -name prime256v1 -genkey -noout -out "$key_file" || return 1
  openssl req -new -x509 -sha256 -days 3650 \
    -key "$key_file" -out "$cert_file" -subj "/CN=${SELF_SIGNED_TLS_SERVER_NAME}" \
    || return 1
  openssl x509 -in "$cert_file" -noout -checkend 0 \
    -checkhost "$SELF_SIGNED_TLS_SERVER_NAME" >/dev/null \
    && validate_certificate_key_pair "$cert_file" "$key_file"
}

restore_tls_files() {
  local had_cert=$1 had_key=$2 cert_backup=$3 key_backup=$4 cert_file=$5 key_file=$6
  if [[ "$had_cert" == "1" ]]; then
    install -m 0644 "$cert_backup" "$cert_file"
  else
    rm -f "$cert_file"
  fi
  if [[ "$had_key" == "1" ]]; then
    install -m 0600 "$key_backup" "$key_file"
  else
    rm -f "$key_file"
  fi
}

install_tls_certificate() {
  local source_cert=$1 source_key=$2 target_cert=$3 target_key=$4
  local cert_backup="$TMP_DIR/tls-cert.backup" key_backup="$TMP_DIR/tls-key.backup"
  local had_cert=0 had_key=0 service
  local -a services=()

  [[ -s "$source_cert" && -s "$source_key" ]] || return 1
  install -d -m 0700 "$(dirname "$target_cert")" || return 1
  if [[ -f "$target_cert" ]]; then
    install -m 0644 "$target_cert" "$cert_backup" || return 1
    had_cert=1
  fi
  if [[ -f "$target_key" ]]; then
    install -m 0600 "$target_key" "$key_backup" || return 1
    had_key=1
  fi
  if ! install -m 0644 "$source_cert" "$target_cert" \
    || ! install -m 0600 "$source_key" "$target_key"; then
    restore_tls_files "$had_cert" "$had_key" "$cert_backup" "$key_backup" \
      "$target_cert" "$target_key"
    return 1
  fi

  if [[ -f "$SING_BOX_HOME/config.json" \
    && -f "/etc/systemd/system/${SING_BOX_SERVICE}.service" ]] \
    && jq -e --arg cert "$target_cert" --arg key "$target_key" '
      any(.inbounds[]?;
        (.tls.certificate_path? == $cert) or (.tls.key_path? == $key))
    ' "$SING_BOX_HOME/config.json" >/dev/null; then
    services+=("$SING_BOX_SERVICE")
  fi
  if [[ -f "$XRAY_HOME/config.json" \
    && -f "/etc/systemd/system/${XRAY_SERVICE}.service" ]] \
    && jq -e --arg cert "$target_cert" --arg key "$target_key" '
      any(.inbounds[]?.streamSettings.tlsSettings.certificates[]?;
        (.certificateFile? == $cert) or (.keyFile? == $key))
    ' "$XRAY_HOME/config.json" >/dev/null; then
    services+=("$XRAY_SERVICE")
  fi
  for service in "${services[@]}"; do
    if ! systemctl restart "$service"; then
      restore_tls_files "$had_cert" "$had_key" "$cert_backup" "$key_backup" \
        "$target_cert" "$target_key"
      for service in "${services[@]}"; do
        systemctl restart "$service" || true
      done
      return 1
    fi
  done
}

deploy_acme_certificate() {
  local domain=$1 source_cert source_key staged_cert staged_key
  source_cert="$ACME_DATA_HOME/certificates/${domain}.crt"
  source_key="$ACME_DATA_HOME/certificates/${domain}.key"
  staged_cert="$TMP_DIR/tls-cert.pem"
  staged_key="$TMP_DIR/tls-key.pem"

  [[ -s "$source_cert" && -s "$source_key" ]] || return 1
  install -m 0644 "$source_cert" "$staged_cert"
  install -m 0600 "$source_key" "$staged_key"
  validate_certificate_pair "$domain" "$staged_cert" "$staged_key" || return 1
  install_tls_certificate "$staged_cert" "$staged_key" "$ACME_TLS_CERT" "$ACME_TLS_KEY"
}

install_acme_timer() {
  install -m 0644 /dev/null "/etc/systemd/system/${ACME_SERVICE}.service"
  cat > "/etc/systemd/system/${ACME_SERVICE}.service" <<EOF
[Unit]
Description=Rainbow ACME certificate renewal
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$RAINBOW_BIN acme-renew
EOF

  install -m 0644 /dev/null "/etc/systemd/system/${ACME_TIMER}"
  cat > "/etc/systemd/system/${ACME_TIMER}" <<EOF
[Unit]
Description=Daily Rainbow ACME certificate renewal check

[Timer]
OnCalendar=daily
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$ACME_TIMER"
}

configure_acme_certificate() {
  local domain token answer current_domain=""
  local token_file command_name

  for command_name in openssl tar; do
    command -v "$command_name" >/dev/null 2>&1 || {
      printf '申请 ACME 证书需要 %s 命令。\n' "$command_name" >&2
      return 1
    }
  done
  while true; do
    read -r -p '请输入根域名，例如 example.com：' domain
    domain=$(normalize_domain "$domain")
    valid_domain "$domain" && break
    printf '根域名格式错误。\n' >&2
  done
  if [[ -s "$TLS_DOMAIN_FILE" ]]; then
    IFS= read -r current_domain < "$TLS_DOMAIN_FILE"
  fi
  if [[ -n "$current_domain" && "$current_domain" != "$domain" ]]; then
    printf '当前证书域名为 %s，替换后已有客户端需要更新 SNI。\n' "$current_domain"
    read -r -p '请输入 REPLACE 确认替换：' answer
    [[ "$answer" == "REPLACE" ]] || {
      printf '已取消证书替换。\n'
      return 1
    }
  fi
  read -r -s -p '请输入 Cloudflare API Token：' token
  printf '\n'
  [[ -n "$token" ]] || {
    printf 'Cloudflare API Token 不能为空。\n' >&2
    return 1
  }
  printf '将申请包含 %s 和 *.%s 的证书。\n' "$domain" "$domain"

  token_file="$TMP_DIR/cf-token"
  printf '%s' "$token" > "$token_file"
  chmod 0600 "$token_file"
  unset token

  install_lego || {
    printf '安装 lego 失败。\n' >&2
    return 1
  }
  run_lego "$domain" "$token_file" || {
    printf 'ACME 证书签发失败，现有证书未修改。\n' >&2
    return 1
  }
  deploy_acme_certificate "$domain" || {
    printf '部署 ACME 证书失败，已保留原证书。\n' >&2
    return 1
  }
  install -d -m 0700 "$ACME_HOME" "$TLS_HOME" || return 1
  install -m 0600 "$token_file" "$ACME_CF_TOKEN_FILE" || return 1
  printf '%s\n' "$domain" > "$TLS_DOMAIN_FILE" || return 1
  chmod 0600 "$TLS_DOMAIN_FILE" || return 1

  install_acme_timer || {
    warn '证书已签发，但自动续期定时器安装失败。'
    return 1
  }
  info "ACME 证书已安装：$ACME_TLS_CERT"
}

remove_acme_certificate() {
  local answer config_file="$TMP_DIR/remove-acme.json" type
  local config_backup="$TMP_DIR/remove-acme.backup" timer_was_enabled=0
  local xray_config="$TMP_DIR/remove-acme-xray.json"
  local xray_backup="$TMP_DIR/remove-acme-xray.backup" ws_removed=0
  local -a removed_types=()

  if [[ ! -e "$ACME_TLS_CERT" && ! -e "$ACME_TLS_KEY" \
    && ! -e "$TLS_DOMAIN_FILE" && ! -e "$ACME_CF_TOKEN_FILE" ]]; then
    printf '当前没有 ACME 证书。\n'
    return
  fi
  read -r -p '请输入 REMOVE 确认移除当前 ACME 证书：' answer
  [[ "$answer" == "REMOVE" ]] || {
    printf '已取消移除。\n'
    return 1
  }
  systemctl is-enabled "$ACME_TIMER" >/dev/null 2>&1 && timer_was_enabled=1
  if systemctl cat "$ACME_TIMER" >/dev/null 2>&1; then
    systemctl disable --now "$ACME_TIMER" || return 1
  fi
  systemctl stop "$ACME_SERVICE" >/dev/null 2>&1 || true

  if [[ -x "$SING_BOX_HOME/sing-box" && -f "$SING_BOX_HOME/config.json" ]]; then
    for type in tuic anytls hysteria2; do
      if jq -e --arg tag "rainbow-${type}" --arg acme_cert "$ACME_TLS_CERT" \
        --arg acme_key "$ACME_TLS_KEY" '
          any(.inbounds[]?;
            (.tag == $tag)
            and ((.tls.certificate_path? == $acme_cert)
              or (.tls.key_path? == $acme_key)))
        ' "$SING_BOX_HOME/config.json" >/dev/null; then
        removed_types+=("$type")
      fi
    done
    if ! jq --arg acme_cert "$ACME_TLS_CERT" --arg acme_key "$ACME_TLS_KEY" \
      '
        def uses_acme:
          (.tls.certificate_path? == $acme_cert) or (.tls.key_path? == $acme_key);
        ([.inbounds[]? | select(uses_acme)]) as $removed
        | ([$removed[].users[]?.name]) as $removed_users
        | .inbounds = [(.inbounds // [])[] | select(uses_acme | not)]
        | .route = ((.route // {}) | .rules = [
            (.rules // [])[] | select(
              [(.auth_user // [])[]
                | select(. as $user | $removed_users | index($user))] | length == 0
            )
          ])
        | ([.route.rules[]? | select((.outbound // "") == "rainbow-warp")]
            | length > 0) as $needs_warp
        | if $needs_warp then .
          else .endpoints = ((.endpoints // [])
            | map(select((.tag // "") != "rainbow-warp")))
          end
      ' "$SING_BOX_HOME/config.json" > "$config_file" \
      || ! "$SING_BOX_HOME/sing-box" check -c "$config_file" \
      || ! install -m 0600 "$SING_BOX_HOME/config.json" "$config_backup" \
      || ! install -m 0600 "$config_file" "$SING_BOX_HOME/config.json"; then
      [[ "$timer_was_enabled" == "0" ]] || systemctl enable --now "$ACME_TIMER" || true
      return 1
    fi
    if [[ -f "/etc/systemd/system/${SING_BOX_SERVICE}.service" ]] \
      && ! systemctl restart "$SING_BOX_SERVICE"; then
      install -m 0600 "$config_backup" "$SING_BOX_HOME/config.json"
      systemctl restart "$SING_BOX_SERVICE" || true
      [[ "$timer_was_enabled" == "0" ]] || systemctl enable --now "$ACME_TIMER" || true
      return 1
    fi
  fi

  if [[ -x "$XRAY_HOME/xray" && -f "$XRAY_HOME/config.json" ]] \
    && jq -e 'any(.inbounds[]?; .tag == "rainbow-vless-ws")' \
      "$XRAY_HOME/config.json" >/dev/null; then
    if ! jq '
      .inbounds = [(.inbounds // [])[] | select(.tag != "rainbow-vless-ws")]
      | .routing = ((.routing // {}) | .rules = [
          (.rules // [])[]
          | select(((.user // []) | index("rainbow-ws-warp")) == null)
        ])
      | ([.routing.rules[]? | select((.outboundTag // "") == "rainbow-warp")]
          | length > 0) as $needs_warp
      | if $needs_warp then .
        else .outbounds = ((.outbounds // [])
          | map(select((.tag // "") != "rainbow-warp")))
        end
    ' "$XRAY_HOME/config.json" > "$xray_config" \
      || ! "$XRAY_HOME/xray" run -test -config "$xray_config" \
      || ! install -m 0600 "$XRAY_HOME/config.json" "$xray_backup" \
      || ! install -m 0600 "$xray_config" "$XRAY_HOME/config.json"; then
      [[ "$timer_was_enabled" == "0" ]] || systemctl enable --now "$ACME_TIMER" || true
      return 1
    fi
    if [[ -f "/etc/systemd/system/${XRAY_SERVICE}.service" ]] \
      && ! systemctl restart "$XRAY_SERVICE"; then
      install -m 0600 "$xray_backup" "$XRAY_HOME/config.json"
      systemctl restart "$XRAY_SERVICE" || true
      [[ "$timer_was_enabled" == "0" ]] || systemctl enable --now "$ACME_TIMER" || true
      return 1
    fi
    ws_removed=1
  fi

  rm -f "$ACME_TLS_CERT" "$ACME_TLS_KEY" "$TLS_DOMAIN_FILE" "$ACME_CF_TOKEN_FILE"
  rm -rf "$ACME_DATA_HOME"
  if ((${#removed_types[@]})); then
    for type in "${removed_types[@]}"; do
      rm -f "$SING_BOX_HOME/client-${type}.txt"
    done
    refresh_sing_box_client_info
  fi
  if [[ "$ws_removed" == "1" ]]; then
    rm -f "$XRAY_HOME/client-ws.txt"
    refresh_xray_client_info
  fi
  info 'ACME 证书及依赖此证书的节点已移除'
}

renew_acme_certificate() {
  local domain before_digest="" after_digest command_name
  for command_name in openssl sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || return 1
  done
  [[ -x "$ACME_BIN" && -s "$ACME_CF_TOKEN_FILE" \
    && -s "$TLS_DOMAIN_FILE" ]] || return 1
  IFS= read -r domain < "$TLS_DOMAIN_FILE"
  valid_domain "$domain" || return 1
  [[ -f "$ACME_TLS_CERT" ]] \
    && before_digest=$(sha256sum "$ACME_TLS_CERT" | awk '{print $1}')

  run_lego "$domain" "$ACME_CF_TOKEN_FILE" || return 1
  after_digest=$(sha256sum "$ACME_DATA_HOME/certificates/${domain}.crt" | awk '{print $1}')
  if [[ -n "$before_digest" && "$before_digest" == "$after_digest" ]]; then
    info 'ACME 证书暂不需要续期'
    return
  fi
  deploy_acme_certificate "$domain" || return 1
  info 'ACME 证书已续期并部署'
}

manage_tls_certificates() {
  local choice
  while true; do
    clear_screen
    show_header '证书管理'
    printf '%s\n' \
      '1) 申请/重新配置 ACME 证书' \
      '2) 移除当前 ACME 证书' \
      '0) 返回' \
      ''
    read -r -p '请输入 [0/1/2]：' choice
    case "$choice" in
      1) configure_acme_certificate || true; pause_menu ;;
      2) remove_acme_certificate || true; pause_menu ;;
      0) return ;;
      *) printf '无效选项，请输入 0、1 或 2。\n' >&2 ;;
    esac
  done
}

sing_box_version_at_least() {
  local major minor required_minor=$1 version
  version=$("$SING_BOX_HOME/sing-box" version | awk 'NR == 1 {print $3}')
  [[ "$version" =~ ^([0-9]+)[.]([0-9]+) ]] || return 1
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  ((major > 1 || (major == 1 && minor >= required_minor)))
}

sing_box_supports_anytls() {
  sing_box_version_at_least 12
}

sing_box_supports_hysteria2() {
  sing_box_version_at_least 5
}

sing_box_supports_wireguard_endpoint() {
  sing_box_version_at_least 11
}

ensure_self_signed_certificate() {
  local cert_file="$TMP_DIR/sing-box-cert.pem" key_file="$TMP_DIR/sing-box-key.pem"

  valid_self_signed_certificate && return

  if [[ -f "$LEGACY_SING_BOX_TLS_HOME/cert.pem" \
    && -f "$LEGACY_SING_BOX_TLS_HOME/key.pem" ]]; then
    if openssl x509 -in "$LEGACY_SING_BOX_TLS_HOME/cert.pem" -noout -checkend 0 \
      -checkhost "$SELF_SIGNED_TLS_SERVER_NAME" >/dev/null 2>&1 \
      && validate_certificate_key_pair "$LEGACY_SING_BOX_TLS_HOME/cert.pem" \
        "$LEGACY_SING_BOX_TLS_HOME/key.pem"; then
      install_tls_certificate "$LEGACY_SING_BOX_TLS_HOME/cert.pem" \
        "$LEGACY_SING_BOX_TLS_HOME/key.pem" "$SELF_SIGNED_TLS_CERT" \
        "$SELF_SIGNED_TLS_KEY" || return 1
      info "已迁移 sing-box 自签证书：$SELF_SIGNED_TLS_HOME"
      return
    fi
  fi
  generate_self_signed_certificate "$cert_file" "$key_file" || return 1
  install_tls_certificate "$cert_file" "$key_file" "$SELF_SIGNED_TLS_CERT" \
    "$SELF_SIGNED_TLS_KEY" || return 1
  info "已生成 sing-box 自签名 TLS 证书"
}

migrate_legacy_tls_layout() {
  local mode="self-signed" target_cert="$SELF_SIGNED_TLS_CERT"
  local target_key="$SELF_SIGNED_TLS_KEY" config_file="$TMP_DIR/tls-migration.json"
  local config_backup="$TMP_DIR/tls-migration.backup" domain source_cert source_key

  [[ -s "$LEGACY_TLS_MODE_FILE" ]] && IFS= read -r mode < "$LEGACY_TLS_MODE_FILE"
  if [[ "$mode" == "acme" ]]; then
    target_cert="$ACME_TLS_CERT"
    target_key="$ACME_TLS_KEY"
  fi

  if [[ -s "$LEGACY_TLS_CERT" && -s "$LEGACY_TLS_KEY" ]]; then
    if [[ ! -s "$target_cert" || ! -s "$target_key" ]]; then
      install -d -m 0700 "$(dirname "$target_cert")" || return 1
      install -m 0644 "$LEGACY_TLS_CERT" "$target_cert" || return 1
      install -m 0600 "$LEGACY_TLS_KEY" "$target_key" || return 1
    fi
    if [[ -x "$SING_BOX_HOME/sing-box" && -f "$SING_BOX_HOME/config.json" ]]; then
      jq --arg old_cert "$LEGACY_TLS_CERT" --arg old_key "$LEGACY_TLS_KEY" \
        --arg cert "$target_cert" --arg key "$target_key" '
          .inbounds = ((.inbounds // []) | map(
            if (.tls.certificate_path? == $old_cert) or (.tls.key_path? == $old_key)
            then .tls.certificate_path = $cert | .tls.key_path = $key
            else . end
          ))
        ' "$SING_BOX_HOME/config.json" > "$config_file" || return 1
      "$SING_BOX_HOME/sing-box" check -c "$config_file" || return 1
      install -m 0600 "$SING_BOX_HOME/config.json" "$config_backup" || return 1
      install -m 0600 "$config_file" "$SING_BOX_HOME/config.json" || return 1
      if [[ -f "/etc/systemd/system/${SING_BOX_SERVICE}.service" ]] \
        && ! systemctl restart "$SING_BOX_SERVICE"; then
        install -m 0600 "$config_backup" "$SING_BOX_HOME/config.json"
        systemctl restart "$SING_BOX_SERVICE" || true
        return 1
      fi
    fi
    rm -f "$LEGACY_TLS_CERT" "$LEGACY_TLS_KEY"
  fi
  rm -f "$LEGACY_TLS_MODE_FILE"

  if [[ ! -s "$ACME_TLS_CERT" && -s "$TLS_DOMAIN_FILE" ]]; then
    IFS= read -r domain < "$TLS_DOMAIN_FILE"
    source_cert="$ACME_DATA_HOME/certificates/${domain}.crt"
    source_key="$ACME_DATA_HOME/certificates/${domain}.key"
    if valid_domain "$domain" && [[ -s "$source_cert" && -s "$source_key" ]] \
      && validate_certificate_pair "$domain" "$source_cert" "$source_key"; then
      install_tls_certificate "$source_cert" "$source_key" "$ACME_TLS_CERT" \
        "$ACME_TLS_KEY" || return 1
    fi
  fi
}

read_sing_box_node_details() {
  local protocol="tcp"
  [[ "$SING_NODE_TYPE" == "tuic" || "$SING_NODE_TYPE" == "hysteria2" ]] \
    && protocol="udp"
  read_node_port "$protocol" || return
  read_node_address
}

resolve_sing_box_cli_node_details() {
  local protocol="tcp"
  [[ "$SING_NODE_TYPE" == "tuic" || "$SING_NODE_TYPE" == "hysteria2" ]] \
    && protocol="udp"

  if [[ -z "$NODE_PORT" ]]; then
    NODE_PORT=$(random_high_port "$protocol") || {
      printf '未找到可用的随机端口。\n' >&2
      return 1
    }
    printf '已选择随机端口：%s\n' "$NODE_PORT"
  else
    if port_in_use "$NODE_PORT" "$protocol"; then
      printf '端口 %s 已被占用。\n' "$NODE_PORT" >&2
      return 1
    fi
  fi

  if [[ -z "$NODE_ADDRESS" ]]; then
    NODE_ADDRESS=$(detect_public_ipv4) || {
      printf '无法检测公网 IPv4，请使用 --address 指定节点地址。\n' >&2
      return 1
    }
  fi
}

write_sing_box_node_config() {
  local current_config=$1 config_file=$2 tag="rainbow-${SING_NODE_TYPE}"
  local direct_user="rainbow-${SING_NODE_TYPE}" warp_user="rainbow-${SING_NODE_TYPE}-warp"

  jq \
    --arg type "$SING_NODE_TYPE" \
    --arg tag "$tag" \
    --arg direct_user "$direct_user" \
    --arg warp_user "$warp_user" \
    --arg warp_mode "$WARP_MODE" \
    --argjson port "$NODE_PORT" \
    --arg uuid "${SING_NODE_UUID:-}" \
    --arg warp_uuid "${SING_NODE_WARP_UUID:-}" \
    --arg password "$SING_NODE_PASSWORD" \
    --arg warp_password "${SING_NODE_WARP_PASSWORD:-}" \
    --arg certificate_path "$SING_BOX_TLS_CERT" \
    --arg key_path "$SING_BOX_TLS_KEY" \
    --arg warp_private_key "${WARP_PRIVATE_KEY:-}" \
    --arg warp_addresses "${WARP_ADDRESSES:-}" \
    --arg warp_public_key "${WARP_PUBLIC_KEY:-}" \
    --arg warp_allowed_ips "${WARP_ALLOWED_IPS:-}" \
    --arg warp_endpoint_address "${WARP_ENDPOINT_ADDRESS:-}" \
    --argjson warp_endpoint_port "${WARP_ENDPOINT_PORT:-0}" \
    --argjson warp_mtu "${WARP_MTU:-1280}" '
      def csv:
        split(",") | map(gsub("^[ \t]+|[ \t]+$"; "")) | map(select(length > 0));

      def user($name; $uuid; $password):
        {name: $name, password: $password}
        + if $type == "tuic" then {uuid: $uuid} else {} end;

      def node_users:
        if $warp_mode == "direct" then
          [user($direct_user; $uuid; $password)]
        elif $warp_mode == "both" then
          [user($direct_user; $uuid; $password),
            user($warp_user; $warp_uuid; $warp_password)]
        else
          [user($warp_user; $uuid; $password)]
        end;

      .inbounds = (
        ((.inbounds // []) | map(select((.tag // "") != $tag))) + [
          ({
            type: $type,
            tag: $tag,
            listen: "0.0.0.0",
            listen_port: $port,
            users: node_users,
            tls: ({
              enabled: true,
              certificate_path: $certificate_path,
              key_path: $key_path
            } + if $type == "tuic" then {alpn: ["h3"]} else {} end)
          } + if $type == "tuic" then {
            congestion_control: "bbr",
            zero_rtt_handshake: false
          } else {} end)
        ]
      )
      | .route = (
          (.route // {})
          | .rules = (
              (if $warp_mode == "direct" then [] else [{
                  auth_user: [$warp_user],
                  action: "route",
                  outbound: "rainbow-warp"
                }] end)
              + ((.rules // []) | map(select(
                  (((.outbound // "") == "rainbow-warp")
                    and ((.auth_user // []) | index($warp_user) != null)) | not
                )))
            )
        )
      | ([.route.rules[]? | select((.outbound // "") == "rainbow-warp")] | length > 0)
        as $needs_warp
      | .endpoints = (
          if $warp_mode == "direct" then
            if $needs_warp then (.endpoints // [])
            else ((.endpoints // []) | map(select((.tag // "") != "rainbow-warp"))) end
          else
            ((.endpoints // []) | map(select((.tag // "") != "rainbow-warp"))) + [{
              type: "wireguard",
              tag: "rainbow-warp",
              system: false,
              mtu: $warp_mtu,
              address: ($warp_addresses | csv),
              private_key: $warp_private_key,
              peers: [{
                address: $warp_endpoint_address,
                port: $warp_endpoint_port,
                public_key: $warp_public_key,
                allowed_ips: ($warp_allowed_ips | csv)
              }]
            }]
          end
        )
    ' "$current_config" > "$config_file"
}

write_sing_box_client_block() {
  local client_file=$1 uuid=$2 password=$3 label=$4 outbound=$5 encoded_label uri

  encoded_label=$(jq -rn --arg value "$label" '$value | @uri')

  case "$SING_NODE_TYPE" in
    tuic)
      uri="tuic://${uuid}:${password}@${NODE_ADDRESS}:${NODE_PORT}?congestion_control=bbr&alpn=h3&sni=${SING_BOX_TLS_SERVER_NAME}&udp_relay_mode=native"
      [[ "$SING_BOX_TLS_IS_PUBLIC" == "1" ]] || uri+="&allow_insecure=1"
      ;;
    anytls)
      uri="anytls://${password}@${NODE_ADDRESS}:${NODE_PORT}/?sni=${SING_BOX_TLS_SERVER_NAME}"
      [[ "$SING_BOX_TLS_IS_PUBLIC" == "1" ]] || uri+="&insecure=1"
      ;;
    hysteria2)
      uri="hysteria2://${password}@${NODE_ADDRESS}:${NODE_PORT}/?sni=${SING_BOX_TLS_SERVER_NAME}"
      if [[ "$SING_BOX_TLS_IS_PUBLIC" != "1" ]]; then
        uri+="&insecure=1&pinSHA256=${SING_BOX_CERT_SHA256}"
      fi
      ;;
  esac
  uri+="#${encoded_label}"

  printf '%s\n' \
    "类型：$label" \
    "出站：$outbound" \
    "地址：$NODE_ADDRESS" \
    "端口：$NODE_PORT" \
    "TLS SNI：$SING_BOX_TLS_SERVER_NAME" \
    "UUID：${uuid:--}" \
    "密码：$password" \
    "分享链接：$uri" >> "$client_file"
}

save_sing_box_client_info() {
  local client_file="$SING_BOX_HOME/client-${SING_NODE_TYPE}.txt" label prefix

  prefix=$(get_node_prefix)
  case "$SING_NODE_TYPE" in
    tuic) label="${prefix}-TUIC" ;;
    anytls) label="${prefix}-AnyTLS" ;;
    hysteria2) label="${prefix}-HY2" ;;
  esac
  install -m 0600 /dev/null "$client_file"
  case "$WARP_MODE" in
    direct)
      write_sing_box_client_block "$client_file" "$SING_NODE_UUID" \
        "$SING_NODE_PASSWORD" "$label" "直出"
      ;;
    both)
      write_sing_box_client_block "$client_file" "$SING_NODE_UUID" \
        "$SING_NODE_PASSWORD" "$label" "直出"
      printf '\n' >> "$client_file"
      write_sing_box_client_block "$client_file" "$SING_NODE_WARP_UUID" \
        "$SING_NODE_WARP_PASSWORD" "${label}-WARP" "WARP"
      ;;
    warp)
      write_sing_box_client_block "$client_file" "$SING_NODE_UUID" \
        "$SING_NODE_PASSWORD" "${label}-WARP" "WARP"
      ;;
  esac

  refresh_sing_box_client_info

  printf '\n节点搭建完成：\n'
  cat "$client_file"
  printf '全部客户端信息已保存至：%s\n' "$SING_BOX_HOME/client.txt"
  printf '请在服务器防火墙中开放端口：%s/%s\n\n' \
    "$NODE_PORT" "$([[ "$SING_NODE_TYPE" == "anytls" ]] && printf tcp || printf udp)"
}

refresh_sing_box_client_info() {
  local all_clients="$SING_BOX_HOME/client.txt" type

  install -m 0600 /dev/null "$all_clients"
  for type in tuic anytls hysteria2; do
    [[ -f "$SING_BOX_HOME/client-${type}.txt" ]] || continue
    [[ ! -s "$all_clients" ]] || printf '\n' >> "$all_clients"
    cat "$SING_BOX_HOME/client-${type}.txt" >> "$all_clients"
  done
}

setup_sing_box_node() {
  local backup_file command_name config_file="$TMP_DIR/sing-box-node-config.json"
  local service_file="/etc/systemd/system/${SING_BOX_SERVICE}.service"

  if [[ ! -x "$SING_BOX_HOME/sing-box" || ! -f "$SING_BOX_HOME/config.json" \
    || ! -f "$service_file" ]] \
    || ! grep -qx \
      "ExecStart=$SING_BOX_HOME/sing-box run -c $SING_BOX_HOME/config.json" "$service_file"; then
    printf '请先通过 Rainbow 安装 sing-box。\n' >&2
    return 1
  fi
  for command_name in openssl ss; do
    command -v "$command_name" >/dev/null 2>&1 || {
      printf '搭建 sing-box 节点需要 %s 命令。\n' "$command_name" >&2
      return 1
    }
  done
  if [[ "$SING_NODE_TYPE" == "anytls" ]] && ! sing_box_supports_anytls; then
    printf 'AnyTLS 需要 sing-box 1.12.0 或更高版本。\n' >&2
    return 1
  fi
  if [[ "$SING_NODE_TYPE" == "hysteria2" ]] && ! sing_box_supports_hysteria2; then
    printf 'Hysteria2 需要 sing-box 1.5.0 或更高版本。\n' >&2
    return 1
  fi
  if [[ "${CLI_MODE:-0}" != "1" ]]; then
    select_warp_mode
  fi
  if [[ "$WARP_MODE" != "direct" ]]; then
    if ! sing_box_supports_wireguard_endpoint; then
      printf 'WARP 需要 sing-box 1.11.0 或更高版本。\n' >&2
      return 1
    fi
    command -v getent >/dev/null 2>&1 || {
      printf '搭建 sing-box WARP 节点需要 getent 命令。\n' >&2
      return 1
    }
    ensure_warp_profile || {
      printf 'WARP 配置失败，原配置未修改。\n' >&2
      return 1
    }
    detect_warp_domain_strategy
    resolve_warp_endpoint || {
      printf 'WARP Endpoint 解析失败，原配置未修改。\n' >&2
      return 1
    }
  fi

  if [[ "${CLI_MODE:-0}" == "1" ]]; then
    resolve_sing_box_cli_node_details || return
  else
    read_sing_box_node_details || return
  fi
  ensure_self_signed_certificate || {
    printf '生成 sing-box TLS 证书失败。\n' >&2
    return 1
  }
  select_sing_box_certificate
  SING_BOX_CERT_SHA256=""
  if [[ "$SING_NODE_TYPE" == "hysteria2" && "$SING_BOX_TLS_IS_PUBLIC" != "1" ]]; then
    SING_BOX_CERT_SHA256=$(openssl x509 -in "$SING_BOX_TLS_CERT" -noout -fingerprint -sha256) || {
      printf '读取 TLS 证书指纹失败。\n' >&2
      return 1
    }
    SING_BOX_CERT_SHA256=${SING_BOX_CERT_SHA256#*=}
  fi
  SING_NODE_PASSWORD=$(random_hex 16)
  SING_NODE_WARP_PASSWORD=""
  [[ "$WARP_MODE" == "both" ]] && SING_NODE_WARP_PASSWORD=$(random_hex 16)
  SING_NODE_UUID=""
  SING_NODE_WARP_UUID=""
  if [[ "$SING_NODE_TYPE" == "tuic" ]]; then
    SING_NODE_UUID=$("$SING_BOX_HOME/sing-box" generate uuid) || {
      printf '生成 TUIC UUID 失败。\n' >&2
      return 1
    }
    if [[ "$WARP_MODE" == "both" ]]; then
      SING_NODE_WARP_UUID=$("$SING_BOX_HOME/sing-box" generate uuid) || {
        printf '生成 TUIC WARP UUID 失败。\n' >&2
        return 1
      }
    fi
  fi

  write_sing_box_node_config "$SING_BOX_HOME/config.json" "$config_file"
  "$SING_BOX_HOME/sing-box" check -c "$config_file" || {
    printf 'sing-box 配置验证失败，原配置未修改。\n' >&2
    return 1
  }

  backup_file=$(mktemp "$SING_BOX_HOME/config.json.backup.XXXXXX")
  install -m 0600 "$SING_BOX_HOME/config.json" "$backup_file"
  install -m 0600 "$config_file" "$SING_BOX_HOME/config.json"
  if ! systemctl restart "$SING_BOX_SERVICE"; then
    install -m 0600 "$backup_file" "$SING_BOX_HOME/config.json"
    systemctl restart "$SING_BOX_SERVICE" || true
    printf 'sing-box 启动失败，已恢复原配置：%s\n' "$backup_file" >&2
    return 1
  fi

  info "原配置已备份：$backup_file"
  save_sing_box_client_info
}

manage_sing_box_nodes() {
  local choice

  while true; do
    clear_screen
    show_header 'sing-box 节点'
    printf '%s\n' \
      '请选择 sing-box 节点类型：' \
      '1) TUIC' \
      '2) AnyTLS' \
      '3) Hysteria2' \
      '0) 返回' \
      ''
    read -r -p '请输入 [0/1/2/3]：' choice
    case "$choice" in
      1) SING_NODE_TYPE="tuic"; setup_sing_box_node || true; pause_menu ;;
      2) SING_NODE_TYPE="anytls"; setup_sing_box_node || true; pause_menu ;;
      3) SING_NODE_TYPE="hysteria2"; setup_sing_box_node || true; pause_menu ;;
      0) return ;;
      *) printf '无效选项，请输入 0、1、2 或 3。\n' >&2 ;;
    esac
  done
}

init_temp_dir() {
  TMP_DIR=$(mktemp -d)
  readonly TMP_DIR
  trap 'rm -rf "$TMP_DIR"' EXIT
}

prepare_rainbow() {
  require_root
  require_commands
  init_temp_dir

  install_rainbow_command
  migrate_legacy_tls_layout || die "迁移 TLS 证书失败"
  ensure_self_signed_certificate || die "初始化自签证书失败"
  rainbow_is_initialized || initialize_rainbow
}

show_sing_box_cli_help() {
  cat <<'EOF'
用法：
  rb sing-box list
  rb sing-box add <tuic|anytls|hysteria2> [选项]
  rb sing-box remove <tuic|anytls|hysteria2> [--yes]

选项：
  --port <端口>                  省略时随机生成
  --address <IP或域名>          省略时自动检测公网 IPv4
  --warp <direct|both|warp>      默认 direct
  --yes                         删除时跳过确认
  -h, --help                    显示帮助
EOF
}

sing_box_cli_error() {
  error "$1"
  printf '请使用 rb sing-box --help 查看用法。\n' >&2
  return 2
}

parse_sing_box_add_options() {
  CLI_MODE=1
  WARP_MODE="direct"
  NODE_PORT=""
  NODE_ADDRESS=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        [[ $# -ge 2 ]] || { sing_box_cli_error '缺少 --port 参数。'; return; }
        NODE_PORT=$2
        shift 2
        ;;
      --address)
        [[ $# -ge 2 ]] || { sing_box_cli_error '缺少 --address 参数。'; return; }
        NODE_ADDRESS=$2
        shift 2
        ;;
      --warp)
        [[ $# -ge 2 ]] || { sing_box_cli_error '缺少 --warp 参数。'; return; }
        WARP_MODE=$2
        shift 2
        ;;
      *)
        sing_box_cli_error "未知参数：$1"
        return
        ;;
    esac
  done

  if [[ -n "$NODE_PORT" ]]; then
    [[ "$NODE_PORT" =~ ^[0-9]+$ && ${#NODE_PORT} -le 5 ]] \
      || { sing_box_cli_error '端口必须是 1 到 65535 之间的整数。'; return; }
    NODE_PORT=$((10#$NODE_PORT))
    ((NODE_PORT >= 1 && NODE_PORT <= 65535)) \
      || { sing_box_cli_error '端口必须是 1 到 65535 之间的整数。'; return; }
  fi
  [[ -z "$NODE_ADDRESS" \
    || "$NODE_ADDRESS" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] \
    || { sing_box_cli_error '节点地址格式错误。'; return; }
  [[ "$WARP_MODE" =~ ^(direct|both|warp)$ ]] \
    || { sing_box_cli_error '--warp 仅支持 direct、both 或 warp。'; return; }
}

run_sing_box_remove_command() {
  local answer assume_yes=0 command_name label tag type=${1:-}
  shift || true

  if [[ "$type" == "-h" || "$type" == "--help" ]]; then
    show_sing_box_cli_help
    return
  fi
  [[ "$type" =~ ^(tuic|anytls|hysteria2)$ ]] \
    || { sing_box_cli_error "不支持的 sing-box 节点类型：${type:-未指定}"; return; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) assume_yes=1 ;;
      *) sing_box_cli_error "未知参数：$1"; return ;;
    esac
    shift
  done

  require_root
  for command_name in install jq systemctl; do
    command -v "$command_name" >/dev/null 2>&1 || die "缺少依赖：${command_name}"
  done
  init_temp_dir
  if [[ ! -f "$SING_BOX_HOME/config.json" ]]; then
    printf '当前没有 %s 节点。\n' "$type"
    return
  fi
  jq -e 'type == "object"' "$SING_BOX_HOME/config.json" >/dev/null || {
    printf 'sing-box 配置格式错误，无法删除节点。\n' >&2
    return 1
  }
  tag="rainbow-${type}"
  if ! jq -e --arg tag "$tag" 'any(.inbounds[]?; .tag == $tag)' \
    "$SING_BOX_HOME/config.json" >/dev/null; then
    printf '当前没有 %s 节点。\n' "$type"
    return
  fi
  case "$type" in
    tuic) label="TUIC" ;;
    anytls) label="AnyTLS" ;;
    hysteria2) label="Hysteria2" ;;
  esac

  if [[ "$assume_yes" != "1" ]]; then
    printf '将删除 sing-box 节点：%s\n' "$label"
    printf '同一协议的直出和 WARP 节点会一起删除。\n'
    read -r -p '请输入 DELETE 确认删除：' answer || return 1
    [[ "$answer" == "DELETE" ]] || {
      printf '已取消删除。\n'
      return 1
    }
  fi

  REMOVE_NODE_ENGINES=("sing-box")
  REMOVE_NODE_TYPES=("$type")
  REMOVE_NODE_LABELS=("$label")
  SELECTED_NODE_INDEXES=("1")
  SELECTED_NODE_COUNT=1
  remove_selected_nodes || return
  info "已删除 sing-box ${label} 节点"
}

run_sing_box_command() {
  local command=${1:-}

  case "$command" in
    list)
      [[ $# -eq 1 ]] || { sing_box_cli_error 'list 不支持额外参数。'; return; }
      require_root
      command -v systemctl >/dev/null 2>&1 || die '缺少依赖：systemctl'
      show_nodes "$SING_BOX_SERVICE" "$SING_BOX_HOME/client.txt" 'sing-box'
      ;;
    add)
      shift
      [[ $# -gt 0 ]] || { sing_box_cli_error '缺少 sing-box 节点类型。'; return; }
      if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_sing_box_cli_help
        return
      fi
      SING_NODE_TYPE=$1
      shift
      [[ "$SING_NODE_TYPE" =~ ^(tuic|anytls|hysteria2)$ ]] \
        || { sing_box_cli_error "不支持的 sing-box 节点类型：$SING_NODE_TYPE"; return; }
      parse_sing_box_add_options "$@" || return
      prepare_rainbow
      setup_sing_box_node
      ;;
    remove)
      shift
      run_sing_box_remove_command "$@"
      ;;
    -h | --help | help)
      show_sing_box_cli_help
      ;;
    '')
      sing_box_cli_error '缺少 sing-box 子命令。'
      ;;
    *)
      sing_box_cli_error "未知 sing-box 子命令：$command"
      ;;
  esac
}

main() {
  prepare_rainbow

  while true; do
    clear_screen
    show_header '主菜单'
    show_installation_status
    select_action

    if [[ "$ACTION" == "uninstall" ]]; then
      uninstall_rainbow && exit
      pause_menu
      continue
    fi
    if [[ "$ACTION" == "show-nodes" ]]; then
      show_all_nodes
      continue
    fi
    if [[ "$ACTION" == "remove-nodes" ]]; then
      manage_node_removal || true
      pause_menu
      continue
    fi
    if [[ "$ACTION" == "edit-node" ]]; then
      manage_node_edit || true
      pause_menu
      continue
    fi
    if [[ "$ACTION" == "xray-node" ]]; then
      manage_xray_nodes
      continue
    fi
    if [[ "$ACTION" == "sing-box-node" ]]; then
      manage_sing_box_nodes
      continue
    fi
    if [[ "$ACTION" == "tls" ]]; then
      manage_tls_certificates
      continue
    fi
    if [[ "$ACTION" == "node-prefix" ]]; then
      configure_node_prefix
      pause_menu
      continue
    fi
  done
}

run_command() {
  case "${1:-}" in
    --install)
      prepare_rainbow
      printf 'Rainbow 初始化安装完成，后续可直接运行 rb。\n'
      ;;
    sing-box)
      shift
      run_sing_box_command "$@"
      ;;
    acme-renew)
      require_root
      require_commands
      init_temp_dir
      renew_acme_certificate
      ;;
    quick-tunnel-refresh)
      require_root
      require_commands
      refresh_quick_tunnel_client
      ;;
    *) main ;;
  esac
}

run_command "$@"
