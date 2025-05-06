class ServiceManager:
    def __init__(self, service_file, ss_bin, config_path):
        self.service_file = service_file
        self.ss_bin = ss_bin
        self.config_path = config_path

    def setup_service(self):
        service_content = f"""[Unit]
Description=Shadowsocks Rust Server
After=network.target

[Service]
Type=simple
ExecStart={self.ss_bin} -c {self.config_path}
Restart=on-failure
User=shadowsocks
Group=shadowsocks

[Install]
WantedBy=multi-user.target
"""
        with open(self.service_file, 'w') as f:
            f.write(service_content)