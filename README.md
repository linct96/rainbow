# rainbow

## 使用方式

```bash
bash <(curl -Ls https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh)
```

首次执行后会安装为 `/usr/local/bin/rb`，后续直接运行：

```bash
rb
```

首次执行会自动安装最新版 Xray、sing-box、wgcf，注册 WARP 账户并生成自签 TLS 证书。WARP 注册会自动接受 [Cloudflare 服务条款](https://www.cloudflare.com/application/terms/)。主菜单中的 `一键初始化` 会先卸载 Rainbow 管理的全部数据，再重新执行上述初始化。

需要更新脚本时，在菜单中选择 `更新 rainbow`。

通过 rainbow 安装的程序和配置位于：

```text
~/rainbow/sing-box/
~/rainbow/xray/
```

对应的 systemd 服务为 `rainbow-sing-box` 和 `rainbow-xray`，不会覆盖其他方式安装的同名程序和服务。

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

查看续期日志：

```bash
journalctl -u rainbow-acme.service
```
