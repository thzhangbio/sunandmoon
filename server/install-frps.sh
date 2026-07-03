#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="sunandmoon"
INSTALL_DIR="/opt/${APP_NAME}/frp"
CONFIG_DIR="/etc/${APP_NAME}"
CONFIG_FILE="${CONFIG_DIR}/frps.toml"
TOKEN_FILE="${CONFIG_DIR}/frp-token"
SERVICE_FILE="/etc/systemd/system/frps.service"
LOG_FILE="/var/log/${APP_NAME}-frps.log"

FRP_VERSION="${FRP_VERSION:-latest}"
FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"
FRP_TOKEN="${FRP_TOKEN:-}"

log() {
  printf '\033[1;32m[server]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2
}

fail() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "请用 sudo 运行：sudo bash server/install-frps.sh"
fi

need_cmd curl
need_cmd tar
need_cmd uname

ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64) FRP_ARCH="amd64" ;;
  aarch64|arm64) FRP_ARCH="arm64" ;;
  armv7l|armv7) FRP_ARCH="arm" ;;
  *) fail "暂不支持的服务器架构：${ARCH_RAW}" ;;
esac

if [[ "${FRP_VERSION}" == "latest" ]]; then
  log "获取 frp 最新版本号..."
  TAG="$(curl -fsSL --connect-timeout 10 --max-time 30 https://api.github.com/repos/fatedier/frp/releases/latest | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [[ -n "${TAG}" ]] || fail "无法获取 frp 最新版本号。可以手动指定：FRP_VERSION=0.xx.x sudo bash server/install-frps.sh"
  VERSION_NO_V="${TAG#v}"
else
  VERSION_NO_V="${FRP_VERSION#v}"
  TAG="v${VERSION_NO_V}"
fi

FRP_TARBALL="frp_${VERSION_NO_V}_linux_${FRP_ARCH}.tar.gz"
FRP_URL="https://github.com/fatedier/frp/releases/download/${TAG}/${FRP_TARBALL}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log "下载 ${FRP_URL}"
curl -fL --connect-timeout 10 --max-time 300 "${FRP_URL}" -o "${TMP_DIR}/${FRP_TARBALL}"

tar -xzf "${TMP_DIR}/${FRP_TARBALL}" -C "${TMP_DIR}"
FRP_SRC_DIR="${TMP_DIR}/frp_${VERSION_NO_V}_linux_${FRP_ARCH}"
[[ -x "${FRP_SRC_DIR}/frps" ]] || fail "解压后未找到 frps：${FRP_SRC_DIR}/frps"

install -d -m 0755 "${INSTALL_DIR}"
install -d -m 0755 "${CONFIG_DIR}"
install -m 0755 "${FRP_SRC_DIR}/frps" "${INSTALL_DIR}/frps"

if [[ -z "${FRP_TOKEN}" ]]; then
  if [[ -s "${TOKEN_FILE}" ]]; then
    FRP_TOKEN="$(cat "${TOKEN_FILE}")"
    log "复用已有 token：${TOKEN_FILE}"
  else
    if command -v openssl >/dev/null 2>&1; then
      FRP_TOKEN="$(openssl rand -hex 24)"
    else
      FRP_TOKEN="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48)"
    fi
    printf '%s\n' "${FRP_TOKEN}" > "${TOKEN_FILE}"
    chmod 600 "${TOKEN_FILE}"
    log "已生成新 token：${TOKEN_FILE}"
  fi
else
  printf '%s\n' "${FRP_TOKEN}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  log "已写入指定 token：${TOKEN_FILE}"
fi

cat > "${CONFIG_FILE}" <<EOF
bindPort = ${FRP_BIND_PORT}

auth.method = "token"
auth.token = "${FRP_TOKEN}"

log.to = "${LOG_FILE}"
log.level = "info"
log.maxDays = 3
EOF
chmod 600 "${CONFIG_FILE}"

touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=sunandmoon frp server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/frps -c ${CONFIG_FILE}
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable frps >/dev/null
systemctl restart frps

if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
  log "检测到 ufw 已启用，尝试放行端口..."
  ufw allow "${FRP_BIND_PORT}/tcp" || true
  ufw allow 47984/tcp || true
  ufw allow 47989/tcp || true
  ufw allow 48010/tcp || true
  ufw allow 47998/udp || true
  ufw allow 47999/udp || true
  ufw allow 48000/udp || true
fi

if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  log "检测到 firewalld 已启用，尝试放行端口..."
  firewall-cmd --permanent --add-port="${FRP_BIND_PORT}/tcp" || true
  firewall-cmd --permanent --add-port=47984/tcp || true
  firewall-cmd --permanent --add-port=47989/tcp || true
  firewall-cmd --permanent --add-port=48010/tcp || true
  firewall-cmd --permanent --add-port=47998/udp || true
  firewall-cmd --permanent --add-port=47999/udp || true
  firewall-cmd --permanent --add-port=48000/udp || true
  firewall-cmd --reload || true
fi

VPS_ADDR="$(curl -fsS4 --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"

log "frps 已安装并启动。"
log "服务状态：systemctl status frps --no-pager"
log "日志文件：${LOG_FILE}"
log "配置文件：${CONFIG_FILE}"
log "token 文件：${TOKEN_FILE}"

printf '\n==== Mac mini 端需要的信息 ====\n'
printf 'VPS_ADDR=%s\n' "${VPS_ADDR:-请填写你的 VPS 公网 IP}"
printf 'FRP_TOKEN=%s\n' "${FRP_TOKEN}"
printf '\nMac mini 上运行示例：\n'
printf 'VPS_ADDR="%s" FRP_TOKEN="%s" bash client/install-frpc-macos.sh\n' "${VPS_ADDR:-你的VPS公网IP}" "${FRP_TOKEN}"
printf '\n请确认 VPS 云厂商安全组已放行：TCP %s,47984,47989,48010；UDP 47998,47999,48000\n' "${FRP_BIND_PORT}"
