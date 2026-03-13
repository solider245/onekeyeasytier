#!/bin/bash

#================================================================================
# EasyTier OpenWrt 专属部署管理脚本
# 适配 OpenWrt (aarch64) 环境，使用 procd 进行服务管理。
#================================================================================

# --- 脚本配置 ---
GITHUB_PROXY="gh.565600.xyz"

# 颜色定义
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# --- OpenWrt 专属路径和文件名 ---
INSTALL_DIR="/usr/bin"
CONFIG_DIR="/etc/easytier"
CONFIG_FILE="${CONFIG_DIR}/easytier.toml"
CORE_BINARY_NAME="easytier-core"
CLI_BINARY_NAME="easytier-cli"
ALIAS_PATH="/usr/bin/et"
SERVICE_NAME="easytier"
SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"

# --- OpenWrt aarch64 专属下载链接 ---
DOWNLOAD_URL="https://gh.565600.xyz/https://github.com/EasyTier/EasyTier/releases/download/v2.3.2/easytier-linux-aarch64-v2.3.2.zip"
GITHUB_API_URL="https://api.github.com/repos/EasyTier/EasyTier/releases"


# --- 辅助函数 ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以 root 权限运行。${NC}"; exit 1
    fi
}

check_arch() {
    CURRENT_ARCH=$(uname -m)
    if [ "$CURRENT_ARCH" != "aarch64" ]; then
        echo -e "${RED}错误: 此脚本专为 aarch64 架构设计。检测到当前架构为: $CURRENT_ARCH${NC}"
        exit 1
    fi
}

check_dependencies() {
    local missing_deps=""
    for cmd in curl unzip find mktemp; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done

    if [ -n "$missing_deps" ]; then
        echo -e "${YELLOW}检测到缺失的依赖: ${missing_deps}${NC}"
        read -p "是否尝试使用 opkg 自动安装? (y/n): " choice
        if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
            echo -e "${RED}操作中止。${NC}"; exit 1
        fi
        
        opkg update
        opkg install $missing_deps
        for dep in $missing_deps; do
             if ! command -v "$dep" >/dev/null 2>&1; then
                echo -e "${RED}依赖 '$dep' 安装失败。请手动安装后重试。${NC}"; exit 1
             fi
        done
    fi
}

check_installed() {
    if [ ! -f "${INSTALL_DIR}/${CORE_BINARY_NAME}" ]; then
        echo -e "${YELLOW}EasyTier 尚未安装。请先选择选项 1。${NC}"; return 1
    fi
    return 0
}

set_toml_value() {
    sed -i.bak "s|^#* *${1} *=.*|${1} = ${2}|" "$3" && rm "${3}.bak"
}

