import os
import sys
import time
import logging
import paramiko
from scp import SCPClient
from typing import Optional
from .config import Inventory, NodeConfig

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("SingBoxManager")

class SSHClient:
    def __init__(self, node: NodeConfig):
        self.node = node
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    def connect(self):
        try:
            logger.info(f"Connecting to {self.node.name} ({self.node.host}:{self.node.port})...")
            
            key_filename = None
            if self.node.auth_type == 'key' and self.node.key_path:
                key_filename = os.path.expanduser(self.node.key_path)

            password = self.node.get_password()
            
            self.client.connect(
                hostname=self.node.host,
                port=self.node.port,
                username=self.node.user,
                key_filename=key_filename,
                password=password,
                timeout=10
            )
            logger.info(f"Connected to {self.node.name}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to {self.node.name}: {e}")
            return False

    def close(self):
        self.client.close()

    def run_command(self, command: str) -> bool:
        if not self.client.get_transport() or not self.client.get_transport().is_active():
             if not self.connect():
                 return False

        logger.info(f"Running command on {self.node.name}: {command}")
        stdin, stdout, stderr = self.client.exec_command(command)
        exit_status = stdout.channel.recv_exit_status()
        
        if exit_status == 0:
            logger.info(f"Command success on {self.node.name}")
            return True
        else:
            err = stderr.read().decode().strip()
            logger.error(f"Command failed on {self.node.name}: {err}")
            return False

    def _ensure_remote_dir(self, remote_path: str) -> bool:
        """Ensure the directory for the remote file exists."""
        remote_dir = os.path.dirname(remote_path)
        if not remote_dir:
            return True

        check_cmd = f"test -d {remote_dir}"
        if self.run_command(check_cmd):
            return True

        # Directory doesn't exist, ask user if they want to create it
        logger.warning(f"Remote directory {remote_dir} does not exist on {self.node.name}")
        response = input(f"Do you want to create directory {remote_dir} on {self.node.name}? [y/N] ").strip().lower()
        
        if response == 'y':
            create_cmd = f"mkdir -p {remote_dir}"
            if self.run_command(create_cmd):
                logger.info(f"Created directory {remote_dir} on {self.node.name}")
                return True
            else:
                logger.error(f"Failed to create directory {remote_dir} on {self.node.name}")
                return False
        else:
            logger.info("Operation cancelled by user")
            return False

    def upload_file(self, local_path: str, remote_path: str) -> bool:
        if not self.client.get_transport() or not self.client.get_transport().is_active():
             if not self.connect():
                 return False
        
        # Check and ensure remote directory exists
        if not self._ensure_remote_dir(remote_path):
            return False

        try:
            # Use SCP instead of SFTP
            with SCPClient(self.client.get_transport()) as scp:
                scp.put(local_path, remote_path)
                
            logger.info(f"Uploaded {local_path} to {self.node.name}:{remote_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to upload file to {self.node.name}: {e}")
            return False

class Manager:
    def __init__(self, inventory: Inventory):
        self.inventory = inventory

    def deploy(self, node_name: Optional[str] = None):
        target_nodes = self.inventory.nodes
        if node_name:
            target_nodes = [n for n in self.inventory.nodes if n.name == node_name]
            if not target_nodes:
                logger.error(f"Node {node_name} not found in inventory")
                return

        for node in target_nodes:
            self._deploy_node(node)

    def _deploy_node(self, node: NodeConfig):
        logger.info(f"Starting deployment for {node.name}...")
        
        client = SSHClient(node)
        if not client.connect():
            return

        try:
            # 1. Upload config
            local_config = self.inventory.global_config.config_source
            remote_config = self.inventory.global_config.remote_config_path
            
            if not os.path.exists(local_config):
                logger.error(f"Local config file not found: {local_config}")
                return

            if not client.upload_file(local_config, remote_config):
                return

            # 2. Reload service
            restart_cmd = self.inventory.global_config.restart_command
            if not client.run_command(restart_cmd):
                return
            
            logger.info(f"Deployment to {node.name} completed successfully")

        finally:
            client.close()

