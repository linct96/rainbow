#!/usr/bin/env bash

set -Eeuo pipefail

readonly SING_BOX_REPO="SagerNet/sing-box"
readonly XRAY_REPO="XTLS/Xray-core"
readonly WGCF_REPO="ViRb3/wgcf"
readonly LEGO_REPO="go-acme/lego"
readonly RAINBOW_URL="https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh"
readonly RAINBOW_BIN="/usr/local/bin/rb"
readonly RAINBOW_HOME="${HOME:-/root}/rainbow"
readonly SING_BOX_HOME="$RAINBOW_HOME/sing-box"
readonly XRAY_HOME="$RAINBOW_HOME/xray"
readonly WARP_HOME="$XRAY_HOME/warp"
readonly WGCF_BIN="$WARP_HOME/wgcf"
readonly WGCF_ACCOUNT="$WARP_HOME/wgcf-account.toml"
readonly WGCF_PROFILE="$WARP_HOME/wgcf-profile.conf"
readonly TLS_HOME="$RAINBOW_HOME/tls"
readonly TLS_CERT="$TLS_HOME/cert.pem"
readonly TLS_KEY="$TLS_HOME/key.pem"
readonly TLS_DOMAIN_FILE="$TLS_HOME/domain"
readonly TLS_MODE_FILE="$TLS_HOME/mode"
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

TLS_MODE="self-signed"
SING_BOX_TLS_SERVER_NAME="$SELF_SIGNED_TLS_SERVER_NAME"

log() {
  printf '[安装] %s\n' "$*"
}

die() {
  printf '[错误] %s\n' "$*" >&2
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
    '4) 搭建 sing-box 节点' \
    '5) 查看所有节点' \
    '6) 更新 rainbow' \
    '7) 一键卸载' \
    '8) TLS 证书管理' \
    ''

  while true; do
    read -r -p '请输入 [1/2/3/4/5/6/7/8]：' choice
    case "$choice" in
      1) ACTION="install"; PRODUCT="sing-box"; REPO="$SING_BOX_REPO"; return ;;
      2) ACTION="install"; PRODUCT="xray"; REPO="$XRAY_REPO"; return ;;
      3) ACTION="xray-node"; return ;;
      4) ACTION="sing-box-node"; return ;;
      5) ACTION="show-nodes"; return ;;
      6) ACTION="update"; return ;;
      7) ACTION="uninstall"; return ;;
      8) ACTION="tls"; return ;;
      *) printf '无效选项，请输入 1、2、3、4、5、6、7 或 8。\n' >&2 ;;
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

  for unit in "$ACME_TIMER" "$ACME_SERVICE" "$XRAY_SERVICE" "$SING_BOX_SERVICE"; do
    systemctl cat "$unit" >/dev/null 2>&1 || continue
    systemctl disable --now "$unit" || {
      printf '停止服务 %s 失败，卸载已中止。\n' "$unit" >&2
      return 1
    }
  done

  rm -f "/etc/systemd/system/${XRAY_SERVICE}.service" \
    "/etc/systemd/system/${SING_BOX_SERVICE}.service" \
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

select_warp_mode() {
  local choice

  printf '%s\n' \
    '' \
    '请选择该节点的 WARP 出站模式：' \
    '1) 同时创建直出和 WARP 节点（默认）' \
    '2) 不启用 WARP' \
    '3) 仅创建 WARP 节点' \
    ''
  while true; do
    read -r -p '请输入 [1/2/3]（直接回车选择 1）：' choice
    case "${choice:-1}" in
      1) WARP_MODE="both"; return ;;
      2) WARP_MODE="direct"; return ;;
      3) WARP_MODE="warp"; return ;;
      *) printf '无效选项，请输入 1、2 或 3。\n' >&2 ;;
    esac
  done
}