generate_random_string() {
    local length=$1
    local chars="abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local result=""
    for i in $(seq 1 "$length"); do
        local random_index=$((RANDOM % ${#chars}))
        result="${result}${chars:$random_index:1}"
    done
    echo "$result"
}

get_local_ip() {
    local ip
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$ip" ]; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "")
    fi
    echo "$ip"
}

get_public_ip() {
    local public_ip
    if command -v curl >/dev/null 2>&1; then
        public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
    fi
    if [ -z "$public_ip" ] && command -v curl >/dev/null 2>&1; then
        public_ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    fi
    echo "$public_ip"
}

show_network_requirements() {
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  ⚠️  网络要求说明${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}1. 防火墙要求:${NC}"
    echo "   需要开放以下端口:"
    echo "   • UDP: 11010"
    echo "   • TCP: 11010, 11011, 11012"
    echo ""
    echo -e "${BLUE}2. 公网访问要求:${NC}"
    echo "   • 作为种子节点，需要公网 IP 或端口映射"
    echo "   • 如果在 NAT 后面，需要做端口映射"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p "我已了解上述要求，继续部署 (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${RED}操作已取消。${NC}"
        return 1
    fi
    return 0
}

show_port_setup_guide() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  📝 端口配置说明 (OpenWrt)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}已在防火墙中开放以下端口:${NC}"
    echo "   • UDP 11010"
    echo "   • TCP 11010, 11011, 11012"
    echo ""
    echo -e "${BLUE}OpenWrt 防火墙配置 (LuCI):${NC}"
    echo "   网络 -> 防火墙 -> 通信规则 -> 新建规则"
    echo ""
    echo -e "${BLUE}命令行配置示例:${NC}"
    echo "   uci add firewall rule"
    echo "   uci set firewall.@rule[-1].src=wan"
    echo "   uci set firewall.@rule[-1].dest_port=11010"
    echo "   uci set firewall.@rule[-1].proto=udp"
    echo "   uci set firewall.@rule[-1].target=ACCEPT"
    echo "   uci commit firewall"
    echo "   /etc/init.d/firewall restart"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

generate_network_token() {
    local network_name="$1"
    local network_secret="$2"
    local peer_address="$3"
    
    local token="easytier://${network_name}?secret=${network_secret}&peer=${peer_address}"
    echo "$token"
}

parse_network_token() {
    local token="$1"
    
    if [[ "$token" =~ ^easytier://([^?]+)\?secret=([^&]+)\&peer=(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}|${BASH_REMATCH[3]}"
        return 0
    else
        return 1
    fi
}

flush_output() {
    echo ""
}

show_community_nodes() {
    echo ""
    echo "=============================================="
    echo "       可用的公共节点列表"
    echo "=============================================="
    echo ""
    echo " 1. tcp://public.easytier.top:11010 (官方节点 - 可能不稳定)"
    echo " 2. tcp://124.221.120.232:11010 (社区节点 - 北京联通)"
    echo " 3. tcp://43.154.108.32:11010 (社区节点 - 广东电信)"
    echo " 4. tcp://47.119.167.113:11010 (社区节点 - 上海阿里云)"
    echo " 5. tcp://47.116.129.91:11010 (社区节点 - 江苏移动)"
    echo " 6. tcp://47.243.72.177:11010 (社区节点 - 香港)"
    echo " 7. tcp://149.28.85.42:11010 (社区节点 - 新加坡)"
    echo " 8. tcp://207.148.114.92:11010 (社区节点 - 日本东京)"
    echo " 9. tcp://149.28.197.141:11010 (社区节点 - 澳大利亚)"
    echo "10. 自定义节点地址"
    echo "11. 跳过 (不添加公共节点)"
    echo ""
}

select_community_node() {
    show_community_nodes
    flush_output
    echo -n "请选择要使用的公共节点 [1-11]: "
    read node_choice
    
    case $node_choice in
        1)
            echo "tcp://public.easytier.top:11010"
            ;;
        2)
            echo "tcp://124.221.120.232:11010"
            ;;
        3)
            echo "tcp://43.154.108.32:11010"
            ;;
        4)
            echo "tcp://47.119.167.113:11010"
            ;;
        5)
            echo "tcp://47.116.129.91:11010"
            ;;
        6)
            echo "tcp://47.243.72.177:11010"
            ;;
        7)
            echo "tcp://149.28.85.42:11010"
            ;;
        8)
            echo "tcp://207.148.114.92:11010"
            ;;
        9)
            echo "tcp://149.28.197.141:11010"
            ;;
        10)
            read -p "请输入自定义节点地址 (如 tcp://1.2.3.4:11010): " custom_node
            if [ -n "$custom_node" ]; then
                echo "$custom_node"
            else
                echo ""
            fi
            ;;
        11)
            echo "skip"
            ;;
        *)
            echo -e "${YELLOW}无效选择，将跳过添加公共节点${NC}"
            echo "skip"
            ;;
    esac
}


# --- OpenWrt 服务管理功能 ---
create_service_file() {
    mkdir -p "$(dirname "${SERVICE_FILE}")"
    cat > "${SERVICE_FILE}" << 'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=95
STOP=01

PROG=/usr/bin/easytier-core
CONFIG_FILE="/etc/easytier/easytier.toml"

start_service() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "配置文件 $CONFIG_FILE 未找到"
        return 1
    fi
    
    procd_open_instance
    procd_set_param command ${PROG} -c ${CONFIG_FILE}
    procd_set_param respawn
    procd_set_param file ${CONFIG_FILE}
    procd_close_instance
}

