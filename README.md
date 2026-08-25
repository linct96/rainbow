# rainbow

## 使用方式

```bash
bash <(curl -Ls https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh)
```

仅完成初始化安装并注册 `rb` 命令，不进入交互菜单：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh) --install
```

首次执行后会安装为 `/usr/local/bin/rb`，后续直接运行：

```bash
rb
```

## sing-box CLI

```bash
rb sing-box list
rb sing-box add tuic
rb sing-box add anytls --port 443
rb sing-box add hysteria2 --address 1.2.3.4 --warp both
rb sing-box remove tuic
rb sing-box remove hysteria2 --yes
rb sing-box remove tuic anytls hysteria2 --yes
```

`--port` 省略时随机生成端口，`--address` 省略时自动检测公网 IPv4，
`--warp` 支持 `direct`、`both` 和 `warp`，默认为 `direct`。删除节点需要输入
`DELETE` 确认，自动化场景可使用 `--yes` 跳过确认。

脚本日志使用绿色 `[INFO]`、黄色 `[WARN]` 和红色 `[ERROR]` 标签。非交互输出不包含颜色，
可通过 `NO_COLOR=1` 强制关闭颜色。

## 证书 CLI

```bash
rb cert add --domain example.com --cfapitoken "Cloudflare_API_Token"
rb cert status
rb cert remove
rb cert remove --yes
```

`add` 会通过 Cloudflare DNS-01 同时申请 `example.com` 和 `*.example.com` 证书。
`--domain` 只接受根域名，`--cfapitoken` 不会输出到日志，但会出现在 Shell 历史和短暂的进程参数中。
`remove` 需要输入 `REMOVE` 确认，自动化场景可使用 `--yes` 跳过确认。移除 ACME
证书时，依赖该证书的节点和客户端信息也会一并删除。

首次执行会自动安装最新版 Xray、sing-box、wgcf，注册 WARP 账户并生成自签 TLS 证书。

通过 rainbow 安装的程序和配置位于：

```text
~/rainbow/sing-box/
~/rainbow/xray/
~/rainbow/cloudflared/
```

对应的 systemd 服务为 `rainbow-sing-box`、`rainbow-xray`，以及可选的 `rainbow-cloudflared-quick`、`rainbow-cloudflared-named`，不会覆盖其他方式安装的同名程序和服务。

## 卸载节点

主菜单中的 `卸载节点` 会列出当前 Rainbow 管理的节点。输入多个序号时可以使用空格或逗号分隔，例如：

```text
1 3 5
1,3,5
```

删除操作只匹配 `rainbow-*` 标签。同一协议的直出和 WARP 节点会一起删除；没有其他 WARP 节点时，对应的共享 WARP 出站也会移除。删除 ARGO 节点时会同时清理对应的 cloudflared 服务和状态文件，不会删除共享程序、证书或 WARP 账户。

主菜单的“编辑节点”可修改 Rainbow 管理节点的监听端口，修改前会检查端口占用并验证新配置。固定 ARGO 隧道修改后，还需将 Cloudflare Published application 的回源端口改为相同值。

## TLS 证书

主菜单会分别显示自签证书和 ACME 证书状态。自签证书会在初始化时生成，`证书管理` 只负责 ACME 证书的申请、重新配置和移除。

两类证书可以同时存在。搭建 TUIC、AnyTLS、Hysteria2 节点时，脚本会优先使用有效的 ACME 证书；未配置、无效或已过期时自动使用自签证书。

移除 ACME 证书时，依赖该证书的节点和客户端信息也会一并删除。

申请 ACME 证书时，输入根域名和 Cloudflare API Token。脚本会申请一张同时包含以下域名的 Let's Encrypt 证书：

```text
example.com
*.example.com
```

Cloudflare API Token 需要限定到目标 Zone，并包含以下权限：

```text
Zone / Zone / Read
Zone / DNS / Edit
```

证书和私钥分别保存在：

```text
~/rainbow/tls/self-signed/cert.pem
~/rainbow/tls/self-signed/key.pem
~/rainbow/tls/acme/cert.pem
~/rainbow/tls/acme/key.pem
```

Token 保存在 `~/rainbow/acme/cf-token`，文件权限为 `0600`。`rainbow-acme.timer` 每天检查续期，只有证书发生变化时才会重启 sing-box。

TUIC、AnyTLS、Hysteria2 使用的 A、AAAA 或 CNAME 记录应在 Cloudflare 中设置为 `DNS only`。

## VLESS + WebSocket + Cloudflare CDN

Xray 节点菜单支持创建 `VLESS + TLS + WebSocket + Cloudflare CDN` 节点。该类型强制使用有效的 ACME 证书，不会回退到自签证书；未配置证书时请先进入 `证书管理` 完成申请。

创建节点时输入域名前缀，直接回车默认使用 `cdn`。例如证书根域名为 `example.com`，默认生成的完整节点域名为：

```text
cdn.example.com
```

随后可以输入优选域名；留空时使用上述完整节点域名。优选域名只作为客户端连接地址，TLS SNI 和 WebSocket Host 始终使用完整节点域名。

可选端口仅限 Cloudflare 支持代理的 HTTPS 端口：

```text
443 2053 2083 2087 2096 8443
```

在 Cloudflare 中添加指向服务器公网 IP 的 A 记录，并开启小黄云：

```text
名称：cdn
代理状态：已代理
SSL/TLS 模式：Full (strict)
```

客户端连接端口与 Xray 回源监听端口保持一致。移除 ACME 证书时，对应的 WebSocket 节点也会一并移除。

查看续期日志：

```bash
journalctl -u rainbow-acme.service
```

创建 VLESS + WebSocket 节点时可选启用 VLESS ENC。默认关闭以保持客户端兼容性；启用后使用 Xray 生成的 ML-KEM-768 加密对，仅支持新版 Xray 内核客户端。

## VLESS + WebSocket + Cloudflare Argo 隧道

Xray 节点菜单使用一个入口创建 Cloudflare Tunnel 节点。Tunnel Token 留空时创建临时隧道；输入 Token 时创建固定隧道。两种节点名称均为 `{节点前缀}-ARGO`，WARP 节点追加 `-WARP`。

脚本会安装独立的 `cloudflared`，并创建仅监听 `127.0.0.1` 的 VLESS + WebSocket 入站。客户端固定连接 `443` 端口，可以另外输入优选域名作为连接地址。

Token 留空时注册 `rainbow-cloudflared-quick` 服务。TLS SNI 和 WebSocket Host 使用随机生成的 `*.trycloudflare.com` 域名。

Quick Tunnel 仅适合测试：没有 SLA，最多支持 200 个并发请求，服务重启后域名会变化。脚本会自动刷新服务器上的客户端文件，但已经导入客户端的旧分享链接需要重新导入。

查看隧道日志：

```bash
journalctl -u rainbow-cloudflared-quick.service
```

输入 Token 时注册 `rainbow-cloudflared-named` 服务，并复用证书管理中保存的根域名。例如根域名为 `example.com`，输入子域名前缀 `tunnel` 后使用：

```text
tunnel.example.com
```

脚本会显示需要在 Cloudflare Tunnel 的 `Published application` 中配置的内容：

```text
Hostname：tunnel.example.com
Service：http://127.0.0.1:<脚本生成的端口>
```

Token 保存在 `~/rainbow/cloudflared/named-token`，权限为 `0600`。客户端固定连接 `443` 端口；优选域名只作为连接地址，TLS SNI 和 WebSocket Host 始终使用固定隧道域名。

查看固定隧道日志：

```bash
journalctl -u rainbow-cloudflared-named.service
```
