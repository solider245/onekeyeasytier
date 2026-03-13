#!/bin/bash

# --- 脚本配置 ---
GITHUB_PROXY="gh.565600.xyz"

# 颜色定义
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# --- 平台无关路径和文件名 ---
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/easytier"
CONFIG_FILE="${CONFIG_DIR}/easytier.toml"
CORE_BINARY_NAME="easytier-core"
CLI_BINARY_NAME="easytier-cli"
ALIAS_PATH="/usr/local/bin/et"

# --- 平台特定变量 (将在 main 函数中设置) ---
OS_TYPE=""
SERVICE_FILE=""
SERVICE_LABEL="com.easytier.core"
SERVICE_NAME="easytier"
LOG_FILE="/var/log/easytier.log"

# 原始下载地址
GITHUB_API_URL="https://api.github.com/repos/EasyTier/EasyTier/releases/latest"

# --- 笔记模块配置 ---
NOTES_DIR="$HOME/.easytier"
NOTES_FILE="${NOTES_DIR}/notes.md"
INSTALL_LOG="${NOTES_DIR}/install.log"

# --- 辅助函数 ---
check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo -e "${RED}错误: 此脚本必须以 root 或 sudo 权限运行。${NC}"; exit 1
	fi
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

check_port_available() {
	local port=$1
	if command -v ss >/dev/null 2>&1; then
		if ss -tuln 2>/dev/null | grep -q ":${port} "; then
			return 1
		fi
	elif command -v netstat >/dev/null 2>&1; then
		if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
			return 1
		fi
	fi
	return 0
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
	echo "   • 如果使用 WireGuard: UDP 11011"
	echo "   • 如果使用 WebSocket: TCP 11011/11012"
	echo ""
	echo -e "${BLUE}2. 公网访问要求:${NC}"
	echo "   • 作为种子节点，需要公网 IP 或端口映射"
	echo "   • 如果在 NAT 后面，需要做端口映射 (UDP/TCP 11010-11012)"
	echo "   • 或者使用穿透服务 (如 frp, ngrok 等)"
	echo ""
	echo -e "${BLUE}3. 局域网模式:${NC}"
	echo "   • 如果只在内网使用，可以跳过公网要求"
	echo "   • 其他节点直接用内网 IP 连接即可"
	echo ""
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	read -p "我已了解上述要求，继续部署 (y/n): " confirm
	if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
		echo -e "${RED}操作已取消。${NC}"
		return 1
	fi
	return 0
}