reload_service() {
    stop
    start
}

service_triggers() {
    procd_add_reload_trigger "easytier"
}
EOF
    chmod +x "${SERVICE_FILE}"
    echo -e "${GREEN}OpenWrt init 脚本创建成功: ${SERVICE_FILE}${NC}"
}

start_service() { service_action start; }
stop_service() { service_action stop; }
restart_service() { service_action restart; }
enable_service() { service_action enable; }
disable_service() { service_action disable; }
status_service() { service_action status; }

service_action() {
    if [ ! -f "${SERVICE_FILE}" ]; then
        echo -e "${YELLOW}服务脚本 ${SERVICE_FILE} 不存在。请先部署网络以创建它。${NC}"
        return 1
    fi
    ${SERVICE_FILE} "$1"
}

log_service() {
    echo "正在使用 logread 查看日志，按 Ctrl+C 退出。"
    logread -f -e ${CORE_BINARY_NAME}
}

# --- 主功能函数 ---
create_shortcut() {
    local SCRIPT_PATH
    SCRIPT_PATH=$(realpath "$0" 2>/dev/null || (cd "$(dirname "$0")" && echo "$(pwd)/$(basename "$0")"))
    if [ -L "${ALIAS_PATH}" ] && [ "$(readlink "${ALIAS_PATH}")" = "${SCRIPT_PATH}" ]; then
        return 0
    fi
    echo -e "${YELLOW}正在创建 'et' 快捷命令...${NC}"
    chmod +x "${SCRIPT_PATH}"
    ln -sf "${SCRIPT_PATH}" "${ALIAS_PATH}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}成功! 现在你可以在终端中直接输入 'et' 来运行此脚本。${NC}"
    else
        echo -e "${RED}创建快捷命令失败。请检查权限。${NC}"
    fi
}

remove_shortcut() {
    if [ -L "${ALIAS_PATH}" ]; then
        rm -f "${ALIAS_PATH}" >/dev/null 2>&1
    fi
}

