#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import uuid
import subprocess
from pathlib import Path
import argparse
import requests
from typing import Optional, Dict, Union

from config_manager import ConfigManager
from service_manager import ServiceManager
from user_manager import UserManager
from install_manager import InstallManager

class SS2022Manager:
    def __init__(self):
        self.ss_base_path = "/usr/local/etc/shadowsocks2022"
        self.config_path = f"{self.ss_base_path}/config.json"
        self.users_path = f"{self.ss_base_path}/users.json"
        self.backup_dir = f"{self.ss_base_path}/backup"
        self.log_dir = "/var/log/shadowsocks2022"
        self.service_name = "shadowsocks"
        self.service_file = "/etc/systemd/system/shadowsocks2022.service"
        self.ss_bin = "/usr/local/bin/ssserver"
        
        # 初始化各个管理器
        self.config_manager = ConfigManager(self.config_path)
        self.service_manager = ServiceManager(self.service_file, self.ss_bin, self.config_path)
        self.user_manager = UserManager(self.users_path)
        self.install_manager = InstallManager(self._get_download_url(), self.ss_bin)

    def _get_download_url(self) -> str:
        """获取下载URL"""
        version = self._get_latest_version()
        return f"https://github.com/shadowsocks/shadowsocks-rust/releases/download/{version}/shadowsocks-{version}.x86_64-unknown-linux-gnu.tar.xz"

    def _get_latest_version(self) -> str:
        """获取最新版本号"""
        response = requests.get("https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest")
        return response.json()["tag_name"]

    def check_root(self) -> bool:
        if os.geteuid() != 0:
            print("❌ 此脚本需要以 root 权限运行")
            sys.exit(1)
        return True

    def install(self):
        """安装SS2022服务"""
        self.check_root()
        print("📦 开始安装 SS2022...")
        
        try:
            # 尝试apt安装
            subprocess.run(["apt-get", "update"], check=True)
            subprocess.run(["apt-get", "install", "-y", "shadowsocks-rust"], check=True)
            print("✅ 通过apt安装成功")
        except subprocess.CalledProcessError:
            print("📌 apt安装失败，使用预编译二进制包安装...")
            self.install_manager.install_from_binary()

        # 设置服务和配置
        self.service_manager.setup_service()
        self.config_manager.setup_config()
        print("✅ 安装完成！")

    def uninstall(self):
        """卸载SS2022服务"""
        self.check_root()
        print("⚠️ 即将卸载 SS2022，并删除其所有配置文件和程序。")
        
        # 停止和禁用服务
        subprocess.run(["systemctl", "stop", self.service_name], check=True)
        subprocess.run(["systemctl", "disable", self.service_name], check=True)
        
        # 清理文件
        for path in [self.service_file, self.config_path, self.users_path]:
            if os.path.exists(path):
                os.remove(path)
        
        for directory in [self.ss_base_path, self.log_dir]:
            if os.path.exists(directory):
                os.rmdir(directory)
                
        print("✅ 卸载完成。")

    # 用户管理相关方法委托给UserManager
    def add_user(self, username: str):
        """添加用户"""
        self.check_root()
        self.user_manager.add_user(username)

    def del_user(self, username: str):
        """删除用户"""
        self.check_root()
        self.user_manager.del_user(username)

    def list_users(self):
        """列出所有用户"""
        self.check_root()
        self.user_manager.list_users()

    def query_user(self, username: str):
        """查询用户信息"""
        self.check_root()
        self.user_manager.query_user(username)

    def upgrade(self):
        """升级SS2022服务"""
        self.check_root()
        current_version = self._get_latest_version()
        installed_version = self.install_manager.get_installed_version()
        
        print(f"当前版本: {installed_version}, 最新版本: {current_version}")
        
        if current_version > installed_version:
            confirm = input("检测到新版本，是否升级？(y/N): ")
            if confirm.lower() == 'y':
                self.install_manager.ss_download_url = self._get_download_url()
                self.install_manager.install_from_binary()
                print("✅ 升级完成！")
            else:
                print("❌ 已取消升级操作。")
        else:
            print("当前已是最新版本，无需升级。")

def main():
    parser = argparse.ArgumentParser(description='SS2022管理工具')
    parser.add_argument('action', choices=['install', 'uninstall', 'add', 'del', 'list', 'query', 'upgrade'])
    parser.add_argument('param', nargs='?', help='操作参数')
    
    args = parser.parse_args()
    manager = SS2022Manager()
    
    actions = {
        'install': manager.install,
        'uninstall': manager.uninstall,
        'add': lambda: manager.add_user(args.param),
        'del': lambda: manager.del_user(args.param),
        'list': manager.list_users,
        'query': lambda: manager.query_user(args.param),
        'upgrade': manager.upgrade,
    }
    
    action = actions.get(args.action)
    if action:
        action()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()