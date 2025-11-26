# firewall

面向 Linux 的轻量级端口安全管理工具，整合 UFW、ufw-docker、nftables 与 ipset，对 Docker 发布端口进行开放与基于中国 IP 的限制控制；支持交互式 CLI、一次性命令，以及定时任务更新 China IP 列表。

## 功能概览
- 交互式命令行与一次性子命令
- 基于 `ufw-docker` 优先、`ufw` 回退的端口开放
- 基于 `nftables` 的中国 IP 端口拦截（集合 `cnwall_china`）
- `ipset` 管理中国 IP CIDR 集合（同名 `cnwall_china`）
- 查询当前 UFW、nftables、ipset 状态与 Docker 发布端口
- 通过 YAML 配置选择开放端口、是否限制中国 IP
- 重置规则（删除端口拦截并清空集合）
- 定时任务定期更新 China IP 列表

## 环境要求
- Linux 主机（需要 root 或具备相应权限）
- `ufw`、`nft`(nftables)、`ipset`、`docker`、`crontab`
- 可选：`ufw-docker`（存在时用于 Docker 端口开放，否则回退到 `ufw`）

## 安装与运行
```bash
# 安装 Python 依赖
pip3 install -r firewall/requirements.txt

# 交互模式
python3 -m firewall.main

# 一次性命令示例
python3 -m firewall.main status
python3 -m firewall.main china_update
python3 -m firewall.main apply
python3 -m firewall.main reset
python3 -m firewall.main config_show
python3 -m firewall.main config_reset
python3 -m firewall.main schedule_set
python3 -m firewall.main schedule_remove
```

> 开发环境不需要存在 `config.yaml`。当配置文件缺失时，程序会使用内置默认配置；只有执行 `config_reset` 才会生成 `config.yaml` 到 `firewall/` 目录。

## 配置文件
- 示例：`firewall/config.yaml.example`
- 实际配置文件（可选）：`firewall/config.yaml`

示例结构：
```yaml
ports:
  - port: 8080
    protos: [tcp, udp]
    open: true
    china_policy: block_china
    container: webapp
  - port: 9090
    protos: [udp]
    open: false
    china_policy: none
    container: ""
china_ip_source: "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
schedule_cron: "0 3 * * *"
```
字段说明：
- `ports[].port`：端口号
- `ports[].protos`：协议数组，支持同时指定 `tcp` 与 `udp`
- `ports[].open`：是否开放端口（`true` 使用 `ufw-docker` 或 `ufw` 开放）
- `ports[].china_policy`：中国 IP 策略，`none` 不限制，`block_china` 限制中国 IP，`block_non_china` 限制非中国 IP
- `ports[].container`：容器名（设置时走 `ufw-docker allow <container> <port> <proto>`；为空则对宿主端口执行 `ufw allow`）
- `china_ip_source`：中国 IP CIDR 列表下载地址
- `schedule_cron`：定时任务表达式（设置为每天 03:00）

## 常用命令
- `status`：打印 UFW、nftables 与 ipset 状态，以及 Docker 发布端口
- `apply`：按 `config.yaml` 应用端口开放与中国 IP 端口拦截（支持 `protos` 多协议与三态策略）
- `reset`：删除端口拦截规则并清空 `cnwall_china` 集合
- `china_update`：下载 China CIDR 列表，写入 `ipset` 与 `nftables` 集合
- `config_show`：打印当前配置（缺失文件时显示默认值）
- `config_reset`：将默认配置写入 `firewall/config.yaml`
- `schedule_set`：设置 `crontab` 定时执行 `china_update`
- `schedule_remove`：移除该定时任务

## 工作原理
- UFW 与 ufw-docker
  - 优先使用 `ufw-docker` 允许容器端口；不存在时回退到 `ufw allow port/proto`
- nftables
  - 表：`inet cnwall`，链：`filter`，集合：`cnwall_china`
  - 对 `@cnwall_china` 源地址访问指定端口的流量进行 `drop`
- ipset
  - 集合：`cnwall_china`，类型 `hash:net`
  - 与 nftables 集合同名，便于同时维护与查询
- 代码位置
  - CLI：`firewall/cli.py`
  - 配置：`firewall/config.py`（缺失时返回默认配置）
  - UFW：`firewall/ufw.py`
  - nftables：`firewall/nft.py`
  - ipset：`firewall/ipset.py`
  - Docker端口查询：`firewall/docker_ports.py`
  - 定时任务：`firewall/scheduler.py`（使用 `python -m firewall.main china_update`）

## 部署建议
- 在 Linux 上以具有必要权限的用户运行（推荐 root）
- 确保 `ufw`、`nft`、`ipset`、`docker`、`crontab` 已安装且可执行
- 若你已有现成的 nftables 表/链命名规范，可在 `firewall/nft.py` 中调整 `TABLE/TABLE_NAME/CHAIN/SET_NAME`
- 若与已有 `cnwall` 脚本联动，请确认集合与链命名一致或做适配

## 注意事项
- 修改防火墙与路由规则可能影响生产流量；先在测试环境验证
- 定时任务会定期刷新 China IP 集合；如需停用请执行 `schedule_remove`
- `.gitignore` 已忽略任意子目录下的 `config.yaml`（示例文件不受影响）

## 目录结构
```
firewall/
  ├── __init__.py
  ├── cli.py
  ├── config.py
  ├── config.yaml.example
  ├── docker_ports.py
  ├── ipset.py
  ├── main.py
  ├── nft.py
  ├── requirements.txt
  ├── scheduler.py
  ├── system.py
  └── ufw.py
```
