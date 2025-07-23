#!/bin/bash

# 自动下载并安装最新版GOST，配置为systemd服务
# 脚本需要以root权限运行

set -e

# 获取最新版本号
get_latest_version() {
    curl -s https://api.github.com/repos/go-gost/gost/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")'
}

# 根据系统架构选择下载文件
get_download_url() {
    local version=$1
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')

    local base_url="https://github.com"

    if [[ "$(curl -s --max-time 2 ipinfo.io/country)" == "CN" ]]; then
        echo "Detect CN IP" >&2
        base_url="https://ghfast.top/https://github.com"
    fi
    
    case "$arch" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            echo "Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac

    echo "${base_url}/go-gost/gost/releases/download/${version}/gost_${version#v}_${os}_${arch}.tar.gz"
}

# 安装GOST
install_gost() {
    local version=$(get_latest_version)
    local download_url=$(get_download_url "$version")

    echo "Downloading GOST $version..."
    wget -O /tmp/gost.tar.gz "$download_url"

    echo "Extracting GOST..."
    tar -xzf /tmp/gost.tar.gz -C /tmp

    echo "Installing GOST to /usr/local/bin..."
    mv /tmp/gost /usr/local/bin/gost
    chmod +x /usr/local/bin/gost

    echo "Cleaning up..."
    rm -f /tmp/gost.tar.gz

    # 验证安装
    if gost -V; then
        echo "GOST installed successfully"
    else
        echo "GOST installation failed"
        exit 1
    fi
}

# 创建systemd服务
create_systemd_service() {
    local service_file="/etc/systemd/system/gost.service"

    if [ -f "$service_file" ]; then
        echo "GOST service already exists at $service_file"
        return
    fi
    
    mkdir -p /etc/gost
    touch /etc/gost/gost.yml
    
    echo "Creating systemd service..."
    cat > "$service_file" <<EOF
[Unit]
Description=GOST Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/gost
ExecStart=/usr/local/bin/gost -api 127.0.0.1:18080 -C /etc/gost/gost.yml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gost
    systemctl start gost

    echo "GOST service created and started. API listening on 127.0.0.1:18080"
}

# 主函数
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi

    install_gost
    create_systemd_service

    echo "Installation complete. You can manage GOST with:"
    echo "  systemctl start|stop|restart|status gost"
}

main