show_port_setup_guide() {
	local peer_address="$1"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${GREEN}  📝 端口配置说明${NC}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	echo -e "${BLUE}已开放的端口:${NC}"
	echo "   • UDP 11010 - EasyTier 通信"
	echo "   • TCP 11010 - EasyTier 通信"
	echo "   • TCP 11011 - WireGuard / KCP"
	echo "   • TCP 11012 - WSS (WebSocket Secure)"
	echo ""
	echo -e "${BLUE}防火墙命令参考:${NC}"
	
	if [[ "$OS_TYPE" == "linux" ]]; then
		echo "   # Ubuntu/Debian"
		echo "   sudo ufw allow 11010/udp"
		echo "   sudo ufw allow 11010/tcp"
		echo "   sudo ufw allow 11011/tcp"
		echo "   sudo ufw allow 11012/tcp"
		echo ""
		echo "   # CentOS/RHEL"
		echo "   sudo firewall-cmd --permanent --add-port=11010/udp"
		echo "   sudo firewall-cmd --permanent --add-port=11010/tcp"
		echo "   sudo firewall-cmd --permanent --add-port=11011/tcp"
		echo "   sudo firewall-cmd --permanent --add-port=11012/tcp"
		echo "   sudo firewall-cmd --reload"
		echo ""
		echo "   # iptables"
		echo "   sudo iptables -A INPUT -p udp --dport 11010 -j ACCEPT"
		echo "   sudo iptables -A INPUT -p tcp --dport 11010 -j ACCEPT"
		echo "   sudo iptables -A INPUT -p tcp --dport 11011 -j ACCEPT"
		echo "   sudo iptables -A INPUT -p tcp --dport 11012 -j ACCEPT"
	elif [[ "$OS_TYPE" == "macos" ]]; then
		echo "   # macOS (编辑 /etc/pf.conf 或使用 GUI)"
		echo "   sudo launchctl load /System/Library/LaunchDaemons/com.apple.pfctl.plist"
		echo "   # 建议通过 System Preferences > Security & Privacy > Firewall"
	fi
	
	echo ""
	echo -e "${YELLOW}如需从外网访问，请确保路由器也做了端口映射！${NC}"
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

check_dependencies() {
	local missing_deps=()
	for cmd in curl jq unzip; do
		if ! command -v "$cmd" &> /dev/null; then missing_deps+=("$cmd"); fi
	done
	if [ ${#missing_deps[@]} -gt 0 ]; then
		echo -e "${YELLOW}检测到缺失的依赖: ${missing_deps[*]}${NC}"
		if [[ "$OS_TYPE" == "linux" || "$OS_TYPE" == "alpine"  ]]; then
			read -p "是否尝试自动安装? (y/n): " choice
			if [[ "$choice" != "y" && "$choice" != "Y" ]]; then echo -e "${RED}操作中止。${NC}"; exit 1; fi
			if [[ "$OS_TYPE" == "linux" ]]; then
				if command -v apt-get &>/dev/null; then apt-get update && apt-get install -y "${missing_deps[@]}";
				elif command -v yum &>/dev/null; then yum install -y "${missing_deps[@]}";
				elif command -v dnf &>/dev/null; then dnf install -y "${missing_deps[@]}";
				else echo -e "${RED}无法确定包管理器。请手动安装。${NC}"; exit 1; fi
			elif [[ "$OS_TYPE" == "alpine" ]]; then apk add --no-cache "${missing_deps[@]}"; fi
		elif [[ "$OS_TYPE" == "macos" ]]; then
			echo -e "${YELLOW}请使用 Homebrew 手动安装: brew install ${missing_deps[*]}${NC}"; exit 1
		fi
		for cmd in "${missing_deps[@]}"; do
			 if ! command -v "$cmd" &> /dev/null; then
				echo -e "${RED}依赖 '$cmd' 安装失败。请手动安装后重试。${NC}"; exit 1
			 fi
		done
	fi
}

get_arch() {
	case "$(uname -m)" in
		x86_64|amd64) echo "x86_64" ;; aarch64|arm64) echo "aarch64" ;;
		*) echo -e "${RED}错误: 不支持的架构: $(uname -m)${NC}"; exit 1 ;;
	esac
}

check_installed() {
	if [ ! -f "${INSTALL_DIR}/${CORE_BINARY_NAME}" ]; then
		echo -e "${YELLOW}EasyTier 尚未安装。请先选择选项 1。${NC}"; return 1
	fi; return 0
}

set_toml_value() {
	# This sed command works on both Linux and macOS
	sed -i.bak "s|^#* *${1} *=.*|${1} = ${2}|" "$3" && rm "${3}.bak"
}


# --- 平台相关的服务管理功能 ---

create_service_file() {
    if [[ "$OS_TYPE" == "macos" || "$OS_TYPE" == "alpine" ]]; then
        touch "$LOG_FILE"
        chown root:root "$LOG_FILE" &>/dev/null
        chmod 644 "$LOG_FILE"
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        cat > "${SERVICE_FILE}" << EOL
[Unit]
Description=EasyTier Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/${CORE_BINARY_NAME} -c ${CONFIG_FILE}
# 使用 "always" 策略确保进程无论如何退出都会被重启，提供最强的守护
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL
    elif [[ "$OS_TYPE" == "alpine" ]]; then
        # 使用 OpenRC 的 supervise-daemon 实现真正的进程守护
        cat > "${SERVICE_FILE}" << EOL
#!/sbin/openrc-run
description="EasyTier Service with Supervisor"
supervisor=supervise-daemon
command="${INSTALL_DIR}/${CORE_BINARY_NAME}"
command_args="-c ${CONFIG_FILE}"
command_user="root"
pidfile="/var/run/${SERVICE_NAME}.pid"
output_log="${LOG_FILE}"
error_log="${LOG_FILE}"
depend() {
	need net
	after net
}
EOL
        chmod +x "${SERVICE_FILE}";
    elif [[ "$OS_TYPE" == "macos" ]]; then
        cat > "${SERVICE_FILE}" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/${CORE_BINARY_NAME}</string>
        <string>-c</string>
        <string>${CONFIG_FILE}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
</dict>
</plist>
EOL
    fi
    echo -e "${GREEN}服务文件创建/更新成功: ${SERVICE_FILE}${NC}"
}

