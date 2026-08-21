#!/usr/bin/env bash

set -Eeuo pipefail

readonly SING_BOX_REPO="SagerNet/sing-box"
readonly XRAY_REPO="XTLS/Xray-core"

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

select_product() {
  printf '%s\n' \
    '请选择要安装的程序：' \
    '1) sing-box' \
    '2) Xray'

  while true; do
    read -r -p '请输入 [1/2]：' choice
    case "$choice" in
      1) PRODUCT="sing-box"; REPO="$SING_BOX_REPO"; return ;;
      2) PRODUCT="xray"; REPO="$XRAY_REPO"; return ;;
      *) printf '无效选项，请输入 1 或 2。\n' >&2 ;;
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
  install -m 0755 "$extracted_dir/sing-box" /usr/local/bin/sing-box
  install -d -m 0755 /etc/sing-box

  if [[ ! -e /etc/sing-box/config.json ]]; then
    install -m 0644 /dev/null /etc/sing-box/config.json
    printf '%s\n' '{"log":{"level":"info"},"inbounds":[]}' > /etc/sing-box/config.json
  fi

  install -m 0644 /dev/null /etc/systemd/system/sing-box.service
  cat > /etc/systemd/system/sing-box.service <<'EOF'
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  /usr/local/bin/sing-box check -c /etc/sing-box/config.json
  systemctl daemon-reload
  systemctl enable sing-box
  systemctl restart sing-box
  /usr/local/bin/sing-box version
  systemctl --no-pager --full status sing-box || true
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
  install -m 0755 "$TMP_DIR/xray/xray" /usr/local/bin/xray
  install -d -m 0755 /usr/local/share/xray /etc/xray
  install -m 0644 "$TMP_DIR/xray/geoip.dat" "$TMP_DIR/xray/geosite.dat" /usr/local/share/xray/

  if [[ ! -e /etc/xray/config.json ]]; then
    install -m 0644 /dev/null /etc/xray/config.json
    printf '%s\n' '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom"}]}' \
      > /etc/xray/config.json
  fi

  install -m 0644 /dev/null /etc/systemd/system/xray.service
  cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray service
After=network.target

[Service]
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  /usr/local/bin/xray run -test -config /etc/xray/config.json
  systemctl daemon-reload
  systemctl enable xray
  systemctl restart xray
  /usr/local/bin/xray version
  systemctl --no-pager --full status xray || true
}

main() {
  require_root
  require_commands
  detect_arch
  select_product
  read_version

  TMP_DIR=$(mktemp -d)
  readonly TMP_DIR
  trap 'rm -rf "$TMP_DIR"' EXIT

  case "$PRODUCT" in
    sing-box) install_sing_box ;;
    xray) install_xray ;;
  esac

  log "${PRODUCT} ${VERSION} 安装完成"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