install_easytier() {
    echo -e "${GREEN}--- 开始安装或更新 EasyTier (OpenWrt/aarch64) ---${NC}"

    local need_restart=false

    # 检测是否有进程在运行
    if pgrep -x "easytier-core" > /dev/null 2>&1 || ps | grep -q "easytier-core"; then
        echo -e "${YELLOW}检测到 EasyTier 正在运行:${NC}"
        echo "  1. 停止服务后安装（推荐）"
        echo "  2. 强制安装（可能导致失败）"
        read -p "请选择 [1-2](默认1): " install_choice
        if [ "$install_choice" = "1" ] || [ -z "$install_choice" ]; then
            echo "正在停止 EasyTier 服务..."
            stop_service
            need_restart=true
            sleep 2
        else
            echo -e "${YELLOW}警告: 强制安装可能会失败!${NC}"
        fi
    fi

    echo "请选择版本类型:"
    echo "  1. 稳定版 (Stable) - 推荐"
    echo "  2. 预发布版 (Pre-release) - 最新功能，可能不稳定"
    read -p "请选择 [1-2](默认1): " version_choice

    local version
    local download_file_url

    if [ "$version_choice" = "2" ]; then
        echo "1. 获取预发布版本信息..."
        local releases_info
        releases_info=$(curl -sL "$GITHUB_API_URL")
        if [ -z "$releases_info" ]; then
            echo -e "${RED}错误: 无法从 GitHub API 获取版本信息。${NC}"; return 1
        fi
        version=$(echo "$releases_info" | grep -o '"tag_name": "[^"]*' | head -1 | cut -d'"' -f4)
        if [ -z "$version" ]; then
            echo -e "${RED}错误: 未找到预发布版本。${NC}"; return 1
        fi
    else
        echo "1. 获取稳定版本信息..."
        local latest_info
        latest_info=$(curl -sL "https://api.github.com/repos/EasyTier/EasyTier/releases/latest")
        if [ -z "$latest_info" ]; then
            echo -e "${RED}错误: 无法从 GitHub API 获取版本信息。${NC}"; return 1
        fi
        version=$(echo "$latest_info" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    fi

    download_file_url="https://gh.565600.xyz/https://github.com/EasyTier/EasyTier/releases/download/${version}/easytier-linux-aarch64-${version}.zip"
    echo "选择版本: ${version}"
    echo "2. 使用代理下载: ${download_file_url}"

    local temp_file
    temp_file=$(mktemp)
    
    curl -L --progress-bar -o "$temp_file" "$download_file_url"
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败!${NC}"; rm -f "$temp_file"; return 1
    fi
    
    echo "3. 创建临时解压目录并解压..."
    local extract_dir
    extract_dir=$(mktemp -d)
    
    unzip -o "$temp_file" -d "$extract_dir" > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}解压失败! 请检查文件是否为有效的 zip 格式。${NC}"
        rm -f "$temp_file"; rm -rf "$extract_dir"; return 1
    fi

    echo "4. 查找核心文件..."
    local found_core
    found_core=$(find "$extract_dir" -type f -name "${CORE_BINARY_NAME}")
    local found_cli
    found_cli=$(find "$extract_dir" -type f -name "${CLI_BINARY_NAME}")

    if [ -z "$found_core" ] || [ -z "$found_cli" ]; then
        echo -e "${RED}错误: 在解压目录中未动态找到核心文件。${NC}"
        rm -f "$temp_file"; rm -rf "$extract_dir"; return 1
    fi
    
    echo "5. 安装文件..."
    mkdir -p "$INSTALL_DIR"
    mv -f "$found_core" "${INSTALL_DIR}/${CORE_BINARY_NAME}"
    mv -f "$found_cli" "${INSTALL_DIR}/${CLI_BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${CORE_BINARY_NAME}" "${INSTALL_DIR}/${CLI_BINARY_NAME}"
    
    rm -f "$temp_file"; rm -rf "$extract_dir"
    
    log_install "$version"
    echo -e "${GREEN}--- EasyTier 安装/更新成功! ---${NC}"
    create_shortcut
    
    if [ "$need_restart" = true ]; then
        echo -e "${YELLOW}正在重启服务...${NC}"
        restart_service
    elif [ -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}检测到现有服务，如需重启请手动执行服务管理。${NC}"
    fi
}

create_default_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << 'EOF'
# === EasyTier 配置文件 (由脚本生成) ===
ipv4 = ""
dhcp = false
listeners = ["udp://0.0.0.0:11010", "tcp://0.0.0.0:11010", "wg://0.0.0.0:11011", "ws://0.0.0.0:11011/", "wss://0.0.0.0:11012/", "tcp://[::]:11010", "udp://[::]:11010"]
[network_identity]
network_name = ""
network_secret = ""
[flags]
default_protocol = "udp"
dev_name = ""
enable_encryption = true
enable_ipv6 = true
mtu = 1380
latency_first = true
enable_exit_node = false
no_tun = false
use_smoltcp = false
foreign_network_whitelist = "*"
disable_p2p = false
relay_all_peer_rpc = false
disable_udp_hole_punching = false
enableKcp_Proxy = true
EOF
    if [ $? -eq 0 ]; then
       echo "已成功创建默认配置文件: ${CONFIG_FILE}"; return 0
    else
       echo -e "${RED}错误: 创建配置文件失败!${NC}"; return 1
    fi
}

