import cmd
from .config import load_config, save_config, DEFAULT_CONFIG_PATH
from .ufw import status as ufw_status, allow_port, deny_port, allow_docker
from .nft import ensure_table_chain_set, flush_set as nft_flush, add_elements as nft_add_elements, add_block_rule, add_block_non_china_rule, add_accept_rule, add_drop_cidr_rule, list_ours as nft_list, count_set_elements, flush_policy_chains, delete_table
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
        save_config({"ports": [], "china_ip_source": "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt", "schedule_cron": "0 3 * * *", "allow_private": True, "whitelist_cidrs": [], "blacklist_cidrs": [], "prerouting_priority": -350})
        print("已重置配置")

    def do_apply(self, arg):
        cfg = load_config()
        ensure_table_chain_set(cfg.get("prerouting_priority", -350))
        flush_policy_chains()
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
            allow_private = bool(cfg.get("allow_private", True))
            whitelist = []
            if allow_private:
                whitelist += ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
            whitelist += cfg.get("whitelist_cidrs", [])
            whitelist += p.get("whitelist_cidrs", [])
            for proto in protos:
                for cidr in whitelist:
                    add_accept_rule(port, proto, cidr)
            blacklist = []
            blacklist += cfg.get("blacklist_cidrs", [])
            blacklist += p.get("blacklist_cidrs", [])
            for proto in protos:
                for cidr in blacklist:
                    add_drop_cidr_rule(port, proto, cidr)
            if policy == "block_china":
                for proto in protos:
                    add_block_rule(port, proto)
            elif policy == "block_non_china":
                if count_set_elements() > 0:
                    for proto in protos:
                        add_block_non_china_rule(port, proto)
                else:
                    print("警告: nft集合为空，已跳过非中国IP拦截规则")
        print("已应用配置")

    def do_reset(self, arg):
        delete_table()
        print("已删除nft表 inet cnwall")

    def do_china_update(self, arg):
        cfg = load_config()
        src = cfg.get("china_ip_source")
        ipset_ensure()
        ipset_flush()
        ensure_table_chain_set(cfg.get("prerouting_priority", -350))
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
