# rainbow

## 使用方式

```bash
bash <(curl -Ls https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh)
```

首次执行后会安装为 `/usr/local/bin/rb`，后续直接运行：

```bash
rb
```

主菜单可设置节点名称前缀，默认使用服务器主机名。客户端节点名称格式为
`{前缀名称}-Rainbow-{协议}`，例如 `vps01-Rainbow-XHTTP`；WARP 节点会额外追加
`-WARP`。

首次执行会自动安装最新版 Xray、sing-box、wgcf，注册 WARP 账户并生成自签 TLS 证书。WARP 注册会自动接受 [Cloudflare 服务条款](https://www.cloudflare.com/application/terms/)。主菜单中的 `一键初始化` 会先卸载 Rainbow 管理的全部数据，再重新执行上述初始化。

通过 rainbow 安装的程序和配置位于：

```text
~/rainbow/sing-box/
~/rainbow/xray/
~/rainbow/cloudflared/
```

对应的 systemd 服务为 `rainbow-sing-box`、`rainbow-xray` 和可选的 `rainbow-cloudflared-quick`，不会覆盖其他方式安装的同名程序和服务。

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

## VLESS + WebSocket + Cloudflare 临时隧道

Xray 节点菜单支持创建无需域名、证书和 Cloudflare Token 的临时隧道节点。脚本会安装独立的 `cloudflared`，创建仅监听 `127.0.0.1` 的 VLESS + WebSocket 入站，并注册 `rainbow-cloudflared-quick` 服务。

客户端固定连接 `443` 端口。可以输入优选域名作为连接地址；留空时直接使用随机生成的 `*.trycloudflare.com` 域名。TLS SNI 和 WebSocket Host 始终使用该临时隧道域名。

Quick Tunnel 仅适合测试：没有 SLA，最多支持 200 个并发请求，服务重启后域名会变化。脚本会自动刷新服务器上的客户端文件，但已经导入客户端的旧分享链接需要重新导入。

查看隧道日志：

```bash
journalctl -u rainbow-cloudflared-quick.service
```