install_wgcf() {
  local release_json tag version asset_name asset_url expected actual

  detect_arch
  log "正在查询 wgcf 最新版本"
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
  log "wgcf ${tag} 已安装"
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
  local answer

  load_wgcf_profile && return
  install -d -m 0700 "$WARP_HOME"
  [[ -x "$WGCF_BIN" ]] || install_wgcf || return

  if [[ ! -s "$WGCF_ACCOUNT" ]]; then
    printf '%s\n' \
      '首次启用 WARP 需要通过 wgcf 注册 Cloudflare WARP 账户。' \
      '服务条款：https://www.cloudflare.com/application/terms/'
    read -r -p '是否同意并继续 [y/N]：' answer
    [[ "$answer" =~ ^[Yy]$ ]] || {
      printf '已取消 WARP 配置。\n' >&2
      return 1
    }
    "$WGCF_BIN" register --accept-tos --config "$WGCF_ACCOUNT" || {
      [[ -s "$WGCF_ACCOUNT" ]] || return 1
      log "wgcf 已生成账户，继续验证配置"
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
  local key_output

  NODE_UUID=$("$XRAY_HOME/xray" uuid)
  NODE_WARP_UUID=""
  if [[ "$WARP_MODE" == "both" ]]; then
    NODE_WARP_UUID=$("$XRAY_HOME/xray" uuid)
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
  local current_config=$1 config_file=$2 flow network tag warp_email

  if [[ "$NODE_TYPE" == "xhttp" ]]; then
    network="xhttp"
    flow=""
  else
    network="tcp"
    flow="xtls-rprx-vision"
  fi
  tag="rainbow-vless-${NODE_TYPE}"
  warp_email="rainbow-${NODE_TYPE}-warp"

  jq \
    --argjson port "$NODE_PORT" \
    --arg uuid "$NODE_UUID" \
    --arg warp_uuid "$NODE_WARP_UUID" \
    --arg warp_mode "$WARP_MODE" \
    --arg flow "$flow" \
    --arg network "$network" \
    --arg tag "$tag" \
    --arg warp_email "$warp_email" \
    --arg path "$NODE_PATH" \
    --arg target "${NODE_SERVER_NAME}:443" \
    --arg server_name "$NODE_SERVER_NAME" \
    --arg private_key "$NODE_PRIVATE_KEY" \
    --arg short_id "$NODE_SHORT_ID" \
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
          listen: "0.0.0.0",
          port: $port,
          protocol: "vless",
          settings: {
            clients: node_clients,
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
  local client_file=$1 uuid=$2 label=$3 outbound=$4 encoded_path uri

  if [[ "$NODE_TYPE" == "xhttp" ]]; then
    encoded_path=$(jq -rn --arg value "$NODE_PATH" '$value | @uri')
    uri="vless://${uuid}@${NODE_ADDRESS}:${NODE_PORT}?encryption=none&security=reality&sni=${NODE_SERVER_NAME}&fp=chrome&pbk=${NODE_PUBLIC_KEY}&sid=${NODE_SHORT_ID}&type=xhttp&path=${encoded_path}&mode=auto#${label}"
  else
    uri="vless://${uuid}@${NODE_ADDRESS}:${NODE_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${NODE_SERVER_NAME}&fp=chrome&pbk=${NODE_PUBLIC_KEY}&sid=${NODE_SHORT_ID}&type=tcp&headerType=none#${label}"
  fi

  printf '%s\n' \
    "类型：$label" \
    "出站：$outbound" \
    "地址：$NODE_ADDRESS" \
    "端口：$NODE_PORT" \
    "伪装域名：$NODE_SERVER_NAME" \
    "XHTTP 路径：${NODE_PATH:--}" \
    "UUID：$uuid" \
    "Public Key：$NODE_PUBLIC_KEY" \
    "Short ID：$NODE_SHORT_ID" \
    "分享链接：$uri" >> "$client_file"
}

save_xray_client_info() {
  local all_clients="$XRAY_HOME/client.txt" client_file first_line label

  if [[ -f "$all_clients" && ! -f "$XRAY_HOME/client-xhttp.txt" \
    && ! -f "$XRAY_HOME/client-tcp.txt" ]]; then
    IFS= read -r first_line < "$all_clients" || true
    case "$first_line" in
      '类型：Rainbow-XHTTP') install -m 0600 "$all_clients" "$XRAY_HOME/client-xhttp.txt" ;;
      '类型：Rainbow-TCP') install -m 0600 "$all_clients" "$XRAY_HOME/client-tcp.txt" ;;
    esac
  fi

  [[ "$NODE_TYPE" == "xhttp" ]] \
    && label="Rainbow-$(hostname)-XHTTP" || label="Rainbow-$(hostname)-TCP"

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

  install -m 0600 /dev/null "$all_clients"
  for type in xhttp tcp; do
    [[ -f "$XRAY_HOME/client-${type}.txt" ]] || continue
    [[ ! -s "$all_clients" ]] || printf '\n' >> "$all_clients"
    cat "$XRAY_HOME/client-${type}.txt" >> "$all_clients"
  done

  printf '\n节点搭建完成：\n'
  cat "$client_file"
  printf '全部客户端信息已保存至：%s\n\n' "$all_clients"
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

  select_warp_mode
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

manage_xray_nodes() {
  local choice

  while true; do
    clear_screen
    show_header 'X-ray 节点'
    printf '%s\n' \
      '请选择 X-ray 节点类型：' \
      '1) VLESS + REALITY + XHTTP' \
      '2) VLESS + REALITY + TCP' \
      '0) 返回' \
      ''
    read -r -p '请输入 [0/1/2]：' choice
    case "$choice" in
      1) NODE_TYPE="xhttp"; setup_xray_node || true; pause_menu ;;
      2) NODE_TYPE="tcp"; setup_xray_node || true; pause_menu ;;
      0) return ;;
      *) printf '无效选项，请输入 0、1 或 2。\n' >&2 ;;
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

