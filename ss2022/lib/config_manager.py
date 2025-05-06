import os
import json
import uuid

class ConfigManager:
    def __init__(self, config_path):
        self.config_path = config_path

    def setup_config(self):
        config = {
            "server": ["0.0.0.0", "::"],
            "mode": "tcp_and_udp",
            "timeout": 300,
            "method": "2022-blake3-aes-128-gcm",
            "port_password": {
                "8388": str(uuid.uuid4())
            }
        }
        os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
        with open(self.config_path, 'w') as f:
            json.dump(config, f, indent=4)