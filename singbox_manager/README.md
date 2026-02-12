# SingBox Manager

一个用于批量管理 Sing-box 节点的 Python 工具。支持通过 SSH (密钥或密码) 分发配置和重启服务。

## 功能

- 支持多节点管理
- 支持 SSH 密钥和密码认证
- 支持从环境变量读取密码
- 批量部署配置
- 批量重启服务

## 安装依赖

```bash
pip install -r requirements.txt
```

## 配置

复制 `inventory.yaml.example` 到 `inventory.yaml` 并根据需要修改：

```bash
cp inventory.yaml.example inventory.yaml
```

编辑 `inventory.yaml`：

```yaml
nodes:
  - name: "node-01"
    host: "1.2.3.4"
    user: "root"
    auth_type: "key"
    key_path: "~/.ssh/id_rsa"

global:
  config_source: "./singbox/config.json"
  remote_config_path: "/etc/sing-box/config.json"
  restart_command: "systemctl restart sing-box"
```

## 使用方法

### 列出节点

```bash
python3 -m singbox_manager list
```

### 部署所有节点

```bash
python3 -m singbox_manager deploy
```

### 部署指定节点

```bash
python3 -m singbox_manager deploy --node node-01
```
