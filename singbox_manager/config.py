import os
import yaml
from dataclasses import dataclass, field
from typing import List, Optional, Dict

@dataclass
class NodeConfig:
    name: str
    host: str
    user: str
    port: int = 22
    auth_type: str = "key"
    key_path: Optional[str] = None
    password: Optional[str] = None
    password_env: Optional[str] = None
    tags: List[str] = field(default_factory=list)

    def get_password(self) -> Optional[str]:
        if self.password:
            return self.password
        if self.password_env:
            return os.environ.get(self.password_env)
        return None

@dataclass
class GlobalConfig:
    config_source: str
    remote_config_path: str
    restart_command: str

@dataclass
class Inventory:
    nodes: List[NodeConfig]
    global_config: GlobalConfig

def load_config(config_path: str) -> Inventory:
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    with open(config_path, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)

    nodes = []
    for node_data in data.get('nodes', []):
        nodes.append(NodeConfig(
            name=node_data['name'],
            host=node_data['host'],
            user=node_data.get('user', 'root'),
            port=node_data.get('port', 22),
            auth_type=node_data.get('auth_type', 'key'),
            key_path=node_data.get('key_path'),
            password=node_data.get('password'),
            password_env=node_data.get('password_env'),
            tags=node_data.get('tags', [])
        ))

    global_data = data.get('global', {})
    global_config = GlobalConfig(
        config_source=global_data.get('config_source', './config.json'),
        remote_config_path=global_data.get('remote_config_path', '/etc/sing-box/config.json'),
        restart_command=global_data.get('restart_command', 'systemctl restart sing-box')
    )

    return Inventory(nodes=nodes, global_config=global_config)
