import os
from .system import has_cmd, run_cmd

def set_cron(python_bin: str, schedule: str) -> str:
    cmd = f"{schedule} {python_bin} -m firewall.main china_update"
    r1 = run_cmd(["crontab", "-l"])
    lines = r1.stdout.splitlines() if r1.returncode == 0 else []
    lines = [l for l in lines if "firewall.main china_update" not in l]
    lines.append(cmd)
    tmp = "\n".join(lines) + "\n"
    pr = run_cmd(["crontab", "-"], capture_output=False, input=tmp)
    return "已设置定时任务"

def remove_cron() -> str:
    r1 = run_cmd(["crontab", "-l"])
    lines = r1.stdout.splitlines() if r1.returncode == 0 else []
    lines = [l for l in lines if "firewall.main china_update" not in l]
    tmp = "\n".join(lines) + "\n"
    pr = run_cmd(["crontab", "-"], capture_output=False, input=tmp)
    return "已移除定时任务"
