# 订阅地址与客户端使用

现在安装脚本会自动写入内置节点源、自动创建组合订阅、自动挂载测速脚本。正常情况下你不需要再手动添加 `sources.txt`，也不需要手动粘贴 operator 脚本。

## 一、查看现成订阅地址

安装完成后执行：

```bash
cd /opt/substore-free-node
./show-info.sh
```

你会看到类似：

```text
Ready subscription URLs:
v2rayN      : https://sub.example.com/后端路径/share/col/free-auto/V2Ray%20URI?includeUnsupportedProxy=true
Clash/Mihomo: https://sub.example.com/后端路径/share/col/free-auto/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true
sing-box    : https://sub.example.com/后端路径/share/col/free-auto/sing-box?includeUnsupportedProxy=true
```

直接复制对应客户端的链接。

注意：订阅地址必须包含随机后端路径，也就是：

```text
https://sub.example.com/随机后端路径/share/col/free-auto/...
```

不要写成：

```text
https://sub.example.com/share/col/free-auto/...
```

否则大概率会 404。

## 二、重新生成内置配置

如果你修改了 `sources.txt` 或测速脚本，执行：

```bash
cd /opt/substore-free-node
./scripts/bootstrap-substore.sh
./show-info.sh
```

这个脚本会自动：

```text
读取 /opt/substore-free-node/sources.txt
创建/更新 source-001、source-002 等订阅源
创建/更新 free-auto 组合订阅
把 02_httpmeta_speed_filter.js 挂到 free-auto 上
输出可用订阅链接
```

不会清空其他不相关的订阅配置。

## 三、v2rayN 使用方式

复制 `show-info.sh` 输出的：

```text
v2rayN: .../share/col/free-auto/V2Ray%20URI?includeUnsupportedProxy=true
```

然后打开 v2rayN：

```text
订阅分组
→ 订阅分组设置
→ 添加
```

填写：

```text
备注：free-auto
地址：粘贴 v2rayN 订阅链接
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

## 四、Clash Verge / Mihomo 使用方式

复制 `show-info.sh` 输出的：

```text
Clash/Mihomo: .../share/col/free-auto/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true
```

Clash Verge / Clash Verge Rev：

```text
Profiles / 配置
→ New / 新建
→ Remote / URL / 远程配置
→ 粘贴 Clash/Mihomo 订阅链接
→ 保存
→ Update / 更新
→ 选中该配置
```

OpenClash 一般是：

```text
配置订阅
→ 添加
→ 名称：free-auto
→ 地址：Clash/Mihomo 订阅链接
→ 保存并更新
```

## 五、sing-box 使用方式

复制 `show-info.sh` 输出的：

```text
sing-box: .../share/col/free-auto/sing-box?includeUnsupportedProxy=true
```

然后在 sing-box 客户端里添加远程配置或订阅 URL。

不同客户端界面不一样，核心原则是：

```text
v2rayN       → 用 v2rayN 链接
Clash/Mihomo → 用 Clash/Mihomo 链接
sing-box     → 用 sing-box 链接
```

## 六、如果想进入 Sub-Store 面板

执行：

```bash
cd /opt/substore-free-node
./show-info.sh
```

打开：

```text
One-line UI URL
```

里面可以看到已经自动创建好的：

```text
source-001、source-002、source-003 ...
free-auto 组合订阅
http-meta-speed-filter 脚本处理
```

## 七、排错命令

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