load_tls_settings() {
  local domain mode
  TLS_MODE="self-signed"
  SING_BOX_TLS_SERVER_NAME="$SELF_SIGNED_TLS_SERVER_NAME"

  [[ -s "$TLS_MODE_FILE" && -s "$TLS_DOMAIN_FILE" ]] || return 0
  IFS= read -r mode < "$TLS_MODE_FILE"
  IFS= read -r domain < "$TLS_DOMAIN_FILE"
  if [[ "$mode" == "acme" ]] && valid_domain "$domain" \
    && [[ -s "$TLS_CERT" && -s "$TLS_KEY" ]]; then
    TLS_MODE="acme"
    SING_BOX_TLS_SERVER_NAME="$domain"
  fi
}

select_sing_box_tls_server_name() {
  local domain prefix
  load_tls_settings
  [[ "$TLS_MODE" == "acme" ]] || return 0
  domain=$SING_BOX_TLS_SERVER_NAME

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
  log "正在查询 lego 最新版本"
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
  log "lego ${tag} 已安装"
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
  local domain=$1 cert_file=$2 key_file=$3 cert_public_key key_public_key
  openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null || return 1
  openssl x509 -in "$cert_file" -noout -checkhost "$domain" >/dev/null || return 1
  openssl x509 -in "$cert_file" -noout -checkhost "wildcard-check.$domain" \
    >/dev/null || return 1
  cert_public_key=$(openssl x509 -in "$cert_file" -pubkey -noout | sha256sum | awk '{print $1}')
  key_public_key=$(openssl pkey -in "$key_file" -pubout 2>/dev/null \
    | sha256sum | awk '{print $1}')
  [[ -n "$cert_public_key" && "$cert_public_key" == "$key_public_key" ]]
}

