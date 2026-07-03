# sunandmoon

Sunshine / Moonlight 公网中转方案。

目标：当家里/学校路由器的公网入站、IPv6 直连、Tailscale 都不方便时，用一台公网 VPS 做中转。

```text
Moonlight 客户端
      ↓
连接 VPS 公网 IP
      ↓
VPS 上的 frps
      ↓
Mac mini 上的 frpc 主动连出
      ↓
Mac mini 上的 Sunshine
```

## 端口

本方案默认转发 Sunshine / Moonlight 的核心端口：

```text
TCP: 47984, 47989, 48010
UDP: 47998, 47999, 48000
```

默认不转发 `47990`，因为它是 Sunshine Web 后台端口，不建议暴露到公网。

---

## 1. VPS 服务器安装 frps

在 VPS 上：

```bash
git clone https://github.com/thzhangbio/sunandmoon.git
cd sunandmoon
sudo bash server/install-frps.sh
```

安装完成后，脚本会输出：

```text
VPS_ADDR
FRP_TOKEN
```

也可以随时查看 token：

```bash
sudo cat /etc/sunandmoon/frp-token
```

检查服务状态：

```bash
sudo systemctl status frps --no-pager
sudo tail -f /var/log/sunandmoon-frps.log
```

### VPS 安全组 / 防火墙

除了服务器系统防火墙，云厂商安全组也必须放行：

```text
TCP: 7000, 47984, 47989, 48010
UDP: 47998, 47999, 48000
```

`7000/tcp` 是 Mac mini 的 frpc 连接 VPS 的控制端口。

---

## 2. Mac mini 安装 frpc

在 Mac mini 上：

```bash
git clone https://github.com/thzhangbio/sunandmoon.git
cd sunandmoon
VPS_ADDR="你的VPS公网IP" FRP_TOKEN="服务器输出的token" bash client/install-frpc-macos.sh
```

例如：

```bash
VPS_ADDR="1.2.3.4" FRP_TOKEN="xxxxxxxx" bash client/install-frpc-macos.sh
```

查看 Mac 端日志：

```bash
tail -f ~/.sunandmoon/frpc.log
```

重启 Mac 端 frpc：

```bash
launchctl kickstart -k gui/$(id -u)/com.sunandmoon.frpc
```

停止 Mac 端 frpc：

```bash
launchctl unload ~/Library/LaunchAgents/com.sunandmoon.frpc.plist
```

---

## 3. Sunshine 设置

Sunshine → Network 建议：

```text
UPnP：关闭
IP 地址族：IPv4
绑定地址：留空
端口：47989
外部 IP：填写 VPS 公网 IP
允许的 Web UI 访问来源：仅局域网
```

保存后重启 Sunshine。

---

## 4. Moonlight 连接

外网设备上打开 Moonlight，手动添加：

```text
VPS 公网 IP
```

不要加 `https://`，不要加端口。

如果出现 PIN，回到 Mac mini 本机的 Sunshine 后台输入 PIN。

---

## 5. 排查

VPS 上看端口：

```bash
sudo ss -lntup | grep -E '7000|47984|47989|48010|47998|47999|48000'
```

VPS 上看 frps 日志：

```bash
sudo tail -f /var/log/sunandmoon-frps.log
```

Mac mini 上看 frpc 日志：

```bash
tail -f ~/.sunandmoon/frpc.log
```

Mac mini 上检查 Sunshine 本地端口：

```bash
nc -vz 127.0.0.1 47984
nc -vz 127.0.0.1 47989
nc -vz 127.0.0.1 48010
```

UDP 无法用普通 `nc -vz` 可靠判断，优先看 frpc/frps 日志和 Moonlight 实测。

---

## 6. 更新

服务器：

```bash
cd sunandmoon
git pull
sudo bash server/install-frps.sh
```

Mac mini：

```bash
cd sunandmoon
git pull
VPS_ADDR="你的VPS公网IP" FRP_TOKEN="服务器输出的token" bash client/install-frpc-macos.sh
```
