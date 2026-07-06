# 订阅地址生成与客户端使用

本文说明部署完成后，如何从 Sub-Store 生成订阅地址，并导入 v2rayN、Clash Verge / Mihomo、sing-box 等客户端。

## 一、先确认你的访问地址

安装完成后执行：

```bash
cd /opt/substore-free-node
./show-info.sh
```

你会看到类似：

```text
Sub-Store frontend: https://sub.example.com
Sub-Store backend : https://sub.example.com/xxxxxxxxxxxxxxxxxxxxxxxx
One-line UI URL   : https://sub.example.com?api=https://sub.example.com/xxxxxxxxxxxxxxxxxxxxxxxx
```

打开最后一行 `One-line UI URL`。

如果你没有域名，可能是：

```text
http://你的VPS_IP:3001?api=http://你的VPS_IP:3001/xxxxxxxxxxxxxxxxxxxxxxxx
```

如果你用了 Tunnel 或 `NO_PUBLIC_IP=1`，不要用 VPS IP 访问，应该用域名或本地转发后的地址。

## 二、在 Sub-Store 里创建组合订阅

进入 Sub-Store 网页后：

```text
组合订阅 / Collections
→ 新建
→ 名称，例如：free-auto
→ 添加订阅源
→ 把 /opt/substore-free-node/sources.txt 里的链接逐个添加进去
```

查看源列表：

```bash
cat /opt/substore-free-node/sources.txt
```

然后添加脚本处理：

```text
节点操作 / 脚本处理 / Operator
→ 新建或粘贴脚本
→ 使用 /opt/substore-free-node/operators/02_httpmeta_speed_filter.js
→ 保存
→ 预览
```

查看测速脚本：

```bash
cat /opt/substore-free-node/operators/02_httpmeta_speed_filter.js
```

预览能看到节点后，再点分享、导出或复制订阅链接。

> 不建议自己手写 Sub-Store 的 API 路径。不同版本 UI 生成的分享链接可能略有不同，最稳妥是直接在 Sub-Store 页面点“分享/复制链接”。

## 三、v2rayN 使用方式

给 v2rayN 用时，在 Sub-Store 导出类型选择：

```text
V2Ray / V2RayN / URI / Base64
```

不要选择 Clash.Meta，也不要选择 sing-box。

然后打开 v2rayN：

```text
订阅分组
→ 订阅分组设置
→ 添加
```

填写：

```text
备注：free-auto
地址：粘贴 Sub-Store 复制出来的 v2rayN / V2Ray 订阅链接
```

保存后：

```text
订阅分组
→ 更新全部订阅，或者更新当前订阅
```

更新成功后：

```text
右键节点
→ 测试服务器延迟 / 测试真实连接
→ 选择可用节点
→ 设为活动服务器
→ 系统代理
→ 自动配置系统代理
```

如果 v2rayN 更新不到节点，通常是下面几种情况：

```text
1. 你复制的是 Clash.Meta 链接，不是 V2Ray/v2rayN 链接
2. Sub-Store 后端地址没有配置对
3. Cloudflare Tunnel 没有把域名转发到 localhost:3001
4. 组合订阅预览本身就是空的
5. 测速脚本筛选太严格，MAX_DELAY 太低
```

可以先在 Sub-Store 里临时关闭测速脚本，确认原始节点能正常输出。

## 四、Clash Verge / Mihomo 使用方式

给 Clash Verge、Clash Verge Rev、Mihomo Party、OpenClash 等使用时，在 Sub-Store 导出类型选择：

```text
Clash.Meta / Mihomo
```

然后在客户端里添加远程配置。

以 Clash Verge / Clash Verge Rev 为例：

```text
Profiles / 配置
→ New / 新建
→ Remote / URL / 远程配置
→ 粘贴 Sub-Store 复制出来的 Clash.Meta 订阅链接
→ 保存
→ Update / 更新
→ 选中该配置
```

如果客户端需要填写名称：

```text
Name: free-auto
URL : 你的 Clash.Meta 订阅链接
```

OpenClash 一般是：

```text
配置订阅
→ 添加
→ 名称：free-auto
→ 地址：Clash.Meta 订阅链接
→ 保存并更新
```

## 五、Clash 配置文件里怎么写

大多数 Clash 客户端不需要你手动把节点写进 `config.yaml`，直接添加远程订阅 URL 更稳。

如果你的客户端必须用文件方式，可以在 Sub-Store 里选择 Clash.Meta 导出，然后把生成内容保存成：

```text
config.yaml
```

再导入客户端。

但不建议长期手动保存文件，因为手动文件不会自动跟着 6 小时定时更新。推荐使用远程订阅 URL。

## 六、sing-box 使用方式

给 sing-box / SFI / SFA / NekoBox sing-box 内核使用时，在 Sub-Store 导出类型选择：

```text
sing-box
```

然后在客户端里添加远程配置或订阅 URL。

不同 sing-box 客户端界面不一样，核心原则是：

```text
v2rayN       → 选择 V2Ray/v2rayN 类型链接
Clash/Mihomo → 选择 Clash.Meta/Mihomo 类型链接
sing-box     → 选择 sing-box 类型链接
```

## 七、推荐命名

可以创建多个导出链接：

```text
free-auto-v2rayn      → 给 v2rayN 使用
free-auto-clash       → 给 Clash.Meta / Mihomo 使用
free-auto-singbox     → 给 sing-box 使用
```

这样不同客户端互不影响，出问题时也方便排查。

## 八、排错命令

查看 Sub-Store 是否运行：

```bash
docker ps | grep sub-store
```

查看日志：

```bash
cd /opt/substore-free-node
docker compose logs -f --tail=100
```

检查端口监听：

```bash
ss -lntp | grep 3001
```

Cloudflare Tunnel 模式应该看到：

```text
127.0.0.1:3001
```

如果看到：

```text
0.0.0.0:3001
```

说明当前是公网监听模式，不是本机隐藏模式。

检查 tunnel 配置：

```bash
sudo cat /etc/cloudflared/config.yml
```

应包含类似：

```yaml
ingress:
  - hostname: sub.example.com
    service: http://localhost:3001
  - service: http_status:404
```

重启 tunnel：

```bash
sudo systemctl restart cloudflared
```
