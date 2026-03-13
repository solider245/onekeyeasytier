#!/bin/bash

# =====================================================
# EasyTier 笔记模块
# 功能：管理笔记、FAQ、问题记录
# =====================================================

NOTES_DIR="$HOME/.easytier"
NOTES_FILE="${NOTES_DIR}/notes.md"
INSTALL_LOG="${NOTES_DIR}/install.log"
PEERS_FILE="${NOTES_DIR}/peers.json"

# 默认笔记模板
DEFAULT_NOTES='# EasyTier 笔记

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
'

# 初始化笔记目录和文件
init_notes() {
    mkdir -p "$NOTES_DIR"
    if [ ! -f "$NOTES_FILE" ]; then
        echo "$DEFAULT_NOTES" > "$NOTES_FILE"
    fi
}

# 查看笔记
view_notes() {
    init_notes
    if [ -f "$NOTES_FILE" ]; then
        cat "$NOTES_FILE"
    else
        echo "笔记文件不存在"
    fi
}

# 编辑笔记
edit_notes() {
    init_notes
    if command -v nano >/dev/null 2>&1; then
        nano "$NOTES_FILE"
    elif command -v vim >/dev/null 2>&1; then
        vim "$NOTES_FILE"
    elif command -v code >/dev/null 2>&1; then
        code "$NOTES_FILE"
    else
        echo "请使用其他编辑器打开: $NOTES_FILE"
    fi
}

# 记录安装
log_install() {
    init_notes
    local version="$1"
    local date=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$date] 安装版本: $version" >> "$INSTALL_LOG"
}

# 记录节点
add_peer() {
    init_notes
    local peer_addr="$1"
    local date=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$date] 添加节点: $peer_addr" >> "$INSTALL_LOG"
}

# 导出笔记路径
get_notes_path() {
    echo "$NOTES_FILE"
}

# 导出日志路径
get_log_path() {
    echo "$INSTALL_LOG"
}
