# Cloudflare Tunnel / 域名隐藏 IP 配置

这个项目可以不绑定域名，直接用 `http://VPS_IP:3001` 访问；也可以用域名、Nginx、Cloudflare Tunnel 隐藏 VPS IP。

最推荐的方式：

```text
Sub-Store Docker 只监听 127.0.0.1:3001
        ↓
cloudflared Tunnel
        ↓
https://sub.example.com
```

这样外网不需要开放 3001 端口，Sub-Store 只给本机的 cloudflared 访问。

## 方案一：没有域名，跳过域名配置

直接安装：

```bash
sudo bash install.sh
```

这种方式会默认监听公网：

```text
0.0.0.0:3001
```

适合临时测试，不建议长期裸奔。

如果你没有域名，但也不想暴露公网端口，可以只监听本机：

```bash
sudo NO_PUBLIC_IP=1 bash install.sh
```

这样只能在 VPS 本机访问：

```text
http://127.0.0.1:3001
```

后续你再接 Nginx、SSH 端口转发、Cloudflare Tunnel 都可以。

## 方案二：已有 Cloudflare Tunnel，给这个项目增加一个路由

可以。一个 VPS 上已经有一个 cloudflared tunnel 时，通常可以继续在同一个 tunnel 里增加一个 Public Hostname / ingress 规则，把新的子域名转发到本机的 `http://localhost:3001`。

### Cloudflare 网页面板方式

进入：

```text
Cloudflare Zero Trust
→ Networks
→ Tunnels
→ 选择你已经在用的那个 tunnel
→ Public Hostnames
→ Add a public hostname
```

填写：

```text
Subdomain: sub
Domain: example.com
Type: HTTP
URL: localhost:3001
```

保存后，在 VPS 上用本地监听方式安装：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

安装完成后，访问：

```text
https://sub.example.com?api=https://sub.example.com/随机后端路径
```

### CLI 方式

先查看已有 tunnel：

```bash
cloudflared tunnel list
```

给现有 tunnel 增加 DNS 路由：

```bash
cloudflared tunnel route dns <你的Tunnel名称或UUID> sub.example.com
```

然后编辑 cloudflared 配置，一般是：

```bash
sudo nano /etc/cloudflared/config.yml
```

在 `ingress:` 下面增加一条，注意要放在最后的 `http_status:404` 前面：

```yaml
ingress:
  - hostname: old.example.com
    service: http://localhost:8080

  - hostname: sub.example.com
    service: http://localhost:3001

  - service: http_status:404
```

重启 cloudflared：

```bash
sudo systemctl restart cloudflared
```

然后安装本项目：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

也可以用项目里的辅助脚本创建 DNS route：

```bash
DOMAIN=sub.example.com TUNNEL_NAME=你的Tunnel名称 bash scripts/cloudflare-tunnel-route.sh
```

这个辅助脚本只负责创建 DNS route 和输出 ingress 配置示例，不会自动改你现有的 cloudflared 配置，避免误伤你已经在跑的 tunnel。

## 方案三：普通域名 + Nginx 反代

先让 Sub-Store 只监听本机：

```bash
sudo NO_PUBLIC_IP=1 DOMAIN=sub.example.com bash install.sh
```

Nginx 反代示例：

```nginx
server {
    listen 80;
    server_name sub.example.com;

    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

如果域名走 Cloudflare 橙云代理，建议只开放 80/443，并用防火墙限制源站只接受 Cloudflare IP 或直接改用 Cloudflare Tunnel。

## WARP 出口 IP 说明

有些 VPS 开了 WARP 后，访问外网时显示的出口 IP 会变成 WARP IP，不一定是 VPS 原始 IP。

这会影响两件事：

1. `show-info.sh` 里通过 `api.ipify.org` 获取到的 IP 可能是 WARP 出口 IP，不适合作为面板访问地址。
2. Sub-Store 测速免费节点时，测试请求可能从 WARP 出口发出，测出来的是“VPS + WARP 环境下”的可用性，不一定等于你本地电脑直连的体验。

所以如果你用了 WARP，更建议使用：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

让访问地址固定为域名，不依赖脚本自动识别 IP。

## 推荐防火墙策略

Cloudflare Tunnel 模式下，Sub-Store 只监听本机：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

这时公网不需要开放 3001。可以只保留 SSH、必要的 80/443，甚至 80/443 也可以不开放给本项目。

检查监听：

```bash
ss -lntp | grep 3001
```

你应该看到类似：

```text
127.0.0.1:3001
```

而不是：

```text
0.0.0.0:3001
```