reload_service_daemon() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl daemon-reload; fi; }
start_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl start "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" start; elif [[ "$OS_TYPE" == "macos" ]]; then launchctl load "${SERVICE_FILE}" &>/dev/null; fi; }
stop_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl stop "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" stop; elif [[ "$OS_TYPE" == "macos" ]]; then launchctl unload "${SERVICE_FILE}" &>/dev/null; fi; }
restart_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl restart "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" restart; elif [[ "$OS_TYPE" == "macos" ]]; then stop_service; sleep 1; start_service; fi; }
enable_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl enable "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-update add "${SERVICE_NAME}" default; elif [[ "$OS_TYPE" == "macos" ]]; then start_service; fi; echo -e "${GREEN}服务已设为开机自启。${NC}"; }
disable_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl disable "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-update del "${SERVICE_NAME}" default; elif [[ "$OS_TYPE" == "macos" ]]; then stop_service; fi; echo -e "${YELLOW}服务已取消开机自启。${NC}"; }
status_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl status "${SERVICE_NAME}" --no-pager -l; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" status; elif [[ "$OS_TYPE" == "macos" ]]; then if launchctl list | grep -q "${SERVICE_LABEL}"; then echo -e "${GREEN}EasyTier 服务 (${SERVICE_LABEL}) 正在运行。${NC}"; ps aux | grep "${CORE_BINARY_NAME}" | grep -v grep; else echo -e "${YELLOW}EasyTier 服务 (${SERVICE_LABEL}) 已停止。${NC}"; fi; fi; }
log_service() { if [[ "$OS_TYPE" == "linux" ]]; then journalctl -u "${SERVICE_NAME}" -f --no-pager; elif [[ "$OS_TYPE" == "alpine" || "$OS_TYPE" == "macos" ]]; then echo "正在显示日志文件: ${LOG_FILE}"; tail -f "${LOG_FILE}"; fi; }

# --- 主功能函数 ---
create_shortcut() {
	local SCRIPT_PATH; SCRIPT_PATH=$(realpath "$0" 2>/dev/null || (cd "$(dirname "$0")" && echo "$(pwd)/$(basename "$0")"))
	if [ -L "${ALIAS_PATH}" ] && [ "$(readlink "${ALIAS_PATH}")" = "${SCRIPT_PATH}" ]; then return 0; fi
	echo -e "${YELLOW}正在创建“et”快捷命令...${NC}"
	chmod +x "${SCRIPT_PATH}"
	ln -sf "${SCRIPT_PATH}" "${ALIAS_PATH}"
	if [ $? -eq 0 ]; then echo -e "${GREEN}成功! 现在你可以在终端中直接输入“et”来运行此脚本。${NC}"; else echo -e "${RED}创建快捷命令失败。请检查权限或 /usr/local/bin 是否在你的 PATH 中。${NC}"; fi
}

remove_shortcut() {
	if [ -L "${ALIAS_PATH}" ]; then rm -f "${ALIAS_PATH}" &>/dev/null; fi
}

