import json
from .system import has_cmd, run_cmd

def list_published() -> list:
    if not has_cmd("docker"):
        return []
    r = run_cmd(["docker", "ps", "--format", "{{.ID}}"])
    ids = [x.strip() for x in r.stdout.splitlines() if x.strip()]
    ports = []
    for cid in ids:
        ins = run_cmd(["docker", "inspect", cid]).stdout
        data = json.loads(ins)[0]
        pb = data.get("NetworkSettings", {}).get("Ports", {})
        for k, v in pb.items():
            if v:
                p, proto = k.split("/")
                try:
                    ports.append({"container": data.get("Name", "").strip("/"), "port": int(p), "proto": proto})
                except Exception:
                    pass
    return ports

