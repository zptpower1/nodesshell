import cmd
from .config import load_config, save_config, DEFAULT_CONFIG_PATH
from .ufw import status as ufw_status, allow_port, deny_port, allow_docker
from .nft import ensure_table_chain_set, flush_set as nft_flush, add_elements as nft_add_elements, add_block_rule, add_block_non_china_rule, delete_block_rule, list_ours as nft_list
from .ipset import ensure_set as ipset_ensure, flush_set as ipset_flush, add_network as ipset_add, list_set as ipset_list
from .docker_ports import list_published
from .system import run_cmd
from .scheduler import set_cron, remove_cron
import urllib.request

class CnWallCLI(cmd.Cmd):
    prompt = "cnwall> "

    def do_status(self, arg):
        print("ufw状态:")
        print(ufw_status())
        print("nftables状态:")
        print(nft_list())
        print("ipset状态:")
        print(ipset_list())
        print("docker端口:")
        print(list_published())

    def do_config_show(self, arg):
        cfg = load_config()
        print(cfg)

    def do_config_reset(self, arg):
        save_config({"ports": [], "china_ip_source": "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt", "schedule_cron": "0 3 * * *"})
        print("已重置配置")

    def do_apply(self, arg):
        cfg = load_config()
        ensure_table_chain_set()
        for p in cfg.get("ports", []):
            port = int(p.get("port"))
            protos = p.get("protos")
            if not protos:
                proto_single = p.get("proto")
                if proto_single:
                    protos = [proto_single]
                else:
                    protos = ["tcp"]
            open_ = bool(p.get("open", True))
            policy = p.get("china_policy", "none")
            if policy == True:
                policy = "block_china"
            container = p.get("container", "")
            if open_:
                for proto in protos:
                    if container:
                        print(allow_docker(container, port, proto))
                    else:
                        print(allow_port(port, proto))
            if policy == "block_china":
                for proto in protos:
                    add_block_rule(port, proto)
            elif policy == "block_non_china":
                for proto in protos:
                    add_block_non_china_rule(port, proto)
        print("已应用配置")

    def do_reset(self, arg):
        cfg = load_config()
        for p in cfg.get("ports", []):
            port = int(p.get("port"))
            protos = p.get("protos")
            if not protos:
                proto_single = p.get("proto")
                if proto_single:
                    protos = [proto_single]
                else:
                    protos = ["tcp"]
            for proto in protos:
                delete_block_rule(port, proto)
        nft_flush()
        print("已重置规则")

    def do_china_update(self, arg):
        cfg = load_config()
        src = cfg.get("china_ip_source")
        ipset_ensure()
        ipset_flush()
        ensure_table_chain_set()
        nft_flush()
        data = urllib.request.urlopen(src, timeout=30).read().decode("utf-8")
        cidrs = [l.strip() for l in data.splitlines() if l.strip() and "/" in l]
        for c in cidrs:
            ipset_add(c)
        nft_add_elements(cidrs)
        print("已更新china ip")

    def do_schedule_set(self, arg):
        cfg = load_config()
        cron = cfg.get("schedule_cron", "0 3 * * *")
        import sys
        print(set_cron(sys.executable, cron))

    def do_schedule_remove(self, arg):
        print(remove_cron())

    def do_exit(self, arg):
        return True

def run():
    CnWallCLI().cmdloop()
