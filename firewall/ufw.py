from .system import has_cmd, run_cmd

def status() -> str:
    if not has_cmd("ufw"):
        return "ufw未安装"
    r = run_cmd(["ufw", "status"])
    return r.stdout or r.stderr

def docker_available() -> bool:
    return has_cmd("ufw-docker")

def allow_port(port: int, proto: str = "tcp") -> str:
    if not has_cmd("ufw"):
        return "ufw未安装"
    r = run_cmd(["ufw", "allow", f"{port}/{proto}"])
    return r.stdout or r.stderr

def deny_port(port: int, proto: str = "tcp") -> str:
    if not has_cmd("ufw"):
        return "ufw未安装"
    r = run_cmd(["ufw", "delete", "allow", f"{port}/{proto}"])
    return r.stdout or r.stderr

def allow_docker(container: str, port: int, proto: str = "tcp") -> str:
    if not docker_available():
        return allow_port(port, proto)
    r = run_cmd(["ufw-docker", "allow", container, str(port), proto])
    return r.stdout or r.stderr

