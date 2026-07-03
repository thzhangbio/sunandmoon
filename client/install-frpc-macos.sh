#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="sunandmoon"
BASE_DIR="${HOME}/.${APP_NAME}"
INSTALL_DIR="${BASE_DIR}/frp"
CONFIG_FILE="${BASE_DIR}/frpc.toml"
LOG_FILE="${BASE_DIR}/frpc.log"
PLIST_FILE="${HOME}/Library/LaunchAgents/com.sunandmoon.frpc.plist"

FRP_VERSION="${FRP_VERSION:-latest}"
VPS_ADDR="${VPS_ADDR:-}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_TOKEN="${FRP_TOKEN:-}"
SUNSHINE_LOCAL_IP="${SUNSHINE_LOCAL_IP:-127.0.0.1}"

log() {
  printf '\033[1;32m[mac]\033[0m %s\n' "$*"
}

fail() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "这个脚本只用于 macOS。"
need_cmd curl
need_cmd tar
need_cmd uname

if [[ -z "${VPS_ADDR}" ]]; then
  fail "请指定 VPS_ADDR，例如：VPS_ADDR=1.2.3.4 FRP_TOKEN=xxx bash client/install-frpc-macos.sh"
fi

if [[ -z "${FRP_TOKEN}" ]]; then
  fail "请指定 FRP_TOKEN。服务器上可用：sudo cat /etc/sunandmoon/frp-token"
fi

ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  arm64|aarch64) FRP_ARCH="arm64" ;;
  x86_64|amd64) FRP_ARCH="amd64" ;;
  *) fail "暂不支持的 Mac 架构：${ARCH_RAW}" ;;
esac

if [[ "${FRP_VERSION}" == "latest" ]]; then
  log "获取 frp 最新版本号..."
  TAG="$(curl -fsSL --connect-timeout 10 --max-time 30 https://api.github.com/repos/fatedier/frp/releases/latest | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [[ -n "${TAG}" ]] || fail "无法获取 frp 最新版本号。可以手动指定：FRP_VERSION=0.xx.x bash client/install-frpc-macos.sh"
  VERSION_NO_V="${TAG#v}"
else
  VERSION_NO_V="${FRP_VERSION#v}"
  TAG="v${VERSION_NO_V}"
fi

FRP_TARBALL="frp_${VERSION_NO_V}_darwin_${FRP_ARCH}.tar.gz"
FRP_URL="https://github.com/fatedier/frp/releases/download/${TAG}/${FRP_TARBALL}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${INSTALL_DIR}"
mkdir -p "${HOME}/Library/LaunchAgents"

log "下载 ${FRP_URL}"
curl -fL --connect-timeout 10 --max-time 300 "${FRP_URL}" -o "${TMP_DIR}/${FRP_TARBALL}"

tar -xzf "${TMP_DIR}/${FRP_TARBALL}" -C "${TMP_DIR}"
FRP_SRC_DIR="${TMP_DIR}/frp_${VERSION_NO_V}_darwin_${FRP_ARCH}"
[[ -x "${FRP_SRC_DIR}/frpc" ]] || fail "解压后未找到 frpc：${FRP_SRC_DIR}/frpc"

install -m 0755 "${FRP_SRC_DIR}/frpc" "${INSTALL_DIR}/frpc"

cat > "${CONFIG_FILE}" <<EOF
serverAddr = "${VPS_ADDR}"
serverPort = ${FRP_SERVER_PORT}

auth.method = "token"
auth.token = "${FRP_TOKEN}"

log.to = "${LOG_FILE}"
log.level = "info"
log.maxDays = 3

[[proxies]]
name = "sunshine-tcp-47984"
type = "tcp"
localIP = "${SUNSHINE_LOCAL_IP}"
localPort = 47984
remotePort = 47984

[[proxies]]
name = "sunshine-tcp-47989"
type = "tcp"
localIP = "${SUNSHINE_LOCAL_IP}"
localPort = 47989
remotePort = 47989

[[proxies]]
name = "sunshine-tcp-48010"
type = "tcp"
localIP = "${SUNSHINE_LOCAL_IP}"
localPort = 48010
remotePort = 48010

[[proxies]]
name = "sunshine-udp-47998"
type = "udp"
localIP = "${SUNSHINE_LOCAL_IP}"
localPort = 47998
remotePort = 47998

[[proxies]]
name = "sunshine-udp-47999"
type = "udp"
localIP = "${SUNSHINE_LOCAL_IP}"
localPort = 47999
remotePort = 47999

[[proxies]]
name = "sunshine-udp-48000"
type = "udp"
localIP = "${SUNSHINE_LOCAL_IP}"
localPort = 48000
remotePort = 48000
EOF
chmod 600 "${CONFIG_FILE}"
touch "${LOG_FILE}"

cat > "${PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.sunandmoon.frpc</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_DIR}/frpc</string>
    <string>-c</string>
    <string>${CONFIG_FILE}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${INSTALL_DIR}</string>
  <key>StandardOutPath</key>
  <string>${BASE_DIR}/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${BASE_DIR}/launchd.err.log</string>
</dict>
</plist>
EOF

launchctl unload "${PLIST_FILE}" >/dev/null 2>&1 || true
launchctl load -w "${PLIST_FILE}"
launchctl kickstart -k "gui/$(id -u)/com.sunandmoon.frpc" >/dev/null 2>&1 || true

log "frpc 已安装并启动。"
log "配置文件：${CONFIG_FILE}"
log "日志文件：${LOG_FILE}"
log "LaunchAgent：${PLIST_FILE}"
log "本地 Sunshine 地址：${SUNSHINE_LOCAL_IP}"

printf '\n检查日志：\n'
printf 'tail -f %s\n' "${LOG_FILE}"
printf '\n重启 frpc：\n'
printf 'launchctl kickstart -k gui/$(id -u)/com.sunandmoon.frpc\n'
printf '\nMoonlight 外网手动添加：%s\n' "${VPS_ADDR}"
