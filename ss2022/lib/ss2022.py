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
    def __init__(self, script_dir: Optional[str] = None):
        self.ss_base_path = "/usr/local/etc/shadowsocks2022"
        self.config_path = f"{self.ss_base_path}/config.json"
        self.users_path = f"{self.ss_base_path}/users.json"
        self.backup_dir = f"{self.ss_base_path}/backup"
        self.log_dir = "/var/log/shadowsocks2022"
        self.service_name = "shadowsocks2022" # 修正服务名称以保持一致
        self.service_file = f"/etc/systemd/system/{self.service_name}.service" # 使用 self.service_name
        self.ss_bin = "/usr/local/bin/ssserver"
        self.script_dir = script_dir
        
        # 初始化各个管理器
        self.config_manager = ConfigManager(self.config_path)
        self.service_manager = ServiceManager(self.service_file, self.ss_bin, self.config_path)
        self.user_manager = UserManager(self.users_path)
        # 推迟 install_manager 的初始化，直到 _get_download_url 可以被调用
        self._install_manager: Optional[InstallManager] = None


    @property
    def install_manager(self) -> InstallManager:
        if self._install_manager is None:
            # 确保在需要时才初始化，避免启动时就进行网络请求
            try:
                download_url = self._get_download_url()
            except requests.exceptions.RequestException as e:
                print(f"❌ 获取最新版本失败，无法初始化安装管理器: {e}")
                # 提供一个默认或无效的URL，或者让程序在这里退出/抛出更严重的错误
                # 这里我们暂时允许它继续，但 upgrade 和 install_from_binary 可能会失败
                download_url = "" # 或者一个已知的旧版本URL作为备用
            self._install_manager = InstallManager(download_url, self.ss_bin)
        return self._install_manager

    def _get_download_url(self) -> str:
        """获取下载URL"""
        version = self._get_latest_version()
        return f"https://github.com/shadowsocks/shadowsocks-rust/releases/download/{version}/shadowsocks-{version}.x86_64-unknown-linux-gnu.tar.xz"

    def _get_latest_version(self) -> str:
        """获取最新版本号"""
        print("ℹ️ 正在获取最新版本号...")
        response = requests.get("https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest", timeout=10)
        response.raise_for_status() # 如果请求失败则抛出异常
        return response.json()["tag_name"]

    def check_root(self) -> bool:
        if os.geteuid() != 0:
            print("❌ 此脚本需要以 root 权限运行")
            sys.exit(1)
        return True

    def _create_symlinks(self):
        if not self.script_dir:
            print("⚠️ 未提供脚本目录，跳过创建软链接。")
            return

        links_to_create = {
            "ss2022_config": self.ss_base_path,
            "ss2022_logs": self.log_dir
        }

        print("🔗 正在创建软链接...")
        for link_name, target_path_str in links_to_create.items():
            link_path = Path(self.script_dir) / link_name
            target_path = Path(target_path_str)

            if not target_path.exists():
                print(f"⚠️ 目标路径 {target_path} 不存在，无法创建软链接 {link_name}。")
                continue

            if link_path.exists() or link_path.is_symlink():
                print(f"ℹ️ 软链接或文件 {link_path} 已存在，跳过创建。")
            else:
                try:
                    os.symlink(target_path_str, link_path)
                    print(f"✅ 软链接 {link_path} -> {target_path_str} 创建成功。")
                except OSError as e:
                    print(f"❌ 创建软链接 {link_path} 失败: {e}")
                except Exception as e:
                    print(f"❌ 创建软链接 {link_path} 时发生未知错误: {e}")


    def install(self):
        """安装SS2022服务"""
        self.check_root()
        print("📦 开始安装 SS2022...")
        
        # 确保 install_manager 已初始化
        _ = self.install_manager

        try:
            # 尝试apt安装
            print("ℹ️ 尝试通过 apt 安装 shadowsocks-rust...")
            subprocess.run(["apt-get", "update"], check=True, capture_output=True, text=True)
            subprocess.run(["apt-get", "install", "-y", "shadowsocks-rust"], check=True, capture_output=True, text=True)
            print("✅ 通过apt安装成功")
        except subprocess.CalledProcessError as e:
            print(f"📌 apt安装失败: {e.stderr or e.stdout or e}")
            print("ℹ️ 使用预编译二进制包安装...")
            if self.install_manager.ss_download_url: # 检查下载URL是否有效
                 self.install_manager.install_from_binary()
            else:
                print("❌ 下载URL无效，无法从二进制包安装。请检查网络连接或GitHub API状态。")
                return # 或者抛出异常

        # 设置服务和配置
        self.service_manager.setup_service()
        self.config_manager.setup_config()
        print("✅ 安装完成！")
        self._create_symlinks()


    def uninstall(self):
        """卸载SS2022服务"""
        self.check_root()
        print(f"⚠️ 即将卸载 SS2022 ({self.service_name})，并删除其所有配置文件和程序。")
        
        # 停止和禁用服务
        try:
            subprocess.run(["systemctl", "stop", self.service_name], check=True, capture_output=True, text=True)
            subprocess.run(["systemctl", "disable", self.service_name], check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            print(f"ℹ️ 停止或禁用服务 {self.service_name} 时发生错误 (可能服务未安装或已停止): {e.stderr or e.stdout or e}")


        # 清理文件
        paths_to_remove = [self.service_file, self.config_path, self.users_path]
        for path_str in paths_to_remove:
            path_obj = Path(path_str)
            if path_obj.exists():
                try:
                    os.remove(path_obj)
                    print(f"🗑️ 已删除文件: {path_obj}")
                except OSError as e:
                    print(f"❌ 删除文件 {path_obj} 失败: {e}")
        
        dirs_to_remove = [self.ss_base_path, self.log_dir]
        for dir_str in dirs_to_remove:
            dir_obj = Path(dir_str)
            if dir_obj.exists() and dir_obj.is_dir():
                try:
                    # 尝试删除空目录，如果非空，os.rmdir会失败
                    # 更安全的做法是使用 shutil.rmtree，但这里我们先尝试 os.rmdir
                    os.rmdir(dir_obj)
                    print(f"🗑️ 已删除目录: {dir_obj}")
                except OSError as e:
                    print(f"❌ 删除目录 {dir_obj} 失败 (可能是因为目录非空): {e}")
        
        # 清理软链接
        if self.script_dir:
            link_names = ["ss2022_config", "ss2022_logs"]
            for link_name in link_names:
                link_path = Path(self.script_dir) / link_name
                if link_path.is_symlink():
                    try:
                        os.remove(link_path)
                        print(f"🗑️ 已删除软链接: {link_path}")
                    except OSError as e:
                        print(f"❌ 删除软链接 {link_path} 失败: {e}")
                
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
        
        # 确保 install_manager 已初始化
        _ = self.install_manager
        if not self.install_manager.ss_download_url: # 检查下载URL是否有效
            print("❌ 下载URL无效，无法执行升级。请检查网络连接或GitHub API状态。")
            return

        try:
            current_version = self._get_latest_version()
        except requests.exceptions.RequestException as e:
            print(f"❌ 获取最新版本失败: {e}")
            return
            
        installed_version = self.install_manager.get_installed_version()
        
        print(f"当前已安装版本: {installed_version or '未知'}, 最新版本: {current_version}")
        
        if installed_version == current_version and installed_version is not None:
            print("✅ 当前已是最新版本，无需升级。")
            return

        if installed_version and installed_version > current_version : #理论上不应该发生
             print(f"⚠️ 已安装版本 ({installed_version}) 高于检测到的最新版本 ({current_version})。请检查。")
             # 可以选择是否继续

        confirm = input(f"检测到新版本 {current_version} (或需要重新安装)，是否升级？(y/N): ")
        if confirm.lower() == 'y':
            print("🔄 开始升级...")
            # 更新下载URL，以防之前初始化时获取的是旧的
            self.install_manager.ss_download_url = self._get_download_url()
            self.install_manager.install_from_binary()
            # 升级后可能需要重启服务
            try:
                print(f"🔄 正在重启 {self.service_name} 服务...")
                subprocess.run(["systemctl", "restart", self.service_name], check=True, capture_output=True, text=True)
                print(f"✅ 服务 {self.service_name} 重启成功。")
            except subprocess.CalledProcessError as e:
                print(f"❌ 重启服务 {self.service_name} 失败: {e.stderr or e.stdout or e}")
            print("✅ 升级完成！")
        else:
            print("❌ 已取消升级操作。")

def main():
    parser = argparse.ArgumentParser(description='SS2022管理工具')
    parser.add_argument('action', choices=['install', 'uninstall', 'add', 'del', 'list', 'query', 'upgrade'])
    parser.add_argument('param', nargs='?', help='操作参数 (例如: 用户名)')
    parser.add_argument('--script-dir', type=str, help='调用此脚本的shell脚本所在目录，用于创建软链接')
    
    args = parser.parse_args()
    
    # 确保在调用 SS2022Manager 之前 script_dir 是绝对路径且存在 (如果提供的话)
    script_dir_abs = None
    if args.script_dir:
        script_dir_path = Path(args.script_dir)
        if not script_dir_path.is_dir():
            print(f"❌ 提供的脚本目录 '{args.script_dir}' 无效或不存在。软链接功能将不可用。")
        else:
            script_dir_abs = str(script_dir_path.resolve())


    manager = SS2022Manager(script_dir=script_dir_abs)
    
    action_func = getattr(manager, args.action, None)

    if action_func:
        try:
            if args.action in ['add', 'del', 'query'] and args.param:
                action_func(args.param)
            elif args.action in ['install', 'uninstall', 'list', 'upgrade']:
                if args.param:
                    print(f"⚠️ 操作 '{args.action}' 不需要额外参数 '{args.param}'，已忽略。")
                action_func()
            elif args.action in ['add', 'del', 'query'] and not args.param:
                 parser.error(f"操作 '{args.action}' 需要一个参数 (例如: 用户名)。")
            else: # 应该不会到这里，因为 choices 限制了
                parser.print_help()
        except requests.exceptions.RequestException as e:
            print(f"❌ 网络请求错误: {e}")
        except subprocess.CalledProcessError as e:
            print(f"❌ 子进程命令执行错误: {e}")
            if e.stdout: print(f"标准输出:\n{e.stdout}")
            if e.stderr: print(f"标准错误:\n{e.stderr}")
        except Exception as e:
            print(f"❌ 执行操作 '{args.action}' 时发生未知错误: {e}")
            import traceback
            traceback.print_exc()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()