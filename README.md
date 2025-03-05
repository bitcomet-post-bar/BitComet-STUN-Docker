# 介绍

Docker Edition of BitComet Web UI by Post-Bar (unofficial mod)

优化初始配置，并集成 STUN 穿透 与 PeerBanHelper，STUN 穿透需要锥形 NAT 环境。

　*欢迎移植其他下载器*

## 快速使用

**host 网络（传统模式）**

```
docker run -d \
--name BitComet \
--net host \
-v /BC目录:/BitComet \
-v /DL目录:/Downloads \
-v /PBH目录:/PeerBanHelper \
-e BITCOMET_WEBUI_USERNAME='BC WebUI 用户名' \
-e BITCOMET_WEBUI_PASSWORD='BC WebUI 密码' \
-e BITCOMET_WEBUI_PORT='BC WebUI 端口' \
-e BITCOMET_BT_PORT=‘BC BT 端口’ \
-e PBH_WEBUI_TOKEN='PBH Token' \
-e PBH_WEBUI_PORT='PBH WebUI 端口' \
bitcometpostbar/bitcomet:latest
```

**host 网络（改包模式）**

```
docker run -d \
--name BitComet \
--net host \
--cap-add NET_ADMIN \
-v /BC目录:/BitComet \
-v /DL目录:/Downloads \
-v /PBH目录:/PeerBanHelper \
-e BITCOMET_WEBUI_USERNAME='BC WebUI 用户名' \
-e BITCOMET_WEBUI_PASSWORD='BC WebUI 密码' \
-e BITCOMET_WEBUI_PORT='BC WebUI 端口' \
-e BITCOMET_BT_PORT=‘BC BT 端口’ \
-e PBH_WEBUI_TOKEN='PBH Token' \
-e PBH_WEBUI_PORT='PBH WebUI 端口' \
bitcometpostbar/bitcomet:latest
```

**bridge 网络（改包模式）**

```
docker run -d \
--name BitComet \
--cap-add NET_ADMIN \
-p 56082:56082 \
-v /BC目录:/BitComet \
-v /DL目录:/Downloads \
-v /PBH目录:/PeerBanHelper \
-e BITCOMET_WEBUI_USERNAME='BC WebUI 用户名' \
-e BITCOMET_WEBUI_PASSWORD='BC WebUI 密码' \
-e BITCOMET_WEBUI_PORT='BC WebUI 端口' \
-e BITCOMET_BT_PORT=‘BC BT 端口’ \
-e PBH_WEBUI_TOKEN='PBH Token' \
-e PBH_WEBUI_PORT='PBH WebUI 端口' \
bitcometpostbar/bitcomet:latest
```

## 运行日志

本镜像在启动以及 STUN 穿透通道发送变化时会输出重要的信息。

可通过 `docker container logs BitComet` 或各 Docker 前端的日志功能查看。

也可直接打开 `/BitComet/DockerLogs.log` 文件，内容与 Docker 日志同步。

## 穿透模式

本镜像提供两种穿透模式，分别称之为 **传统模式** 和 **改包模式**。

BitTorrent 协议的特性上，需要向 Tracker 通告 NAPT 公网端口，其他 Peer 用户才能获取正确的信息并发起连接。

而在 **运营商级 NAT** 下，内网端口与公网端口不一致且不固定，因此需要动态修改 BT 下载器向 Tracker 通告的端口。

**传统模式** 的原理是获取 NAPT 公网端口后，修改为下载器的监听端口，以达到让下载器向 Tracker 通告公网端口的效果。**要求 Linux 内核 3.9 以上**。

**改包模式** 的原理是获取 NAPT 公网端口后，通过防火墙框架 nftables 识别下载器的 Tracker 流量，并把通告端口篡改为公网端口。**要求 Linux 内核 3.13 以上**。

目前支持 HTTP(S) 与 UDP Tracker 改包，WS(S) Tracker 尚未涉及。

---

**传统模式** 的穿透通道仅支持 TCP 或 UDP 二选一。因为 TCP 与 UDP 的公网端口也不一致，而通常下载器无法分别监听不同的端口号。

**改包模式** 的穿透通道可 TCP 或 UDP 二选一，也可两者同时启用。TCP + UDP 模式下，nftables 会基于 Tracker 服务器的 IP 地址进行 50:50 负载均衡。

