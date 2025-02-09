# 介绍

Docker Edition of BitComet Web UI by Post-Bar (unofficial mod)

优化初始配置，并集成 PeerBanHelper 与 STUN 穿透。

STUN 穿透需要锥形 NAT 环境及 网关开启 UPnP 功能。

# 使用说明

## 网络配置

**强烈建议使用 Host 网络**，如有需求也可自行配置 macvlan 网络

使用 Bridge 网络时，需要自行解决 UPnP 跨网段请求以及 IPv6 等问题

## 变量说明

### 基本变量

| 名称 | 说明 | 默认 |
| --- | --- | --- |
| BITCOMET_WEBUI_USERNAME | BitComet WebUI 用户名 | 随机生成 |
| BITCOMET_WEBUI_PASSWORD | BitComet WebUI 密码 | 随机生成 |
| BITCOMET_WEBUI_PORT | BitComet WebUI 端口 | `8080` |
| BITCOMET_BT_PORT | BitComet BT 端口 | `6082` |
| PBH_WEBUI_TOKEN | PeerBanHelper WebUI Token | 随机生成 |
| PBH_WEBUI_PORT | PeerBanHelper WebUI 端口 | `9898` |
| PBH | PeerBanHelper 开关 | 无 |
| STUN | STUN 穿透开关 | 无 |

* 鉴权信息如未指定，则从配置文件中读取；如配置文件也未指定，则随机生成

* 端口如未指定，则使用默认值；如默认端口被占用，则随机使用 `1024-65535` 中未被使用的端口

* 启用 STUN 穿透时，BitComet BT 端口会自动更新为公网端口，`BITCOMET_BT_PORT` 将作为 NATMap 的绑定端口

* PBH 与 STUN 默认启用；如需禁用，请指定为 `0`


### STUN

| 名称 | 说明 | 默认 |
| --- | --- | --- |
| StunServer | STUN 服务器：[域名列表](https://oniicyan.pages.dev/stun_servers_domain.txt)、[IP 列表](https://oniicyan.pages.dev/stun_servers_ipv4.txt) | `turn.cloudflare.com` |
| StunHttpServer | 穿透通道保活用的 HTTP 服务器 | `qq.com` |
| StunInterval | 穿透通道保活间隔（秒） | `25` |
| StunInterface | NATMap 绑定接口或 IP<br>通常在策略分流时指定 | 不启用 |
| StunArgs | [NATMap 其他参数](https://github.com/heiher/natmap#how-to-use) | 无 |

### UPnP

| 名称 | 说明 | 默认 |
| --- | --- | --- |
| UpnpAddr | UPnP 规则的目的地址<br>Bridge 网络下请填写宿主的本地 IP 地址 | `@`（自动检测本地地址） |
| UpnpInterface | UPnP 发送 [SSDP](https://zh.wikipedia.org/wiki/SSDP) 报文时使用的接口<br>可填写 IP 地址或接口名称，通常在路由器上运行容器时需要 | 无 |
| UpnpUrl | UPnP 设备描述文件 (XML) 的 URL<br>用作绕过 [SSDP](https://zh.wikipedia.org/wiki/SSDP)，通常在 Bridge 模式下需要 | 无 |
| UpnpArgs | [MiniUPnPc 其他参数](https://manpages.debian.org/unstable/miniupnpc/upnpc.1.en.html) | 无 |
