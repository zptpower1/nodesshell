from .system import has_cmd, run_cmd

TABLE = "inet"
TABLE_NAME = "cnwall"
CHAIN_PREROUTING = "filter_prerouting"
SET_NAME = "cnwall_china"

def available() -> bool:
    return has_cmd("nft")

def ensure_table_chain_set(priority: int | str = -350) -> None:
    if not available():
        return
    run_cmd(["nft", "add", "table", TABLE, TABLE_NAME])
    run_cmd(["nft", "add", "chain", TABLE, TABLE_NAME, CHAIN_PREROUTING, "{", "type", "filter", "hook", "prerouting", "priority", str(priority), ";", "policy", "accept", ";", "}"])
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
    batch = 200
    for i in range(0, len(elements), batch):
        chunk = elements[i : i + batch]
        joined = ",".join(chunk)
        run_cmd(["nft", "add", "element", TABLE, TABLE_NAME, SET_NAME, "{", joined, "}"])

def add_block_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_PREROUTING, proto, "dport", str(port), "ip", "saddr", f"@{SET_NAME}", "counter", "drop"])

def delete_block_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    for chain in (CHAIN_PREROUTING,):
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
        return "未创建nft表或链或集合: inet cnwall/filter_prerouting, set cnwall_china"
    return r.stdout or r.stderr

def add_block_non_china_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_PREROUTING, proto, "dport", str(port), "ip", "saddr", "!=", f"@{SET_NAME}", "counter", "drop"])

def count_set_elements() -> int:
    if not available():
        return 0
    r = run_cmd(["nft", "list", "set", TABLE, TABLE_NAME, SET_NAME])
    if r.returncode != 0:
        return 0
    text = r.stdout
    if "elements = {" not in text:
        return 0
    # naive count by commas; suitable for large sets
    try:
        body = text.split("elements = {", 1)[1].split("}", 1)[0]
        return len([x for x in body.split(",") if x.strip()])
    except Exception:
        return 0

def add_accept_rule(port: int, proto: str, cidr: str) -> None:
    if not available():
        return
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_PREROUTING, proto, "dport", str(port), "ip", "saddr", cidr, "counter", "accept"])

def add_drop_cidr_rule(port: int, proto: str, cidr: str) -> None:
    if not available():
        return
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN_PREROUTING, proto, "dport", str(port), "ip", "saddr", cidr, "counter", "drop"])

def delete_accept_rule(port: int, proto: str, cidr: str) -> None:
    if not available():
        return
    for chain in (CHAIN_PREROUTING,):
        r = run_cmd(["nft", "list", "chain", TABLE, TABLE_NAME, chain])
        if r.returncode != 0:
            continue
        for line in r.stdout.splitlines():
            if f"{proto} dport {port}" in line and cidr in line and "accept" in line:
                parts = line.split()
                if "handle" in parts:
                    idx = parts.index("handle")
                    if idx + 1 < len(parts):
                        handle = parts[idx + 1]
                        run_cmd(["nft", "delete", "rule", TABLE, TABLE_NAME, chain, "handle", handle])
def flush_policy_chains() -> None:
    if not available():
        return
    run_cmd(["nft", "flush", "chain", TABLE, TABLE_NAME, CHAIN_PREROUTING])
def delete_table() -> None:
    if not available():
        return
    run_cmd(["nft", "delete", "table", TABLE, TABLE_NAME])
