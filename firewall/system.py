import subprocess
import shutil

def has_cmd(name: str) -> bool:
    return shutil.which(name) is not None

def run_cmd(args, capture_output: bool = True, input: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=capture_output, text=True, input=input)
