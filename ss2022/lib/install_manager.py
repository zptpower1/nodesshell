import os
import subprocess
from typing import Optional

class InstallManager:
    def __init__(self, ss_download_url: str, ss_bin: str):
        self.ss_download_url = ss_download_url
        self.ss_bin = ss_bin
        self.temp_dir = "/tmp/ssrust"

    def install_from_binary(self):
        """从预编译二进制包安装"""
        os.makedirs(self.temp_dir, exist_ok=True)
        
        print("📥 下载预编译包...")
        subprocess.run(["wget", self.ss_download_url, "-O", f"{self.temp_dir}/ss.tar.xz"], check=True)
        
        print("📦 解压安装...")
        subprocess.run(["tar", "-xf", f"{self.temp_dir}/ss.tar.xz", "-C", "/usr/local/bin/"], check=True)
        subprocess.run(["chmod", "+x", self.ss_bin], check=True)

    def get_installed_version(self) -> Optional[str]:
        """获取已安装版本"""
        try:
            result = subprocess.run([self.ss_bin, "--version"], capture_output=True, text=True)
            return result.stdout.strip()
        except:
            return None