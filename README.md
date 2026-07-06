# substore-free-node-deploy

VPS 上一键部署 Sub-Store + http-meta，把多个公开节点源自动聚合、测速、过滤失效节点，并输出 v2rayN / Clash.Meta / sing-box 订阅链接。

> 这个项目部署的是订阅处理器，不是代理服务器。它不会把你的 VPS 变成代理节点。

## 功能

- Docker 一键部署 `xream/sub-store:http-meta`
- 自动生成随机后端路径，降低后台被扫风险
- 自动读取 `sources.txt` 里的公开节点源
- 自动创建 `source-001`、`source-002` 等订阅源
- 自动创建组合订阅 `free-auto`
- 自动挂载 `operators/02_httpmeta_speed_filter.js` 测速过滤脚本
- 自动输出 v2rayN / Clash.Meta / sing-box 订阅地址
- 每 6 小时自动同步和生产一次 `free-auto`
- 支持 Cloudflare Tunnel / 本机监听 / 公网临时测试

## 一键安装

```bash
git clone https://github.com/sssshaosong/substore-free-node-deploy.git
cd substore-free-node-deploy
sudo bash install.sh
```

Cloudflare Tunnel 模式：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

安装完成后会输出类似：

```text
Sub-Store frontend: https://sub.example.com
Sub-Store backend : https://sub.example.com/随机后端路径
One-line UI URL   : https://sub.example.com?api=https://sub.example.com/随机后端路径

Ready subscription URLs:
v2rayN      : https://sub.example.com/share/col/free-auto/V2Ray?includeUnsupportedProxy=true
URI raw     : https://sub.example.com/share/col/free-auto/URI?includeUnsupportedProxy=true
Clash/Mihomo: https://sub.example.com/share/col/free-auto/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true
sing-box    : https://sub.example.com/share/col/free-auto/sing-box?includeUnsupportedProxy=true
```

关键点：

```text
/api 接口走随机后端路径： https://sub.example.com/随机后端路径/api/...
/share 订阅链接走根路径： https://sub.example.com/share/...
```

所以 v2rayN、Clash、sing-box 复制 `Ready subscription URLs` 里的链接，不要复制 `One-line UI URL`，也不要把随机后端路径加到 `/share` 前面。

## 常用参数

没有域名，临时测试：

```bash
sudo bash install.sh
```

没有域名，但不想暴露 3001 到公网，只监听本机：

```bash
sudo NO_PUBLIC_IP=1 bash install.sh
```

已有 Docker 镜像，不想重新拉取：

```bash
sudo SKIP_PULL=1 bash install.sh
```

已有同名容器，换容器名和端口：

```bash
sudo CONTAINER_NAME=sub-store2 PORT=3002 bash install.sh
```

不自动写入内置源和组合订阅：

```bash
sudo AUTO_BOOTSTRAP=0 bash install.sh
```

自定义组合订阅名：

```bash
sudo COLLECTION_NAME=my-free bash install.sh
```

## Cloudflare Tunnel

在 Cloudflare Tunnel 里给已有 tunnel 增加一个 Public Hostname：

```text
sub.example.com -> http://localhost:3001
```

然后执行：

```bash
sudo USE_TUNNEL=1 DOMAIN=sub.example.com bash install.sh
```

详细说明：

```text
docs/cloudflare-tunnel.md
```

## 使用方式

查看订阅地址：

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
v2rayN       -> 使用 /share/col/free-auto/V2Ray 链接
Clash/Mihomo -> 使用 /share/col/free-auto/Clash.Meta 链接
sing-box     -> 使用 /share/col/free-auto/sing-box 链接
```

详细客户端教程：

```text
docs/client-usage.md
```

## 每 6 小时自动检测

安装脚本会写入：

```yaml
SUB_STORE_BACKEND_SYNC_CRON: "0 */6 * * *"
SUB_STORE_PRODUCE_CRON: "0 */6 * * *,collection,free-auto"
```

## 修改筛选条件

测速过滤脚本在：

```text
operators/02_httpmeta_speed_filter.js
```

常改参数：

```js
const TIMEOUT = 5000;
const MAX_DELAY = 800;
const CONCURRENCY = 6;
```

## 安全建议

- 后端路径随机不等于强认证，建议再套 Cloudflare Access、Basic Auth 或仅允许自己的 IP。
- 免费节点很不稳定，不建议用于支付、银行、Stripe、Payoneer、Google 主账号等重要服务。
- 公开节点源可能包含脏节点、钓鱼节点或被滥用节点，只建议低风险测试。
