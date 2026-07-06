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
- 内置 Sub-Store 后台 cron 环境变量：每 6 小时触发一次生产/同步任务
- 安装脚本是幂等设计：Docker、Docker Compose、curl 已存在时会跳过安装，不会重复安装，也不会停止其他 Docker 容器
- 支持域名模式、Cloudflare Tunnel 模式、无域名跳过模式

## 一键安装

```bash
git clone https://github.com/sssshaosong/substore-free-node-deploy.git
cd substore-free-node-deploy
sudo bash install.sh
```

如果你是下载 zip 包，也可以这样：

```bash
unzip substore-free-node-deploy.zip
cd substore-free-node-deploy
sudo bash install.sh
```

可选参数：

```bash
sudo PORT=3001 BIND_IP=0.0.0.0 bash install.sh
```

如果你的 VPS 上 Docker 镜像已经存在，不想每次拉取镜像：

```bash
sudo SKIP_PULL=1 bash install.sh
```

如果已有同名容器 `sub-store` 被别的项目占用，可以换容器名：

```bash
sudo CONTAINER_NAME=sub-store2 PORT=3002 bash install.sh
```

## 隐藏 IP / 域名 / Tunnel 模式

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

然后在 Cloudflare Tunnel 里给已有 tunnel 增加一个 Public Hostname：

```text
sub.example.com -> http://localhost:3001
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

安装完会输出：

```text
Sub-Store frontend: http://你的IP:3001
Sub-Store backend : http://你的IP:3001/随机后端路径
One-line UI URL   : http://你的IP:3001?api=http://你的IP:3001/随机后端路径
```

如果你传了 `DOMAIN=sub.example.com`，输出会变成：

```text
Sub-Store frontend: https://sub.example.com
Sub-Store backend : https://sub.example.com/随机后端路径
One-line UI URL   : https://sub.example.com?api=https://sub.example.com/随机后端路径
```

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
执行 docker compose up -d 更新/启动当前项目
```

它不会清空 `/opt/substore-free-node/data`，也不会停止其他 Docker 容器。

## 使用步骤

1. 打开安装脚本输出的 `One-line UI URL`。
2. 在 Sub-Store 后端设置里确认后端已连接。
3. 新建单条订阅或组合订阅，把 `sources.txt` 里的 URL 添加进去。
4. 在组合订阅的节点操作里添加脚本处理，把 `operators/02_httpmeta_speed_filter.js` 粘贴进去。
5. 预览时会自动测速，保留 `MAX_DELAY` 以下的节点，默认是 800ms。
6. 分享/导出订阅时，v2rayN 建议选择 V2Ray / v2rayN 类型；Clash Verge / Mihomo 选择 Clash.Meta 类型。

更详细的客户端导入教程看这里：

```text
docs/client-usage.md
```

快速判断：

```text
v2rayN       -> 复制 V2Ray / v2rayN / URI / Base64 类型链接
Clash/Mihomo -> 复制 Clash.Meta / Mihomo 类型链接
sing-box     -> 复制 sing-box 类型链接
```

查看源列表：

```bash
cat /opt/substore-free-node/sources.txt
```

查看测速脚本：

```bash
cat /opt/substore-free-node/operators/02_httpmeta_speed_filter.js
```

## 每 6 小时自动检测说明

安装脚本会在 `/opt/substore-free-node/docker-compose.yml` 里写入：

```yaml
SUB_STORE_BACKEND_SYNC_CRON: "0 */6 * * *"
SUB_STORE_PRODUCE_CRON: "0 */6 * * *"
```

Sub-Store 的定时任务只会对已配置好的订阅/产物生效。也就是说：第一次仍然需要你在网页里把源和脚本建好，后续它才会按 6 小时周期预生成/同步。

## 常用命令

```bash
cd /opt/substore-free-node
./show-info.sh
./update.sh
docker compose logs -f --tail=100
./uninstall.sh
```

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