deploy_new_network() { 
    check_installed || return 1
    read -p "请输入网络名称 (回车自动生成): " network_name
    read -p "请输入网络密钥 (回车自动生成): " network_secret
    read -p "请输入此节点虚拟IP (留空则启用DHCP): " virtual_ip
    
    if [ -z "$network_name" ]; then
        network_name=$(generate_random_string 8)
        echo -e "${YELLOW}已自动生成网络名称: ${network_name}${NC}"
    fi
    
    if [ -z "$network_secret" ]; then
        network_secret=$(generate_random_string 16)
        echo -e "${YELLOW}已自动生成网络密钥: ${network_secret}${NC}"
    fi
    
    create_default_config || return 1
    
    set_toml_value "network_name" "\"$network_name\"" "$CONFIG_FILE"
    set_toml_value "network_secret" "\"$network_secret\"" "$CONFIG_FILE"
    
    if [ -z "$virtual_ip" ]; then
        echo -e "${YELLOW}未输入IP，将启用 DHCP 自动获取地址。${NC}"
        set_toml_value "dhcp" "true" "$CONFIG_FILE"
        set_toml_value "ipv4" "\"\"" "$CONFIG_FILE"
    else
        echo -e "${GREEN}已设置静态IP: ${virtual_ip}${NC}"
        set_toml_value "dhcp" "false" "$CONFIG_FILE"
        set_toml_value "ipv4" "\"$virtual_ip\"" "$CONFIG_FILE"
    fi

    create_service_file
    echo -e "${YELLOW}正在应用配置并启动服务...${NC}"
    start_service
    echo -e "${GREEN}--- 新网络部署并启动成功! ---${NC}"
    sleep 2; status_service
}

quick_deploy_network() {
    check_installed || return 1
    
    echo -e "${BLUE}=== 快速部署网络 (自动生成参数) ===${NC}"
    echo ""
    
    show_network_requirements || return 1
    
    network_name=$(generate_random_string 8)
    network_secret=$(generate_random_string 16)
    
    echo -e "${GREEN}正在生成网络配置...${NC}"
    echo "  网络名称: $network_name"
    echo "  网络密钥: $network_secret"
    
    create_default_config || return 1
    
    set_toml_value "network_name" "\"$network_name\"" "$CONFIG_FILE"
    set_toml_value "network_secret" "\"$network_secret\"" "$CONFIG_FILE"
    set_toml_value "dhcp" "true" "$CONFIG_FILE"
    set_toml_value "ipv4" "\"\"" "$CONFIG_FILE"

    create_service_file
    echo -e "${YELLOW}正在启动服务...${NC}"
    start_service
    
    sleep 3
    
    local local_ip
    local_ip=$(get_local_ip)
    local public_ip
    public_ip=$(get_public_ip)
    
    if [ -z "$public_ip" ]; then
        public_ip="<需要公网IP或端口映射>"
        echo -e "${YELLOW}⚠️  未检测到公网IP，可能需要配置端口映射${NC}"
    fi
    
    local peer_address
    if [ -n "$public_ip" ] && [ "$public_ip" != "<需要公网IP或端口映射>" ]; then
        peer_address="tcp://${public_ip}:11010"
    else
        peer_address="tcp://${local_ip}:11010"
    fi
    
    local token
    token=$(generate_network_token "$network_name" "$network_secret" "$peer_address")
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  🎉 网络部署成功！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}📋 网络信息 (可分享给其他节点加入):${NC}"
    echo ""
    echo -e "  ${YELLOW}完整 Token:${NC}"
    echo -e "  ${token}"
    echo ""
    echo -e "${BLUE}📌 分开使用:${NC}"
    echo "   网络名称: ${network_name}"
    echo "   网络密钥: ${network_secret}"
    echo "   节点地址: ${peer_address}"
    echo ""
    echo -e "${BLUE}📊 网络信息:${NC}"
    echo "   本地 IP: ${local_ip}"
    if [ -n "$public_ip" ] && [ "$public_ip" != "<需要公网IP或端口映射>" ]; then
        echo "   公网 IP: ${public_ip}"
    else
        echo -e "   公网 IP: ${YELLOW}未检测到 (NAT后面?)${NC}"
    fi
    echo ""
    show_port_setup_guide
}

