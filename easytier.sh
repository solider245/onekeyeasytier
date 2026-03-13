#!/bin/bash

# --- 脚本配置 ---
GITHUB_PROXY="ghfast.top"

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
	read -p "请输入网络名称: " network_name
	read -p "请输入网络密钥: " network_secret
	read -p "请输入此虚拟IP (回车则启用DHCP): " virtual_ip
	
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

join_existing_network() { 
	check_installed || return 1
	read -p "请输入网络名称: " network_name
	read -p "请输入网络密钥: " network_secret
	read -p "请输入此节点虚拟IP (留空则启用DHCP): " virtual_ip
	read -p "请输入一个对端节点地址 (回车默认为 tcp://public.easytier.top:11010): " peer_address
	if [ -z "$peer_address" ]; then
		peer_address="tcp://public.easytier.top:11010"
		echo -e "${YELLOW}使用默认对端节点: ${peer_address}${NC}"
	fi

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

	# [MODIFIED] 自动启用并重启服务
	echo -e "${YELLOW}正在设置开机自启并启动服务...${NC}"
	enable_service
	restart_service
	echo -e "${GREEN}--- 已加入网络，服务已启动并设为开机自启! ---${NC}"

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
		echo "-------------------------------------------------------"
		echo " 5. 管理EasyTier服务状态"
		echo " 6. 查看EasyTier配置文件"
		echo " 7. 查看EasyTier网络节点"
		echo "-------------------------------------------------------"
		echo " 8. 卸载 EasyTier"
		echo " 9. 查看笔记/FAQ"
		echo "10. 编辑笔记"
		echo " 0. 退出脚本"
		echo "======================================================="
		read -p "请输入选项 [0-10]: " choice
		
		echo
		
		case $choice in
			1) install_easytier ;;
			2) check_update ;;
			3) deploy_new_network ;;
			4) join_existing_network ;;
			5) manage_service ;;
			6) if check_installed && [ -f "$CONFIG_FILE" ]; then cat "$CONFIG_FILE"; else echo -e "${YELLOW}配置文件不存在或未安装。${NC}"; fi ;;
			7) if check_installed; then ${INSTALL_DIR}/${CLI_BINARY_NAME} peer; fi ;;
			8) uninstall_easytier ;;
			9) view_notes ;;
			10) edit_notes ;;
			0) exit 0 ;;
			*) echo -e "${RED}无效输入${NC}" ;;
		esac
		echo -e "\n${YELLOW}按任意键返回主菜单...${NC}"; read -n 1 -s -r
	done
}

# 将 set_toml_value 函数定义移到 main 函数内部，以覆盖全局定义
main "$@"
