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
