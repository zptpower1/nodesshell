from .system import has_cmd, run_cmd

TABLE = "inet"
TABLE_NAME = "cnwall"
CHAIN = "filter"
SET_NAME = "cnwall_china"

def available() -> bool:
    return has_cmd("nft")

def ensure_table_chain_set() -> None:
    if not available():
        return
    run_cmd(["nft", "add", "table", TABLE, TABLE_NAME])
    run_cmd(["nft", "add", "chain", TABLE, TABLE_NAME, CHAIN])
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
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN, proto, "dport", str(port), "ip", "saddr", f"@{SET_NAME}", "counter", "drop"])

def delete_block_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    rules = run_cmd(["nft", "list", "chain", TABLE, TABLE_NAME, CHAIN]).stdout.splitlines()
    for line in rules:
        if f"{proto} dport {port}" in line and f"@{SET_NAME}" in line:
            handle_part = [p for p in line.split() if p.startswith("handle")]
            if handle_part:
                handle = handle_part[0].split()[1] if len(handle_part[0].split()) > 1 else None
                if handle:
                    run_cmd(["nft", "delete", "rule", TABLE, TABLE_NAME, CHAIN, "handle", handle])

def list_ours() -> str:
    if not available():
        return "nft未安装"
    r = run_cmd(["nft", "list", "table", TABLE, TABLE_NAME])
    return r.stdout or r.stderr

def add_block_non_china_rule(port: int, proto: str = "tcp") -> None:
    if not available():
        return
    run_cmd(["nft", "add", "rule", TABLE, TABLE_NAME, CHAIN, proto, "dport", str(port), "ip", "saddr", "!=", f"@{SET_NAME}", "counter", "drop"])
