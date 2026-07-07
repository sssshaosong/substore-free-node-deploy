# substore-free-node-deploy

这是重新推翻后的版本：不再使用 Sub-Store，不再让访问订阅时动态处理。

现在项目只做一件事：

```text
VPS 定时拉取公开节点源
→ 解析节点
→ 去重
→ TCP 连通性检测，移除明显失效节点
→ 每 6 小时生成静态订阅文件
→ 用固定地址提供 v2ray.txt / clash.yaml / uri.txt
```

访问订阅时只是下载已经生成好的静态文件，不会现场测速、不会现场拉 GitHub 源、不会让客户端等待后端处理。

## 输出文件

安装完成后会生成：

```text
/opt/free-node-sub/output/v2ray.txt
/opt/free-node-sub/output/uri.txt
/opt/free-node-sub/output/clash.yaml
/opt/free-node-sub/output/status.json
```

对应访问地址：

```text
https://你的域名/v2ray.txt
https://你的域名/uri.txt
https://你的域名/clash.yaml
https://你的域名/status.json
```

没有域名时会是：

```text
http://你的VPS_IP:8088/v2ray.txt
http://你的VPS_IP:8088/clash.yaml
```

## 一键安装

普通公网测试：

```bash
git clone https://github.com/sssshaosong/substore-free-node-deploy.git
cd substore-free-node-deploy
sudo bash install.sh
```

Cloudflare Tunnel 模式，推荐：

```bash
git clone https://github.com/sssshaosong/substore-free-node-deploy.git
cd substore-free-node-deploy
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

Tunnel 里添加：

```text
sub.example.com -> http://localhost:8088
```

这样 VPS 不需要暴露公网 8088。

## 常用参数

只监听本机，不暴露公网端口：

```bash
sudo NO_PUBLIC_IP=1 bash install.sh
```

跳过 TCP 连通性检测，只做解析、去重、生成：

```bash
sudo CONNECT_CHECK=0 bash install.sh
```

修改端口：

```bash
sudo STATIC_PORT=8090 bash install.sh
```

限制输出节点数量：

```bash
sudo MAX_NODES=300 bash install.sh
```

停止旧的 Sub-Store 容器：

```bash
sudo REMOVE_OLD_SUBSTORE=1 bash install.sh
```

## 使用命令

查看订阅地址：

```bash
cd /opt/free-node-sub
./show-info.sh
```

立即重新生成：

```bash
sudo systemctl start free-node-sub-generate.service
```

查看生成日志：

```bash
sudo journalctl -u free-node-sub-generate.service --no-pager -n 120
```

查看定时任务：

```bash
systemctl list-timers | grep free-node-sub
```

查看静态服务：

```bash
systemctl status free-node-sub-server.service --no-pager
```

本机测试输出：

```bash
curl -I http://127.0.0.1:8088/v2ray.txt
curl http://127.0.0.1:8088/status.json
```

## 文件说明

```text
generator.py    核心生成器，纯 Python
sources.txt     节点源列表
install.sh      VPS 一键安装脚本
```

## 生成逻辑

1. 读取 `sources.txt`
2. 并发拉取所有源
3. 自动识别普通文本、base64 订阅、Clash YAML
4. 解析 `vmess`、`vless`、`trojan`、`ss` 等常见格式
5. 去重
6. 默认做 TCP 连接检测，移除明显连不上的节点
7. 输出静态文件
8. systemd timer 每 6 小时自动运行一次

## 重要说明

- TCP 检测只判断 `server:port` 是否可连接，不等于完整代理测速。
- 免费节点本身质量不稳定，不能保证一直可用。
- 这个项目的目标是：自动聚合、去重、移除明显失效、生成稳定静态订阅文件。
- 不再使用 Sub-Store 动态订阅链路。
