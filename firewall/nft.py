from .system import has_cmd, run_cmd

TABLE = "inet"
TABLE_NAME = "cnwall"
CHAIN_INPUT = "filter_input"
CHAIN_FORWARD = "filter_forward"
SET_NAME = "cnwall_china"

def available() -> bool:
    return has_cmd("nft")

def ensure_table_chain_set() -> None:
    if not available():
        return
    run_cmd(["nft", "add", "table", TABLE, TABLE_NAME])
    run_cmd(["nft", "add", "chain", TABLE, TABLE_NAME, CHAIN_INPUT, "{", "type", "filter", "hook", "input", "priority", "0", ";", "policy", "accept", ";", "}"])
    run_cmd(["nft", "add", "chain", TABLE, TABLE_NAME, CHAIN_FORWARD, "{", "type", "filter", "hook", "forward", "priority", "0", ";", "policy", "accept", ";", "}"])
    run_cmd(["nft", "add", "set", TABLE, TABLE_NAME, SET_NAME, "{", "type", "ipv4_addr", ";", "flags", "interval", ";", "}"])

def flush_set() -> None:
    if not available():
        return
    run_cmd(["nft", "flush", "set", TABLE, TABLE_NAME, SET_NAME])

def add_elements(elements: list) -> None:
    if not available():
        return
    if not elements:
        return
    joined = ",".join(elements)
    run_cmd(["nft", "add", "element", TABLE, TABLE_NAME, SET_NAME, "{", joined, "}"])

def add_block_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_INPUT, proto, "dport", str(port), "ip", "saddr", f"@{SET_NAME}", "counter", "drop"])
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_FORWARD, proto, "dport", str(port), "ip", "saddr", f"@{SET_NAME}", "counter", "drop"])

def delete_block_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    for chain in (CHAIN_INPUT, CHAIN_FORWARD):
        r = run_cmd(["nft", "list", "chain", TABLE, TABLE_NAME, chain])
        if r.returncode != 0:
            continue
        rules = r.stdout.splitlines()
        for line in rules:
            if f"{proto} dport {port}" in line and f"@{SET_NAME}" in line:
                parts = line.split()
                if "handle" in parts:
                    idx = parts.index("handle")
                    if idx + 1 < len(parts):
                        handle = parts[idx + 1]
                        run_cmd(["nft", "delete", "rule", TABLE, TABLE_NAME, chain, "handle", handle])

def list_ours() -> str:
    if not available():
        return "nft未安装"
    r = run_cmd(["nft", "list", "table", TABLE, TABLE_NAME])
    if r.returncode != 0:
        return "未创建nft表或链或集合: inet cnwall/filter, set cnwall_china"
    return r.stdout or r.stderr

def add_block_non_china_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_INPUT, proto, "dport", str(port), "ip", "saddr", "!=", f"@{SET_NAME}", "counter", "drop"])
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_FORWARD, proto, "dport", str(port), "ip", "saddr", "!=", f"@{SET_NAME}", "counter", "drop"])
