from .system import has_cmd, run_cmd

SET_NAME = "cnwall_china"

def available() -> bool:
    return has_cmd("ipset")

def ensure_set() -> None:
    if not available():
        return
    run_cmd(["ipset", "create", SET_NAME, "hash:net"], capture_output=False)

def flush_set() -> None:
    if not available():
        return
    run_cmd(["ipset", "flush", SET_NAME])

def add_network(cidr: str) -> None:
    if not available():
        return
    run_cmd(["ipset", "add", SET_NAME, cidr])

def list_set() -> str:
    if not available():
        return "ipset未安装"
    r = run_cmd(["ipset", "list", SET_NAME])
    return r.stdout or r.stderr

