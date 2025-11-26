import os
import yaml

DEFAULT_CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config.yaml")

def load_config(path: str = None) -> dict:
    p = path or DEFAULT_CONFIG_PATH
    if not os.path.exists(p):
        return {"ports": [], "china_ip_source": "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt", "schedule_cron": "0 3 * * *", "allow_private": True}
    with open(p, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

def save_config(cfg: dict, path: str = None) -> None:
    p = path or DEFAULT_CONFIG_PATH
    with open(p, "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, allow_unicode=True, sort_keys=False)
