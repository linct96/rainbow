# rainbow

## 使用方式

```bash
bash <(curl -Ls https://raw.githubusercontent.com/linct96/rainbow/main/rainbow.sh)
```

首次执行后会安装为 `/usr/local/bin/rb`，后续直接运行：

```bash
rb
```

需要更新脚本时，在菜单中选择 `更新 rainbow`。

通过 rainbow 安装的程序和配置位于：

```text
~/rainbow/sing-box/
~/rainbow/xray/
```

对应的 systemd 服务为 `rainbow-sing-box` 和 `rainbow-xray`，不会覆盖其他方式安装的同名程序和服务。

## ACME TLS 证书

在主菜单选择 `TLS 证书管理`，输入根域名和 Cloudflare API Token。脚本会申请一张同时包含以下域名的 Let's Encrypt 证书：

```text
example.com
*.example.com
```

Cloudflare API Token 需要限定到目标 Zone，并包含以下权限：

```text
Zone / Zone / Read
Zone / DNS / Edit
```

证书和私钥保存在：

```text
~/rainbow/tls/cert.pem
~/rainbow/tls/key.pem
```

Token 保存在 `~/rainbow/acme/cf-token`，文件权限为 `0600`。`rainbow-acme.timer` 每天检查续期，只有证书发生变化时才会重启 sing-box。

TUIC、AnyTLS 使用的 A、AAAA 或 CNAME 记录应在 Cloudflare 中设置为 `DNS only`。

查看续期日志：

```bash
journalctl -u rainbow-acme.service
```
