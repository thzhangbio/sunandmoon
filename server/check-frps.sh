#!/usr/bin/env bash
set -Eeuo pipefail

printf '\n== frps service ==\n'
systemctl status frps --no-pager || true

printf '\n== listening ports ==\n'
if command -v ss >/dev/null 2>&1; then
  ss -lntup | grep -E '7000|47984|47989|48010|47998|47999|48000' || true
else
  netstat -lntup 2>/dev/null | grep -E '7000|47984|47989|48010|47998|47999|48000' || true
fi

printf '\n== frps log tail ==\n'
tail -n 80 /var/log/sunandmoon-frps.log 2>/dev/null || true

printf '\n== public ipv4 ==\n'
curl -fsS4 --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true
printf '\n'

printf '\nReminder: cloud security group must allow TCP 7000,47984,47989,48010 and UDP 47998,47999,48000.\n'
