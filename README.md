# substore-free-node-deploy

这是一个给 VPS 用的 Sub-Store + http-meta 一键部署模板，适合把多个公开订阅源聚合到一起，然后通过脚本测速、过滤失效节点、重命名，最后输出给 v2rayN / Clash / sing-box 等客户端。

> 注意：这个项目部署的是订阅处理器，不是代理服务器。它不会把你的 VPS 变成节点。

## 功能

- Docker 一键部署 `xream/sub-store:http-meta`
- 自动生成随机后端路径，降低后台被扫风险
- 内置公开节点源列表：`sources.txt`
- 内置两个 Sub-Store 脚本：
  - `01_fetch_today_clean.js`：额外拉取当天 free-nodes 订阅并清理名字
  - `02_httpmeta_speed_filter.js`：用 http-meta 真实走代理测速，过滤延迟过高/不可用节点
- 自动把 `sources.txt` 里的节点源写入 Sub-Store
- 自动创建组合订阅 `free-auto`
- 自动把测速过滤脚本挂到组合订阅上
- 自动输出 v2rayN / Clash.Meta / sing-box 可用订阅地址
- 内置 Sub-Store 后台 cron 环境变量：每 6 小时触发一次同步和生产任务
- 安装脚本是幂等设计：Docker、Docker Compose、curl 已存在时会跳过安装，不会重复安装，也不会停止其他 Docker 容器
- 支持域名模式、Cloudflare Tunnel 模式、无域名跳过模式

## 一键安装

```bash
git clone https://github.com/sssshaosong/substore-free-node-deploy.git
cd substore-free-node-deploy
sudo bash install.sh
```

安装完成后会直接输出：

```text
Ready subscription URLs:
v2rayN      : https://sub.example.com/后端路径/share/col/free-auto/V2Ray?includeUnsupportedProxy=true
URI raw     : https://sub.example.com/后端路径/share/col/free-auto/URI?includeUnsupportedProxy=true
Clash/Mihomo: https://sub.example.com/后端路径/share/col/free-auto/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true
sing-box    : https://sub.example.com/后端路径/share/col/free-auto/sing-box?includeUnsupportedProxy=true
```

你复制对应客户端的链接即可，不需要再手动添加 sources，也不需要手动粘贴脚本。v2rayN 优先用 `V2Ray` 这个链接，不要用旧版里的 `V2Ray%20URI`。

## 常用安装参数

没有域名，临时测试：

```bash
sudo bash install.sh
```

没有域名，但不想暴露 3001 到公网，只监听本机：

```bash
sudo NO_PUBLIC_IP=1 bash install.sh
```

已有 Cloudflare Tunnel，推荐这样装：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

如果你的 VPS 上 Docker 镜像已经存在，不想每次拉取镜像：

```bash
sudo SKIP_PULL=1 bash install.sh
```

如果已有同名容器 `sub-store` 被别的项目占用，可以换容器名：

```bash
sudo CONTAINER_NAME=sub-store2 PORT=3002 bash install.sh
```

如果你不想自动写入内置源和组合订阅：

```bash
sudo AUTO_BOOTSTRAP=0 bash install.sh
```

自定义组合订阅名：

```bash
sudo COLLECTION_NAME=my-free bash install.sh
```

## 隐藏 IP / 域名 / Tunnel 模式

已有 Cloudflare Tunnel 时，在 Cloudflare Tunnel 里给已有 tunnel 增加一个 Public Hostname：

```text
sub.example.com -> http://localhost:3001
```

然后执行：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

详细步骤看这里：

```text
docs/cloudflare-tunnel.md
```

辅助脚本：

```bash
DOMAIN=sub.example.com TUNNEL_NAME=你的Tunnel名称 bash scripts/cloudflare-tunnel-route.sh
```

这个辅助脚本只帮你创建 DNS route 并输出 ingress 配置示例，不会自动改你现有 cloudflared 配置，避免影响已有 tunnel。

## 已安装环境下的行为

如果你的 VPS 已经有完整环境：

```text
Docker 已安装
Docker daemon 已运行
Docker Compose 已安装
curl 已安装
```

脚本会直接进入后面的部署流程：

```text
跳过 Docker 安装
跳过 Docker Compose 安装
复制 sources.txt 和 operators 脚本
保留已有 data 数据目录
保留已有 BACKEND_PATH 后端路径
启动/更新 Sub-Store
自动写入内置源和 free-auto 组合订阅
输出 v2rayN / Clash.Meta / sing-box 订阅地址
```

它不会清空 `/opt/substore-free-node/data`，也不会停止其他 Docker 容器。

## 使用方式

安装后查看订阅地址：

```bash
cd /opt/substore-free-node
./show-info.sh
```

重新写入/更新内置源和组合订阅：

```bash
cd /opt/substore-free-node
./scripts/bootstrap-substore.sh
```

本机测试订阅端点：

```bash
cd /opt/substore-free-node
./scripts/test-subscriptions.sh
```

更新容器和配置：

```bash
cd /opt/substore-free-node
./update.sh
```

查看日志：

```bash
cd /opt/substore-free-node
docker compose logs -f --tail=100
```

## 客户端选择

```text
v2rayN       -> 使用 show-info.sh 输出的 v2rayN 链接，也就是 /V2Ray
Clash/Mihomo -> 使用 show-info.sh 输出的 Clash/Mihomo 链接
sing-box     -> 使用 show-info.sh 输出的 sing-box 链接
```

更详细的客户端导入教程：

```text
docs/client-usage.md
```

## 每 6 小时自动检测说明

安装脚本会在 `/opt/substore-free-node/docker-compose.yml` 里写入：

```yaml
SUB_STORE_BACKEND_SYNC_CRON: "0 */6 * * *"
SUB_STORE_PRODUCE_CRON: "0 */6 * * *,collection,free-auto"
```

其中 `free-auto` 会随 `COLLECTION_NAME` 自动变化。

## 修改筛选条件

测速过滤脚本在：

```text
operators/02_httpmeta_speed_filter.js
```

常改的几个参数：

```js
const TIMEOUT = 5000;
const MAX_DELAY = 800;
const CONCURRENCY = 6;
```

- `TIMEOUT`：单个节点测速超时时间，单位毫秒。
- `MAX_DELAY`：只保留小于等于该延迟的节点。
- `CONCURRENCY`：并发测速数量，太高可能压垮 VPS 或导致测速不准。

## 安全建议

- 后端路径已经随机生成，但不等于强认证。公网使用建议再套 Nginx Basic Auth、Cloudflare Access 或只允许自己的 IP 访问。
- 免费节点很不稳定，不建议用来登录支付、银行、Stripe、Payoneer、Google 主账号等重要服务。
- 公开节点源可能包含脏节点、钓鱼节点或被滥用节点，建议只用于低风险测试。
