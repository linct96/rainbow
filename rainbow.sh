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
    '3) 更新 rainbow'

  while true; do
    read -r -p '请输入 [1/2/3]：' choice
    case "$choice" in
      1) ACTION="install"; PRODUCT="sing-box"; REPO="$SING_BOX_REPO"; return ;;
      2) ACTION="install"; PRODUCT="xray"; REPO="$XRAY_REPO"; return ;;
      3) ACTION="update"; return ;;
      *) printf '无效选项，请输入 1、2 或 3。\n' >&2 ;;
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

main() {
  require_root
  require_commands

  TMP_DIR=$(mktemp -d)
  readonly TMP_DIR
  trap 'rm -rf "$TMP_DIR"' EXIT

  install_rainbow_command
  show_installation_status
  select_action

  if [[ "$ACTION" == "update" ]]; then
    update_rainbow
    return
  fi

  detect_arch
  read_version

  case "$PRODUCT" in
    sing-box) install_sing_box ;;
    xray) install_xray ;;
  esac

  log "${PRODUCT} ${VERSION} 安装完成"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