nftables 进行 TCP + UDP 分流时，对同一 IP 地址的 Tracker 始终通告为 TCP 或 UDP 的公网端口，以免服务器侧的节点信息频繁变更。但**对于 HTTPS Tracker，由于使用了中间人攻击实现解密**，nftables 检测到的服务器地址始终为 `127.0.0.1`，因此对所有 HTTPS Tracker 都会通告同一个端口号。

　*尚未确认具体会通告 TCP 还是 UDP*

 基于 UDP 的 uTP 传输协议，通过 DHT 的 `implied_port` 及部分下载器实现的 PEX 端口替换，使其本身带有一定的穿透能力，无论传统模式还是改包模式都不会影响此特性。

 实际使用中，在 TCP 端口可被连通的情况下，再开启 UDP 穿透的提升并不大。

 建议仅在 TCP 穿透通道不可用时才启用 UDP 穿透通道。

 ---

改包模式下，**解密 HTTPS Tracker 流量需要信任证书**。该操作只能在当前容器内生效，因此在同一 host 网络下配置多个同方案的穿透时，**HTTPS Tracker 改包仅对最后一个添加规则的容器生效**。（birdge 及 macvlan 网络不受限制）

为避免拦截不必要的 HTTPS 流量而导致网络性能损耗或影响其他程序的通信，仅匹配 [HTTPS Tracker 列表](https://oniicyan.pages.dev/https_trackers.txt) 中的地址与端口。如需要添加自定义 HTTPS Tracker，请编辑 `/BitComet/CustomHttpsTrackers.txt`。

---

对于 HTTP(S) 改包，nftables 规则仅匹配路径为 `/announce` 的 HTTP 请求

以下这样的 Tracker URL 能被识别

`http://example.com/announce`

以下这样的 Tracker URL 会被忽略

`http://example.com/usertoken/announce`

以下这样的 Tracker URL 仍可匹配

`http://example.com/announce.php`

但目前以数据包的二进制偏移量为基准识别并篡改端口，若字符太多将会超出走查范围。（考虑到执行效率，并不会走查整个数据包）

## NAT 类型

本镜像会在启动时 **进行 NAT 映射行为检测，不进行过滤行为检测**，假定用户为 **受限制锥形 NAT**。

可通过容器自动配置 UPnP，或用户自行配置端口映射。其中 **传统模式** 依赖 UPnP，而 **改包模式** 则不限。

## 端口映射

**传统模式** 下，由于 **穿透通道的本地端口与下载器的监听端口不一致且无法固定**，因此需要通过 UPnP 向网关请求一条 **内外不一致** 的端口映射规则。

**改包模式** 巧妙地利用 NAT 优先级的特性，**穿透通道的本地端口与下载器的监听端口一致且始终不变**，因此用户侧网关无需再进行端口映射。但由于防火墙的过滤，仍需要配置 **内外一致** 的端口映射规则以达到防火墙放行的效果。

# 使用说明

## 网络配置

本镜像为提升易用性，尽可能地考虑了用户的网络环境，但仍有需要注意的地方。

### bridge 网络

* **传统模式**：bridge 网络下，容器的 UPnP 的可达性通常受到阻碍。本镜像仍会尝试请求 UPnP 规则，但可能需要用户自行解决可达性问题。

* **改包模式**：bridge 网络下的推荐模式。仅需在容器启动时指定 `-p` 参数映射端口。但 **操作 nftables 需要 `NET_ADMIN` 权限**，当然也可以直接开启 **特权模式 `privileged`**。

### host 网络

* **传统模式**：host 网络下的推荐模式。只要网关开启了 UPnP 功能，可以说是开箱即用。

* **改包模式**：同样需要 `NET_ADMIN` 权限或特权模式。host 网络下，宿主的所有通信（包括其他容器）都会遍历 nftables 规则，尽管规则已尽可能地精确匹配 Tracker 流量。

### macvlan 网络

推荐使用的网络配置，兼顾以上两者的优点。

**传统模式**：同 host 网络

**改包模式**：同 bridge 网络（不干涉容器外的网络通信）

### IPv6

bridge 与 macvlan 网络下如要使用 IPv6，需要额外的配置。详细请自行查阅 Docker 文档。

host 网络 + 传统模式 由于会改变下载器的监听端口，防火墙的 IPv6 规则可能需要更改。

改包模式下的 nftables 规则既不会也不需要干涉任何 IPv6 通信。

## 目录配置

需要挂载的目录为以下三个

BitComet 配置目录：`/BitComet`

BitComet 下载目录：`/Downloads`

PeerBanHelper 目录：`/PeerBanHelper`

以上任意目录若未挂载，则在容器层自动创建，重启时可能会被 Docker 自动清理。

**其余任何额外挂载的目录，都会自动指定为 BirComet 的自定义下载目录**

## 变量说明

本镜像可根据容器启动时配置的环境变量来控制各项功能。

### 基本变量

| 名称 | 说明 | 默认 |
| --- | --- | --- |
| BITCOMET_WEBUI_USERNAME | BitComet WebUI 用户名 | 随机生成 |
| BITCOMET_WEBUI_PASSWORD | BitComet WebUI 密码 | 随机生成 |
| BITCOMET_WEBUI_PORT | BitComet WebUI 端口 | `8080` |
| BITCOMET_BT_PORT | BitComet BT 端口 | `56082` |
| PBH_WEBUI_TOKEN | PeerBanHelper WebUI Token | 随机生成 |
| PBH_WEBUI_PORT | PeerBanHelper WebUI 端口 | `9898` |
| PBH | PeerBanHelper 开关 | 无 |
| STUN | STUN 穿透开关 | 无 |

* 鉴权信息如未指定，则从配置文件中读取；如配置文件也未指定，则随机生成

* 端口如未指定，则使用默认值；如默认端口被占用，则随机使用 `1024-65535` 中未被使用的端口（BT 端口随机范围为 `10000-65535`）

* 启用 STUN 穿透时，BitComet BT 端口会自动更新为公网端口，`BITCOMET_BT_PORT` 将作为穿透通道的本地端口

* PBH 与 STUN 默认启用；如需禁用，请指定为 `0`；不指定或任何非 0 字符都是开启

* 显式指定 `STUN = 1` 时，即使检测结果为公网映射，仍然执行 STUN

### STUN

| 名称 | 说明 | 默认 |
| --- | --- | --- |
| StunMode | 穿透模式，可接受以下值<br>`tcp`：TCP 传统模式<br>`udp`：UDP 传统模式<br>`nfttcp`：TCP 改包模式<br>`nfttcp`：UDP 改包模式<br>`nftboth`：TCP + UDP 改包模式| 自动检测<br>无 NET_ADMIN 权限则使用 TCP 传统模式<br>有 NET_ADMIN 权限则使用 TCP 改包模式 |
| StunModeHttps | HTTPS 改包开关 | 无（指定 `0` 为禁用） |
| StunMitmEnPort | HTTPS 加密流量端口 | `58443` |
| StunMitmDePort | HTTPS 解密流量端口 | `50080` |
| StunHost | 指定当前容器是否 host 网络<br>`0`非 host 网络（bridge 或 macvlan 等）<br>`1`为 host 网络 | 自动检测<br>检测 `eth0` 的 MAC 地址 |
| StunInterface | 穿透时使用的网络接口或源 IP | 无（由路由表选择） |
| StunInterval | 穿透通道检测/保活间隔（秒）| `25` |
| StunUpnpAddr | UPnP 映射规则的目的地址 | `@`（自动检测本地地址） |
| StunUpnpInterface | UPnP 发送 [SSDP](https://zh.wikipedia.org/wiki/SSDP) 报文时使用的接口<br>可填写 IP 地址或接口名称，通常在路由器上运行容器时需要 | 无<br>若找不到 UPnP 设备，则尝试 `br-lan`（若有） |
| StunUpnpUrl | UPnP 设备描述文件 (XML) 的 URL<br>无法使用 [SSDP](https://zh.wikipedia.org/wiki/SSDP) 时需要 | 无 |

* 即使指定了改包模式，若无 NET_ADMIN 权限也会自动变更为传统模式（`nfttcp/nftboth` -> `tcp`, `nftudp` -> `udp`）

* 是否 host 网络的检测方法为判断 `eth0` 的 MAC 地址。使用 Docker 创建的网卡（包括 bridge 或 macvlan 等）默认以 `02:42` 开头，而 host 网络使用宿主网卡，通常为各厂商的登记地址。该检测方法并非 100% 可靠，嵌套容器或指定 MAC 地址启动时会影响检测结果。

* 若穿透通道保持时间低于检测/保活间隔的 3 倍，则自动缩短间隔直至穿透通道稳定

### 其他

| 名称 | 说明 | 默认 |
| --- | --- | --- |
| JvmArgs | [Java 虚拟机附加参数](https://docs.oracle.com/cd/E22289_01/html/821-1274/configuring-the-default-jvm-and-java-arguments.html)，仅用作 PeerBanHelper | 无 |
