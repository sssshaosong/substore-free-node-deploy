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

## 每 6 小时如何保证执行

安装脚本会写入 systemd timer：

```text
/etc/systemd/system/free-node-sub-generate.timer
/etc/systemd/system/free-node-sub-generate.service
```

核心设置：

```ini
[Timer]
OnBootSec=2min
OnUnitActiveSec=6h
Persistent=true
AccuracySec=1min
RandomizedDelaySec=0
```

含义：

```text
OnBootSec=2min       开机 2 分钟后先跑一次
OnUnitActiveSec=6h   上次生成完成后，每 6 小时再跑一次
Persistent=true      VPS 关机/重启错过任务，开机后会补跑
AccuracySec=1min     时间误差控制在 1 分钟级别
RandomizedDelaySec=0 不随机延迟
```

生成服务用 `flock` 加锁：

```text
ExecStart=/usr/bin/flock -n /run/free-node-sub-generate.lock /opt/free-node-sub/generate.sh
```

也就是说，即使上一次任务还没结束，下一次不会并发乱跑。

## 如何保证每次拉取最新源

每次 systemd 触发 `generate.sh` 时，会先执行：

```text
从 GitHub raw 拉取最新 sources.txt
→ 校验里面必须有 https:// 源
→ 校验成功才覆盖本地 /opt/free-node-sub/sources.txt
→ 如果 GitHub 拉取失败，保留上一次可用 sources.txt
```

默认远程源列表地址：

```text
https://raw.githubusercontent.com/sssshaosong/substore-free-node-deploy/main/sources.txt
```

然后 `generator.py` 每次都会重新请求 `sources.txt` 里的每一个订阅源，不使用上次缓存。

## 如何保证文件不被坏结果覆盖

`generator.py` 已经改成原子写入：

```text
先生成到临时目录
确认 output_count >= 1
再一次性替换 v2ray.txt / uri.txt / clash.yaml / status.json
```

如果本次生成失败、拉源失败、解析不到节点、检测后 0 个节点：

```text
不会覆盖旧的可用订阅文件
只写入 /opt/free-node-sub/output/last_error.json
```

所以客户端拿到的始终是上一次成功生成的文件，不会因为某次 GitHub 抽风或免费源全挂而变成空文件。

## 输出文件

安装完成后会生成：

```text
/opt/free-node-sub/output/v2ray.txt
/opt/free-node-sub/output/uri.txt
/opt/free-node-sub/output/clash.yaml
/opt/free-node-sub/output/status.json
/opt/free-node-sub/output/last_error.json  # 只有失败时出现或更新
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

关闭每次从 GitHub 同步最新版 `sources.txt`，只用本机 `/opt/free-node-sub/sources.txt`：

```bash
sudo SYNC_SOURCES_FROM_GITHUB=0 bash install.sh
```

自定义远程源列表：

```bash
sudo REMOTE_SOURCES_URL=https://example.com/sources.txt bash install.sh
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

## 验证命令

查看订阅地址：

```bash
cd /opt/free-node-sub
./show-info.sh
```

完整健康检查：

```bash
cd /opt/free-node-sub
./health-check.sh
```

立即重新生成：

```bash
sudo systemctl start free-node-sub-generate.service
```

查看生成日志：

```bash
sudo journalctl -u free-node-sub-generate.service --no-pager -n 120
```

查看定时任务下次运行时间：

```bash
systemctl list-timers free-node-sub-generate.timer
```

查看定时器是否启用并运行：

```bash
systemctl is-enabled free-node-sub-generate.timer
systemctl is-active free-node-sub-generate.timer
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

1. 每次运行前同步最新版 `sources.txt`
2. 并发拉取所有源
3. 自动识别普通文本、base64 订阅、Clash YAML
4. 解析 `vmess`、`vless`、`trojan`、`ss` 等常见格式
5. 去重
6. 默认做 TCP 连接检测，移除明显连不上的节点
7. 如果结果有效，原子替换静态文件
8. 如果结果无效，保留上一次成功文件
9. systemd timer 每 6 小时自动运行一次

## 重要说明

- systemd 能保证定时触发和错过后补跑，但不能保证第三方免费源永远可访问。
- TCP 检测只判断 `server:port` 是否可连接，不等于完整代理测速。
- 免费节点本身质量不稳定，不能保证每个节点一直可用。
- 这个项目的目标是：自动聚合、去重、移除明显失效、生成稳定静态订阅文件。
- 不再使用 Sub-Store 动态订阅链路。