write_sing_box_tls_paths() {
  local current_config=$1 output_config=$2
  jq \
    --arg cert "$TLS_CERT" \
    --arg key "$TLS_KEY" \
    --arg legacy_cert "$LEGACY_SING_BOX_TLS_HOME/cert.pem" \
    --arg legacy_key "$LEGACY_SING_BOX_TLS_HOME/key.pem" '
      .inbounds = ((.inbounds // []) | map(
        if ((.tag // "") == "rainbow-tuic")
          or ((.tag // "") == "rainbow-anytls")
          or ((.tag // "") == "rainbow-hysteria2")
          or (.tls.certificate_path? == $legacy_cert)
          or (.tls.key_path? == $legacy_key)
        then .tls.certificate_path = $cert | .tls.key_path = $key
        else . end
      ))
    ' "$current_config" > "$output_config"
}

restore_tls_files() {
  local had_cert=$1 had_key=$2 cert_backup=$3 key_backup=$4
  if [[ "$had_cert" == "1" ]]; then
    install -m 0644 "$cert_backup" "$TLS_CERT"
  else
    rm -f "$TLS_CERT"
  fi
  if [[ "$had_key" == "1" ]]; then
    install -m 0600 "$key_backup" "$TLS_KEY"
  else
    rm -f "$TLS_KEY"
  fi
}

deploy_acme_certificate() {
  local domain=$1 source_cert source_key staged_cert staged_key config_file config_backup
  local cert_backup="$TMP_DIR/tls-cert.backup" key_backup="$TMP_DIR/tls-key.backup"
  local had_cert=0 had_key=0 has_sing_box=0
  source_cert="$ACME_DATA_HOME/certificates/${domain}.crt"
  source_key="$ACME_DATA_HOME/certificates/${domain}.key"
  staged_cert="$TMP_DIR/tls-cert.pem"
  staged_key="$TMP_DIR/tls-key.pem"
  config_file="$TMP_DIR/sing-box-tls-config.json"
  config_backup="$TMP_DIR/sing-box-config.backup"

  [[ -s "$source_cert" && -s "$source_key" ]] || return 1
  install -m 0644 "$source_cert" "$staged_cert"
  install -m 0600 "$source_key" "$staged_key"
  validate_certificate_pair "$domain" "$staged_cert" "$staged_key" || return 1

  install -d -m 0700 "$TLS_HOME"
  if [[ -f "$TLS_CERT" ]]; then
    install -m 0644 "$TLS_CERT" "$cert_backup"
    had_cert=1
  fi
  if [[ -f "$TLS_KEY" ]]; then
    install -m 0600 "$TLS_KEY" "$key_backup"
    had_key=1
  fi
  if ! install -m 0644 "$staged_cert" "$TLS_CERT" \
    || ! install -m 0600 "$staged_key" "$TLS_KEY"; then
    restore_tls_files "$had_cert" "$had_key" "$cert_backup" "$key_backup"
    return 1
  fi

  if [[ -x "$SING_BOX_HOME/sing-box" && -f "$SING_BOX_HOME/config.json" \
    && -f "/etc/systemd/system/${SING_BOX_SERVICE}.service" ]]; then
    has_sing_box=1
    install -m 0600 "$SING_BOX_HOME/config.json" "$config_backup"
    if ! write_sing_box_tls_paths "$SING_BOX_HOME/config.json" "$config_file" \
      || ! "$SING_BOX_HOME/sing-box" check -c "$config_file"; then
      restore_tls_files "$had_cert" "$had_key" "$cert_backup" "$key_backup"
      return 1
    fi
    if ! install -m 0600 "$config_file" "$SING_BOX_HOME/config.json"; then
      restore_tls_files "$had_cert" "$had_key" "$cert_backup" "$key_backup"
      return 1
    fi
  fi

  if [[ "$has_sing_box" == "1" ]] && ! systemctl restart "$SING_BOX_SERVICE"; then
    restore_tls_files "$had_cert" "$had_key" "$cert_backup" "$key_backup"
    install -m 0600 "$config_backup" "$SING_BOX_HOME/config.json"
    systemctl restart "$SING_BOX_SERVICE" || true
    return 1
  fi
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
  local token_file domain_file mode_file command_name

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
  read -r -p "是否接受 Let's Encrypt 服务条款并继续 [y/N]：" answer
  [[ "$answer" =~ ^[Yy]$ ]] || {
    printf '已取消证书申请。\n'
    return 1
  }

  token_file="$TMP_DIR/cf-token"
  domain_file="$TMP_DIR/acme-domain"
  mode_file="$TMP_DIR/tls-mode"
  printf '%s' "$token" > "$token_file"
  printf '%s\n' "$domain" > "$domain_file"
  printf '%s\n' 'acme' > "$mode_file"
  chmod 0600 "$token_file" "$domain_file" "$mode_file"
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

  install -d -m 0700 "$ACME_HOME" "$TLS_HOME"
  install -m 0600 "$token_file" "$ACME_CF_TOKEN_FILE"
  install -m 0600 "$domain_file" "$TLS_DOMAIN_FILE"
  install -m 0600 "$mode_file" "$TLS_MODE_FILE"
  install_acme_timer || {
    printf '证书已签发，但自动续期定时器安装失败。\n' >&2
    return 1
  }
  log "ACME 证书已安装：$TLS_CERT"
  if [[ -f "$SING_BOX_HOME/client-tuic.txt" \
    || -f "$SING_BOX_HOME/client-anytls.txt" \
    || -f "$SING_BOX_HOME/client-hysteria2.txt" ]]; then
    printf '已有客户端配置仍可连接，但请重新搭建节点以生成启用证书校验的新链接。\n'
  fi
}

renew_acme_certificate() {
  local domain before_digest="" after_digest command_name
  for command_name in openssl sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || return 1
  done
  [[ -x "$ACME_BIN" && -s "$ACME_CF_TOKEN_FILE" \
    && -s "$TLS_DOMAIN_FILE" && -s "$TLS_MODE_FILE" ]] || return 1
  IFS= read -r domain < "$TLS_DOMAIN_FILE"
  valid_domain "$domain" || return 1
  [[ -f "$TLS_CERT" ]] && before_digest=$(sha256sum "$TLS_CERT" | awk '{print $1}')

  run_lego "$domain" "$ACME_CF_TOKEN_FILE" || return 1
  after_digest=$(sha256sum "$ACME_DATA_HOME/certificates/${domain}.crt" | awk '{print $1}')
  if [[ -n "$before_digest" && "$before_digest" == "$after_digest" ]]; then
    log 'ACME 证书暂不需要续期'
    return
  fi
  deploy_acme_certificate "$domain" || return 1
  log 'ACME 证书已续期并部署'
}

show_acme_certificate_status() {
  local domain mode end_date end_epoch now_epoch remaining_days
  if [[ ! -s "$TLS_MODE_FILE" ]]; then
    printf '当前未配置 ACME 证书。\n'
    return
  fi
  IFS= read -r mode < "$TLS_MODE_FILE"
  [[ -s "$TLS_DOMAIN_FILE" ]] && IFS= read -r domain < "$TLS_DOMAIN_FILE" || domain="-"
  printf '证书模式：%s\n根域名：%s\n证书路径：%s\n' "$mode" "$domain" "$TLS_CERT"
  if [[ -s "$TLS_CERT" ]]; then
    if command -v openssl >/dev/null 2>&1 \
      && openssl x509 -in "$TLS_CERT" -noout -issuer -dates -ext subjectAltName; then
      end_date=$(openssl x509 -in "$TLS_CERT" -noout -enddate | cut -d= -f2-)
      end_epoch=$(date -d "$end_date" +%s 2>/dev/null || true)
      now_epoch=$(date +%s)
      if [[ "$end_epoch" =~ ^[0-9]+$ ]]; then
        remaining_days=$(((end_epoch - now_epoch) / 86400))
        printf '剩余天数：%s\n' "$remaining_days"
      fi
    else
      printf '证书文件无效或缺少 openssl。\n' >&2
    fi
  else
    printf '证书文件不存在。\n' >&2
  fi
  if systemctl is-enabled "$ACME_TIMER" >/dev/null 2>&1; then
    printf '自动续期：已启用\n'
  else
    printf '自动续期：未启用\n'
  fi
}

manage_tls_certificates() {
  local choice
  while true; do
    clear_screen
    show_header 'TLS 证书管理'
    printf '%s\n' \
      '1) 申请/重新配置 ACME 证书' \
      '2) 查看证书状态' \
      '3) 立即检查续期' \
      '0) 返回' \
      ''
    read -r -p '请输入 [0/1/2/3]：' choice
    case "$choice" in
      1) configure_acme_certificate || true; pause_menu ;;
      2) show_acme_certificate_status || true; pause_menu ;;
      3) renew_acme_certificate || printf 'ACME 证书续期检查失败。\n' >&2; pause_menu ;;
      0) return ;;
      *) printf '无效选项，请输入 0、1、2 或 3。\n' >&2 ;;
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

ensure_sing_box_certificate() {
  local cert_file="$TMP_DIR/sing-box-cert.pem" key_file="$TMP_DIR/sing-box-key.pem"
  local configured_mode=""

  [[ -s "$TLS_MODE_FILE" ]] && IFS= read -r configured_mode < "$TLS_MODE_FILE"
  load_tls_settings
  if [[ "$configured_mode" == "acme" ]]; then
    [[ "$TLS_MODE" == "acme" ]] || {
      printf 'ACME 证书配置不完整，请先在 TLS 证书管理中重新申请。\n' >&2
      return 1
    }
    return
  fi
  if [[ -f "$TLS_CERT" && -f "$TLS_KEY" ]]; then
    return
  fi

  install -d -m 0700 "$TLS_HOME" || return 1
  if [[ -f "$LEGACY_SING_BOX_TLS_HOME/cert.pem" \
    && -f "$LEGACY_SING_BOX_TLS_HOME/key.pem" ]]; then
    install -m 0644 "$LEGACY_SING_BOX_TLS_HOME/cert.pem" "$TLS_CERT" || return 1
    install -m 0600 "$LEGACY_SING_BOX_TLS_HOME/key.pem" "$TLS_KEY" || return 1
    log "已迁移 sing-box TLS 证书：$TLS_HOME"
    return
  fi
  openssl ecparam -name prime256v1 -genkey -noout -out "$key_file" || return 1
  openssl req -new -x509 -sha256 -days 3650 \
    -key "$key_file" -out "$cert_file" -subj "/CN=${SELF_SIGNED_TLS_SERVER_NAME}" || return 1
  install -m 0644 "$cert_file" "$TLS_CERT" || return 1
  install -m 0600 "$key_file" "$TLS_KEY" || return 1
  log "已生成 sing-box 自签名 TLS 证书"
}

read_sing_box_node_details() {
  local protocol="tcp"
  [[ "$SING_NODE_TYPE" == "tuic" || "$SING_NODE_TYPE" == "hysteria2" ]] \
    && protocol="udp"
  read_node_port "$protocol" || return
  read_node_address
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
    --arg certificate_path "$TLS_CERT" \
    --arg key_path "$TLS_KEY" \
    --arg legacy_certificate_path "$LEGACY_SING_BOX_TLS_HOME/cert.pem" \
    --arg legacy_key_path "$LEGACY_SING_BOX_TLS_HOME/key.pem" \
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
        ((.inbounds // []) | map(
          if ((.tag // "") == "rainbow-tuic")
            or ((.tag // "") == "rainbow-anytls")
            or ((.tag // "") == "rainbow-hysteria2")
            or (.tls.certificate_path? == $legacy_certificate_path)
            or (.tls.key_path? == $legacy_key_path)
          then .tls.certificate_path = $certificate_path
            | .tls.key_path = $key_path
          else . end
        ) | map(select((.tag // "") != $tag))) + [
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
  local client_file=$1 uuid=$2 password=$3 label=$4 outbound=$5 uri

  case "$SING_NODE_TYPE" in
    tuic)
      uri="tuic://${uuid}:${password}@${NODE_ADDRESS}:${NODE_PORT}?congestion_control=bbr&alpn=h3&sni=${SING_BOX_TLS_SERVER_NAME}&udp_relay_mode=native"
      [[ "$TLS_MODE" == "acme" ]] || uri+="&allow_insecure=1"
      ;;
    anytls)
      uri="anytls://${password}@${NODE_ADDRESS}:${NODE_PORT}/?sni=${SING_BOX_TLS_SERVER_NAME}"
      [[ "$TLS_MODE" == "acme" ]] || uri+="&insecure=1"
      ;;
    hysteria2)
      uri="hysteria2://${password}@${NODE_ADDRESS}:${NODE_PORT}/?sni=${SING_BOX_TLS_SERVER_NAME}"
      if [[ "$TLS_MODE" != "acme" ]]; then
        uri+="&insecure=1&pinSHA256=${SING_BOX_CERT_SHA256}"
      fi
      ;;
  esac
  uri+="#${label}"

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
  local all_clients="$SING_BOX_HOME/client.txt"
  local client_file="$SING_BOX_HOME/client-${SING_NODE_TYPE}.txt" label

  case "$SING_NODE_TYPE" in
    tuic) label="Rainbow-$(hostname)-TUIC" ;;
    anytls) label="Rainbow-$(hostname)-AnyTLS" ;;
    hysteria2) label="Rainbow-$(hostname)-HY2" ;;
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

  install -m 0600 /dev/null "$all_clients"
  for type in tuic anytls hysteria2; do
    [[ -f "$SING_BOX_HOME/client-${type}.txt" ]] || continue
    [[ ! -s "$all_clients" ]] || printf '\n' >> "$all_clients"
    cat "$SING_BOX_HOME/client-${type}.txt" >> "$all_clients"
  done

  printf '\n节点搭建完成：\n'
  cat "$client_file"
  printf '全部客户端信息已保存至：%s\n' "$all_clients"
  printf '请在服务器防火墙中开放端口：%s/%s\n\n' \
    "$NODE_PORT" "$([[ "$SING_NODE_TYPE" == "anytls" ]] && printf tcp || printf udp)"
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
  select_warp_mode
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

  read_sing_box_node_details || return
  ensure_sing_box_certificate || {
    printf '生成 sing-box TLS 证书失败。\n' >&2
    return 1
  }
  select_sing_box_tls_server_name
  SING_BOX_CERT_SHA256=""
  if [[ "$SING_NODE_TYPE" == "hysteria2" && "$TLS_MODE" != "acme" ]]; then
    SING_BOX_CERT_SHA256=$(openssl x509 -in "$TLS_CERT" -noout -fingerprint -sha256) || {
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

  log "原配置已备份：$backup_file"
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

main() {
  require_root
  require_commands
  init_temp_dir

  install_rainbow_command

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
    if [[ "$ACTION" == "update" ]]; then
      update_rainbow
      pause_menu
      continue
    fi
    if [[ "$ACTION" == "show-nodes" ]]; then
      show_all_nodes
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

    detect_arch
    read_version

    case "$PRODUCT" in
      sing-box) install_sing_box ;;
      xray) install_xray ;;
    esac

    log "${PRODUCT} ${VERSION} 安装完成"
    pause_menu
  done
}

run_command() {
  case "${1:-}" in
    acme-renew)
      require_root
      require_commands
      init_temp_dir
      renew_acme_certificate
      ;;
    *) main ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  run_command "$@"
fi