join_existing_network() { 
    check_installed || return 1
    read -p "请输入网络名称 (或 Token): " network_name
    read -p "请输入网络密钥 (或留空如果使用Token): " network_secret
    read -p "请输入此节点虚拟IP (留空则启用DHCP): " virtual_ip
    
    echo ""
    peer_address=$(select_community_node)
    
    if [ "$peer_address" = "skip" ]; then
        echo -e "${YELLOW}跳过添加公共节点${NC}"
        peer_address=""
    elif [ -z "$peer_address" ]; then
        echo -e "${YELLOW}未选择节点，跳过添加${NC}"
    else
        echo -e "${GREEN}已选择节点: ${peer_address}${NC}"
    fi
    
    create_default_config || return 1

    set_toml_value "network_name" "\"$network_name\"" "$CONFIG_FILE"
    set_toml_value "network_secret" "\"$network_secret\"" "$CONFIG_FILE"
    
    if [ -n "$peer_address" ]; then
        echo -e "\n[[peer]]\n uri = \"${peer_address}\"" >> "$CONFIG_FILE"
    fi

    if [ -z "$virtual_ip" ]; then
        echo -e "${YELLOW}未输入IP，将启用 DHCP 自动获取地址。${NC}"
        set_toml_value "dhcp" "true" "$CONFIG_FILE"
        set_toml_value "ipv4" "\"\"" "$CONFIG_FILE"
    else
        echo -e "${GREEN}已设置静态IP: ${virtual_ip}${NC}"
        set_toml_value "dhcp" "false" "$CONFIG_FILE"
        set_toml_value "ipv4" "\"$virtual_ip\"" "$CONFIG_FILE"
    fi

    create_service_file
    echo -e "${YELLOW}正在应用配置并重启服务...${NC}"
    restart_service
    echo -e "${GREEN}--- 已加入网络并重启服务! ---${NC}"
    sleep 2; status_service
}

join_by_token() {
    check_installed || return 1
    
    echo -e "${BLUE}=== 通过 Token 加入网络 ===${NC}"
    echo ""
    echo -e "请输入 Token (例如: easytier://myvpn8k2d?secret=xxx&peer=tcp://1.2.3.4:11010)"
    read -p ": " token
    
    if [ -z "$token" ]; then
        echo -e "${RED}Token 不能为空${NC}"
        return 1
    fi
    
    if [[ ! "$token" =~ ^easytier:// ]]; then
        echo -e "${YELLOW}警告: Token 格式不是以 easytier:// 开头，将尝试作为网络名称处理${NC}"
        network_name="$token"
        read -p "请输入网络密钥: " network_secret
        read -p "请输入对端节点地址: " peer_address
        
        if [ -z "$network_secret" ] || [ -z "$peer_address" ]; then
            echo -e "${RED}网络密钥和对端节点地址都不能为空${NC}"
            return 1
        fi
    else
        local parsed
        parsed=$(parse_network_token "$token")
        if [ $? -ne 0 ] || [ -z "$parsed" ]; then
            echo -e "${RED}Token 格式解析失败${NC}"
            return 1
        fi
        
        network_name=$(echo "$parsed" | cut -d'|' -f1)
        network_secret=$(echo "$parsed" | cut -d'|' -f2)
        peer_address=$(echo "$parsed" | cut -d'|' -f3)
        
        echo -e "${GREEN}解析成功!${NC}"
        echo "  网络名称: $network_name"
        echo "  网络密钥: $network_secret"
        echo "  对端地址: $peer_address"
    fi
    
    read -p "请输入此节点虚拟IP (留空则启用DHCP): " virtual_ip
    
    create_default_config || return 1

    set_toml_value "network_name" "\"$network_name\"" "$CONFIG_FILE"
    set_toml_value "network_secret" "\"$network_secret\"" "$CONFIG_FILE"
    echo -e "\n[[peer]]\n uri = \"${peer_address}\"" >> "$CONFIG_FILE"

    if [ -z "$virtual_ip" ]; then
        echo -e "${YELLOW}未输入IP，将启用 DHCP 自动获取地址。${NC}"
        set_toml_value "dhcp" "true" "$CONFIG_FILE"
        set_toml_value "ipv4" "\"\"" "$CONFIG_FILE"
    else
        echo -e "${GREEN}已设置静态IP: ${virtual_ip}${NC}"
        set_toml_value "dhcp" "false" "$CONFIG_FILE"
        set_toml_value "ipv4" "\"$virtual_ip\"" "$CONFIG_FILE"
    fi

    create_service_file
    echo -e "${YELLOW}正在应用配置并重启服务...${NC}"
    restart_service
    echo -e "${GREEN}--- 已通过 Token 加入网络! ---${NC}"
    sleep 2; status_service
}

manage_service_menu() {
    check_installed || return 1
    
    while true; do
        echo "--- 服务管理菜单 ---"; echo " 1. 启动服务"; echo " 2. 停止服务"; echo " 3. 重启服务"; echo " 4. 查看状态"; echo " 5. 设为开机自启"; echo " 6. 取消开机自启"; echo " 7. 查看实时日志"; echo " 0. 返回主菜单"; echo "--------------------"
        read -p "请选择操作 [0-7]: " sub_choice
        case $sub_choice in
            1) start_service && echo -e "${GREEN}服务已启动。${NC}"; break ;;
            2) stop_service && echo -e "${GREEN}服务已停止。${NC}"; break ;;
            3) restart_service && echo -e "${GREEN}服务已重启。${NC}"; break ;;
            4) status_service; break ;;
            5) enable_service && echo -e "${GREEN}已设置开机自启。${NC}"; break ;;
            6) disable_service && echo -e "${GREEN}已取消开机自启。${NC}"; break ;;
            7) log_service; break ;;
            0) break ;;
            *) echo -e "${RED}无效输入，请重试。${NC}" ;;
        esac; done
}