install_easytier() {
	echo -e "${GREEN}--- 开始安装或更新 EasyTier ---${NC}"
	
	local need_restart=false
	
	# 检测是否有进程在运行
	if pgrep -x "easytier-core" > /dev/null 2>&1 || pgrep -f "easytier-core" > /dev/null 2>&1; then
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

	local os_identifier="linux"; if [[ "$OS_TYPE" == "macos" ]]; then os_identifier="macos"; fi
	local arch; arch=$(get_arch)

	echo "请选择版本类型:"
	echo "  1. 稳定版 (Stable) - 推荐"
	echo "  2. 预发布版 (Pre-release) - 最新功能，可能不稳定"
	read -p "请选择 [1-2](默认1): " version_choice
	if [ "$version_choice" = "2" ]; then
		echo "1. 获取预发布版本信息..."
		local releases_info; releases_info=$(curl -sL "https://api.github.com/repos/EasyTier/EasyTier/releases")
		if [ -z "$releases_info" ] || ! echo "$releases_info" | jq . >/dev/null 2>&1; then echo -e "${RED}错误: 无法从 GitHub API 获取版本信息。${NC}"; return 1; fi
		local latest_info; latest_info=$(echo "$releases_info" | jq -r '.[] | select(.prerelease == true) | .' | head -1)
		if [ -z "$latest_info" ]; then echo -e "${RED}错误: 未找到预发布版本。${NC}"; return 1; fi
	else
		echo "1. 获取稳定版本信息..."
		local latest_info; latest_info=$(curl -sL "$GITHUB_API_URL")
		if [ -z "$latest_info" ] || ! echo "$latest_info" | jq . >/dev/null 2>&1; then echo -e "${RED}错误: 无法从 GitHub API 获取版本信息。${NC}"; return 1; fi
	fi
	
	local search_prefix="easytier-${os_identifier}-${arch}"
	local asset_json; asset_json=$(echo "$latest_info" | jq ".assets[] | select(.name | startswith(\"${search_prefix}\") and endswith(\".zip\"))")
	if [ -z "$asset_json" ]; then echo -e "${RED}错误: 未能找到适用于 ${OS_TYPE}(${arch}) 的包。${NC}"; return 1; fi
	local download_url; download_url=$(echo "$asset_json" | jq -r '.browser_download_url')
	local actual_filename; actual_filename=$(echo "$asset_json" | jq -r '.name')
	local version; version=$(echo "$latest_info" | jq -r ".tag_name")
	echo "检测到版本: ${version}, 架构: ${arch}, 文件: ${actual_filename}"
	if [ -n "$GITHUB_PROXY" ]; then download_url="https://$GITHUB_PROXY/$download_url"; echo -e "${YELLOW}2. 使用代理下载: ${download_url}${NC}"; else echo "2. 直接下载: ${download_url}"; fi
	local temp_file; temp_file=$(mktemp)
	curl -L --progress-bar -o "$temp_file" "$download_url" || { echo -e "${RED}下载失败!${NC}"; rm -f "$temp_file"; return 1; }
	echo "3. 解压并安装..."
	local unzip_dir_name="easytier-${os_identifier}-${arch}"
	unzip -o "$temp_file" -d /tmp/ > /dev/null || { echo -e "${RED}解压失败!${NC}"; rm -f "$temp_file"; return 1; }
	local extracted_core="/tmp/${unzip_dir_name}/${CORE_BINARY_NAME}"; local extracted_cli="/tmp/${unzip_dir_name}/${CLI_BINARY_NAME}"
	if [ ! -f "$extracted_core" ] || [ ! -f "$extracted_cli" ]; then echo -e "${RED}错误: 在解压目录中未找到核心文件。${NC}"; rm -f "$temp_file"; rm -rf "/tmp/${unzip_dir_name}"; return 1; fi
	mkdir -p "$INSTALL_DIR"
	mv -f "$extracted_core" "${INSTALL_DIR}/${CORE_BINARY_NAME}"; mv -f "$extracted_cli" "${INSTALL_DIR}/${CLI_BINARY_NAME}"
	chmod +x "${INSTALL_DIR}/${CORE_BINARY_NAME}" "${INSTALL_DIR}/${CLI_BINARY_NAME}"
	rm -f "$temp_file"; rm -rf "/tmp/${unzip_dir_name}"
	
	log_install "$version"
	echo -e "${GREEN}--- EasyTier ${version} 安装/更新成功! ---${NC}"
	create_shortcut
	
	if [ "$need_restart" = true ]; then
		echo -e "${YELLOW}正在重启服务...${NC}"; restart_service;
	elif [ -f "$SERVICE_FILE" ]; then
		echo -e "${YELLOW}检测到现有服务，如需重启请手动执行服务管理。${NC}"
	fi
}

create_default_config() { mkdir -p "$CONFIG_DIR"; cat > "$CONFIG_FILE" << 'EOF'
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
	if [ $? -eq 0 ]; then echo "已成功创建默认配置文件: ${CONFIG_FILE}"; return 0;
	else echo -e "${RED}错误: 创建配置文件失败!${NC}"; return 1; fi; }

deploy_new_network() { 
	check_installed || return 1
	read -p "请输入网络名称 (回车自动生成): " network_name
	read -p "请输入网络密钥 (回车自动生成): " network_secret
	read -p "请输入此虚拟IP (回车则启用DHCP): " virtual_ip
	
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
	reload_service_daemon
	
	# [MODIFIED] 自动启用并重启服务
	echo -e "${YELLOW}正在设置开机自启并启动服务...${NC}"
	enable_service
	restart_service
	echo -e "${GREEN}--- 新网络部署成功，服务已启动并设为开机自启! ---${NC}"
	
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
	reload_service_daemon
	
	echo -e "${YELLOW}正在启动服务...${NC}"
	enable_service
	restart_service
	
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
	show_port_setup_guide "$peer_address"
}

