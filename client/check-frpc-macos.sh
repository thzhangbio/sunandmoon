#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="${HOME}/.sunandmoon"
PLIST_FILE="${HOME}/Library/LaunchAgents/com.sunandmoon.frpc.plist"

printf '\n== LaunchAgent ==\n'
launchctl print "gui/$(id -u)/com.sunandmoon.frpc" 2>/dev/null || true

printf '\n== local files ==\n'
ls -lah "${BASE_DIR}" 2>/dev/null || true

printf '\n== frpc log tail ==\n'
tail -n 100 "${BASE_DIR}/frpc.log" 2>/dev/null || true

printf '\n== Sunshine local TCP ports ==\n'
for p in 47984 47989 48010; do
  printf '127.0.0.1:%s ... ' "$p"
  nc -vz 127.0.0.1 "$p" >/dev/null 2>&1 && printf 'ok\n' || printf 'not reachable\n'
done

printf '\n== frpc config path ==\n%s\n' "${BASE_DIR}/frpc.toml"
printf '== plist path ==\n%s\n' "${PLIST_FILE}"