uninstall_easytier() {
    read -p "警告: 此操作将停止服务并删除所有相关文件。确定要卸载吗? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then echo "操作已取消。"; return; fi
    
    echo "正在停止并禁用服务..."
    if [ -f "$SERVICE_FILE" ]; then stop_service >/dev/null 2>&1; disable_service >/dev/null 2>&1; fi
    
    echo "正在删除文件..."
    rm -f "${SERVICE_FILE}" "${INSTALL_DIR}/${CORE_BINARY_NAME}" "${INSTALL_DIR}/${CLI_BINARY_NAME}"
    rm -rf "${CONFIG_DIR}"; remove_shortcut
    
    echo -e "${GREEN}EasyTier 已成功卸载。${NC}"
}

check_update() {
    echo -e "${GREEN}--- 检查 EasyTier 更新 ---${NC}"
    
    echo "正在获取最新版本信息..."
    local latest_info
    latest_info=$(curl -sL "https://api.github.com/repos/EasyTier/EasyTier/releases/latest")
    if [ -z "$latest_info" ]; then
        echo -e "${RED}错误: 无法从 GitHub API 获取版本信息。${NC}"
        return 1
    fi
    
    local latest_version
    latest_version=$(echo "$latest_info" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    echo -e "最新版本: ${GREEN}${latest_version}${NC}"
    
    if [ ! -f "${INSTALL_DIR}/${CORE_BINARY_NAME}" ]; then
        echo -e "${YELLOW}EasyTier 未安装。要安装最新版本吗? (y/n): ${NC}"
        read -p "请选择: " install_choice
        if [ "$install_choice" = "y" ] || [ "$install_choice" = "Y" ]; then
            install_easytier
        fi
        return
    fi
    
    local current_version
    current_version=$(${INSTALL_DIR}/${CORE_BINARY_NAME} --version 2>/dev/null | head -1)
    if [ -z "$current_version" ]; then
        current_version="未知"
    else
        current_version=$(echo "$current_version" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -z "$current_version" ]; then
            current_version=$(${INSTALL_DIR}/${CORE_BINARY_NAME} --version 2>/dev/null | head -1 | tr -d '\n')
        fi
    fi
    
    echo -e "当前版本: ${YELLOW}${current_version}${NC}"
    
    if [ "$current_version" = "$latest_version" ]; then
        echo -e "${GREEN}✓ 当前已是最新版本!${NC}"
    else
        echo -e "${YELLOW}有可用更新!${NC}"
        read -p "是否现在更新? (y/n): " update_choice
        if [ "$update_choice" = "y" ] || [ "$update_choice" = "Y" ]; then
            install_easytier
        fi
    fi
}

# --- 笔记模块配置 ---
NOTES_DIR="$HOME/.easytier"
NOTES_FILE="${NOTES_DIR}/notes.md"
INSTALL_LOG="${NOTES_DIR}/install.log"

init_notes() {
    mkdir -p "$NOTES_DIR"
    if [ ! -f "$NOTES_FILE" ]; then
        cat > "$NOTES_FILE" << 'EOF'
# EasyTier 笔记 (OpenWrt)

## 快速开始
- 安装：选项 1
- 检查更新：选项 2

## 常见问题

### Q1: 连接不上怎么办？
1. 检查服务是否运行：`/etc/init.d/easytier status`
2. 检查端口是否开放：11010, 11011, 11012
3. 检查防火墙规则

### Q2: OpenWrt 空间不足？
- 建议将日志输出到 /tmp 或关闭详细日志

### Q3: 如何查看日志？
`logread -f -e easytier-core`

## 节点记录
- 节点地址：
- 网络名称：
- 网络密钥：

---
*此笔记由 EasyTier 管理脚本自动生成*
EOF
    fi
}

view_notes() {
    init_notes
    echo -e "${GREEN}--- 笔记内容 ---${NC}"
    cat "$NOTES_FILE"
    echo ""
    echo -e "笔记文件位置: ${YELLOW}${NOTES_FILE}${NC}"
}

edit_notes() {
    init_notes
    if command -v vi >/dev/null 2>&1; then
        vi "$NOTES_FILE"
    elif command -v nano >/dev/null 2>&1; then
        nano "$NOTES_FILE"
    else
        echo "请使用其他编辑器打开: $NOTES_FILE"
    fi
}

log_install() {
    init_notes
    local version="$1"
    local date=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$date] 安装版本: $version" >> "$INSTALL_LOG"
}

