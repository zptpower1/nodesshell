import json
import uuid
from typing import Dict

class UserManager:
    def __init__(self, users_path: str):
        self.users_path = users_path

    def add_user(self, username: str) -> str:
        """添加用户并返回UUID"""
        print(f"📌 添加用户: {username}")
        user_uuid = str(uuid.uuid4())
        
        with open(self.users_path, 'r+') as f:
            users = json.load(f)
            users['users'][username] = {"uuid": user_uuid}
            f.seek(0)
            json.dump(users, f, indent=4)
            
        print(f"✅ 用户 {username} 添加成功，UUID: {user_uuid}")
        return user_uuid

    def del_user(self, username: str) -> bool:
        """删除用户，返回是否成功"""
        print(f"📌 删除用户: {username}")
        
        with open(self.users_path, 'r+') as f:
            users = json.load(f)
            if username in users['users']:
                del users['users'][username]
                f.seek(0)
                f.truncate()
                json.dump(users, f, indent=4)
                print(f"✅ 用户 {username} 删除成功")
                return True
            else:
                print(f"❌ 用户 {username} 不存在")
                return False

    def list_users(self) -> Dict:
        """列出所有用户"""
        print("📋 当前用户列表：")
        with open(self.users_path, 'r') as f:
            users = json.load(f)
            for username, details in users['users'].items():
                print(f"用户: {username}, UUID: {details['uuid']}")
            return users['users']

    def query_user(self, username: str) -> Dict:
        """查询用户信息"""
        with open(self.users_path, 'r') as f:
            users = json.load(f)
            if username in users['users']:
                user_info = users['users'][username]
                print(f"用户: {username}, UUID: {user_info['uuid']}")
                return user_info
            else:
                print(f"❌ 用户 {username} 不存在")
                return {}