join_existing_network() { 
	check_installed || return 1
	read -p "请输入网络名称 (或 Token): " network_name
	read -p "请输入网络密钥 (或留空如果使用Token): " network_secret
	read -p "请输入此节点虚拟IP (留空则启用DHCP): " virtual_ip
	read -p "请输入公共节点地址 (留空则不添加, 示例: tcp://124.221.120.232:11010): " peer_address

	create_default_config || return 1

	set_toml_value "network_name" "\"$network_name\"" "$CONFIG_FILE"
	set_toml_value "network_secret" "\"$network_secret\"" "$CONFIG_FILE"
	
	if [ -n "$peer_address" ]; then
		echo -e "\n[[peer]]\nuri = \"${peer_address}\"" >> "$CONFIG_FILE"
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
	reload_service_daemon

	# [MODIFIED] 自动启用并重启服务
	echo -e "${YELLOW}正在设置开机自启并启动服务...${NC}"
	enable_service
	restart_service
	echo -e "${GREEN}--- 已加入网络，服务已启动并设为开机自启! ---${NC}"

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
	echo -e "\n[[peer]]\nuri = \"${peer_address}\"" >> "$CONFIG_FILE"

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
	reload_service_daemon

	echo -e "${YELLOW}正在设置开机自启并启动服务...${NC}"
	enable_service
	restart_service
	echo -e "${GREEN}--- 已通过 Token 加入网络，服务已启动! ---${NC}"

	sleep 2; status_service
}


manage_service() { check_installed || return 1; PS3="请选择操作: "; options=("启动" "停止" "重启" "状态" "设为开机自启" "取消开机自启" "查看日志" "返回"); select opt in "${options[@]}"; do case $opt in "启动") start_service && echo -e "${GREEN}服务已启动。${NC}"; break ;; "停止") stop_service && echo -e "${GREEN}服务已停止。${NC}"; break ;; "重启") restart_service && echo -e "${GREEN}服务已重启。${NC}"; break ;; "状态") status_service; break ;; "设为开机自启") enable_service; break ;; "取消开机自启") disable_service; break ;; "查看日志") log_service; break ;; "返回") break ;; esac; done; }

check_update() {
	echo -e "${GREEN}--- 检查 EasyTier 更新 ---${NC}"
	
	# 获取 GitHub 最新稳定版本
	echo "正在获取最新版本信息..."
	local latest_info; latest_info=$(curl -sL "$GITHUB_API_URL")
	if [ -z "$latest_info" ] || ! echo "$latest_info" | jq . >/dev/null 2>&1; then
		echo -e "${RED}错误: 无法从 GitHub API 获取版本信息。${NC}"
		return 1
	fi
	
	local latest_version; latest_version=$(echo "$latest_info" | jq -r ".tag_name")
	echo -e "最新版本: ${GREEN}${latest_version}${NC}"
	
	# 检查是否已安装
	if ! check_installed >/dev/null 2>&1; then
		echo -e "${YELLOW}EasyTier 未安装。要安装最新版本吗? (y/n): ${NC}"
		read -p "请选择: " install_choice
		if [ "$install_choice" = "y" ] || [ "$install_choice" = "Y" ]; then
			install_easytier
		fi
		return
	fi
	
	# 获取当前安装版本
	local current_version
	current_version=$(${INSTALL_DIR}/${CORE_BINARY_NAME} --version 2>/dev/null | head -1)
	if [ -z "$current_version" ]; then
		current_version="未知"
	else
		# 尝试提取版本号
		current_version=$(echo "$current_version" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
		if [ -z "$current_version" ]; then
			current_version=$(${INSTALL_DIR}/${CORE_BINARY_NAME} --version 2>/dev/null | head -1 | tr -d '\n')
		fi
	fi
	
	echo -e "当前版本: ${YELLOW}${current_version}${NC}"
	
	# 对比版本
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

uninstall_easytier() { read -p "警告: 此操作将停止服务并删除所有相关文件。确定要卸载吗? (y/n): " confirm; if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then echo "操作已取消。"; return; fi; echo "正在停止并禁用服务..."; stop_service &> /dev/null; disable_service &> /dev/null; echo "正在删除文件..."; rm -f "${SERVICE_FILE}" "${INSTALL_DIR}/${CORE_BINARY_NAME}" "${INSTALL_DIR}/${CLI_BINARY_NAME}"; rm -rf "${CONFIG_DIR}"; remove_shortcut; if [[ "$OS_TYPE" == "linux" ]]; then systemctl daemon-reload; fi; if [[ "$OS_TYPE" == "macos" || "$OS_TYPE" == "alpine" ]]; then rm -f "$LOG_FILE"; fi; echo -e "${GREEN}EasyTier 已成功卸载。${NC}"; }

# --- 笔记功能 ---
init_notes() {
    mkdir -p "$NOTES_DIR"
    if [ ! -f "$NOTES_FILE" ]; then
        cat > "$NOTES_FILE" << 'EOF'
# EasyTier 笔记

## 快速开始
- 安装：选项 1
- 检查更新：选项 2
- 部署网络：选项 3

## 常见问题

### Q1: 连接不上怎么办？
1. 检查服务是否运行：`systemctl status easytier`
2. 检查端口是否开放：11010, 11011, 11012
3. 检查防火墙规则

### Q2: 速度很慢怎么办？
1. 尝试使用代理版本
2. 检查网络延迟
3. 尝试不同的协议（UDP/TCP）

### Q3: 如何查看日志？
- Linux: `journalctl -u easytier -f`
- macOS: `tail -f /var/log/easytier.log`

## 节点记录
在此记录你的节点信息：
- 节点地址：
- 网络名称：
- 网络密钥：

## 配置心得
在这里记录你的配置经验...

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
    echo "请选择编辑器:"
    echo "  1. nano"
    echo "  2. vim"  
    echo "  3. 直接打开文件位置"
    read -p "请选择 [1-3]: " editor_choice
    case $editor_choice in
        1)
            if command -v nano >/dev/null 2>&1; then
                nano "$NOTES_FILE"
            else
                echo -e "${RED}nano 未安装，请先安装或选择其他编辑器${NC}"
            fi
            ;;
        2)
            if command -v vim >/dev/null 2>&1; then
                vim "$NOTES_FILE"
            else
                echo -e "${RED}vim 未安装，请先安装或选择其他编辑器${NC}"
            fi
            ;;
        3)
            if [[ "$OS_TYPE" == "macos" ]]; then
                open "$NOTES_FILE"
            elif [[ "$OS_TYPE" == "linux" ]]; then
                xdg-open "$NOTES_FILE" 2>/dev/null || echo "请手动打开: $NOTES_FILE"
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