# --- 主菜单 ---
main() {
    check_root; check_arch; check_dependencies
    
    while true; do
        clear
        echo "======================================================="; echo -e "   ${GREEN}EasyTier OpenWrt 专属管理脚本 v6.4${NC}"; echo -e "   (架构: aarch64, 自动创建 'et' 快捷命令)"; echo "======================================================="
        echo " 1. 安装或更新 EasyTier"; echo " 2. 检查更新"; echo " 3. 部署新网络 (首个节点)"; echo " 4. 加入现有网络"; echo " 5. 快速部署 (自动生成参数+Token)"; echo " 6. 通过Token加入网络"; echo "-------------------------------------------------------"
        echo " 7. 管理服务 (启停/状态/日志)"; echo " 8. 查看配置文件"; echo " 9. 查看网络节点 (easytier-cli)"; echo "-------------------------------------------------------"
        echo "10. 卸载 EasyTier"; echo "11. 查看笔记/FAQ"; echo "12. 编辑笔记"; echo " 0. 退出脚本"; echo "======================================================="
        read -p "请输入选项 [0-12]: " choice
        
        echo
        case $choice in
            1) install_easytier ;;
            2) check_update ;;
            3) deploy_new_network ;;
            4) join_existing_network ;;
            5) quick_deploy_network ;;
            6) join_by_token ;;
            7) manage_service_menu ;;
            8) if check_installed && [ -f "$CONFIG_FILE" ]; then cat "$CONFIG_FILE"; else echo -e "${YELLOW}配置文件不存在或 EasyTier 未安装。${NC}"; fi ;;
            9) if check_installed; then ${INSTALL_DIR}/${CLI_BINARY_NAME} peer; fi ;;
            10) uninstall_easytier ;;
            11) view_notes ;;
            12) edit_notes ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效输入${NC}" ;;
        esac
        echo -e "\n${YELLOW}按任意键返回主菜单...${NC}"; read -n 1 -s -r
    done
}

main "$@"
