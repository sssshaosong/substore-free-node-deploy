# Cloudflare Tunnel 配置

新版本只提供静态文件服务，默认端口是 `8088`。

## 推荐方式

安装时：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

Cloudflare Zero Trust / Tunnel 里添加 Public Hostname：

```text
sub.example.com -> http://localhost:8088
```

然后访问：

```text
https://sub.example.com/v2ray.txt
https://sub.example.com/uri.txt
https://sub.example.com/clash.yaml
https://sub.example.com/status.json
```

## 检查服务

```bash
systemctl status free-node-sub-server.service --no-pager
systemctl list-timers | grep free-node-sub
curl -I http://127.0.0.1:8088/v2ray.txt
```

## 重启服务

```bash
sudo systemctl restart free-node-sub-server.service
sudo systemctl start free-node-sub-generate.service
```

## 注意

`USE_TUNNEL=1` 时，静态服务只监听：

```text
127.0.0.1:8088
```

不会暴露公网端口。公网访问由 Cloudflare Tunnel 转发。