log_install() {
    init_notes
    local version="$1"
    local date=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$date] 安装版本: $version" >> "$INSTALL_LOG"
}

# --- 主菜单 ---
main() {
	# 修复 set_toml_value 与旧版不兼容的问题
	set_toml_value() {
		sed -i.bak "s|^#* *${1} *=.*|${1} = ${2}|" "$3" && rm "${3}.bak"
	}

	case "$(uname)" in
		Linux) if [ -f /etc/alpine-release ]; then OS_TYPE="alpine"; SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"; else OS_TYPE="linux"; SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"; fi ;;
		Darwin) OS_TYPE="macos"; SERVICE_FILE="/Library/LaunchDaemons/${SERVICE_LABEL}.plist"; ;;
		*) echo -e "${RED}错误: 不支持的操作系统: $(uname)${NC}"; exit 1 ;;
	esac
	check_root; check_dependencies
	while true; do
		clear
		echo "======================================================="
		echo -e "   ${GREEN}EasyTier 跨平台部署 Debian/Ubuntu/Mac/Alpine${NC}"
		echo "======================================================="
		echo " 1. 安装或更新 EasyTier"
		echo " 2. 检查更新"
		echo " 3. 部署服务器 (服务节点)"
		echo " 4. 加入EasyTier组网网络"
		echo " 5. 快速部署 (自动生成参数+Token)"
		echo " 6. 通过Token加入网络"
		echo "-------------------------------------------------------"
		echo " 7. 管理EasyTier服务状态"
		echo " 8. 查看EasyTier配置文件"
		echo " 9. 查看EasyTier网络节点"
		echo "-------------------------------------------------------"
		echo "10. 卸载 EasyTier"
		echo "11. 查看笔记/FAQ"
		echo "12. 编辑笔记"
		echo " 0. 退出脚本"
		echo "======================================================="
		read -p "请输入选项 [0-12]: " choice
		
		echo
		
		case $choice in
			1) install_easytier ;;
			2) check_update ;;
			3) deploy_new_network ;;
			4) join_existing_network ;;
			5) quick_deploy_network ;;
			6) join_by_token ;;
			7) manage_service ;;
			8) if check_installed && [ -f "$CONFIG_FILE" ]; then cat "$CONFIG_FILE"; else echo -e "${YELLOW}配置文件不存在或未安装。${NC}"; fi ;;
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

# 将 set_toml_value 函数定义移到 main 函数内部，以覆盖全局定义
main "$@"
