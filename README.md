# onekeyeasytier

一键组网，天下无敌。

![ec9mmBQAWMdMVdkePVvogUYIT4YlodQo.png](https://cdn.nodeimage.com/i/ec9mmBQAWMdMVdkePVvogUYIT4YlodQo.png)

## 快速开始

```bash
# Linux/macOS/Alpine (一键安装脚本)
# 方法1: 直接下载 (国外服务器推荐)
curl -sL https://raw.githubusercontent.com/solider245/onekeyeasytier/main/easytier.sh -o /tmp/easytier.sh && bash /tmp/easytier.sh

# 方法2: 国内加速下载 (推荐)
curl -sL https://gh.565600.xyz/https://raw.githubusercontent.com/solider245/onekeyeasytier/main/easytier.sh -o /tmp/easytier.sh && bash /tmp/easytier.sh
```

## 脚本说明

| 脚本 | 适用平台 | 说明 |
|------|----------|------|
| `easytier.sh` | Linux/macOS | 通用部署脚本 |
| `opeasytier.sh` | OpenWrt | OpenWrt 专用脚本 |
| `easytier.ps1` | Windows | PowerShell 部署脚本 |

## 菜单功能

### easytier.sh (通用版)
```
 1. 安装或更新 EasyTier     - 自动检测最新版本
 2. 检查更新               - 查看可用更新
 3. 部署服务器             - 创建新网络 (首个节点)
 4. 加入网络               - 加入现有网络
 5. 快速部署               - 自动生成网络名/密钥
 6. 通过Token加入网络      - 一键复制粘贴加入
 7. 管理服务状态           - 启动/停止/重启/日志
 8. 查看配置文件          - 查看当前配置
 9. 查看网络节点           - easytier-cli peer
10. 卸载 EasyTier
11. 查看笔记/FAQ
12. 编辑笔记
```

### opeasytier.sh (OpenWrt版)
```
 1. 安装或更新 EasyTier
 2. 检查更新
 3. 部署新网络
 4. 加入现有网络
 5. 快速部署
 6. 通过Token加入网络
 7. 管理服务 (启停/状态/日志)
 8. 查看配置文件
 9. 查看网络节点
10. 卸载 EasyTier
11. 查看笔记/FAQ
12. 编辑笔记
```

## 功能特点

### 🖥️ 全平台制霸
- Linux (Debian/Ubuntu/CentOS): 使用 Systemd 管理
- Alpine Linux: 使用 OpenRC + supervise-daemon 实现真·进程守护
- macOS: 使用 Launchd 实现标准服务管理
- OpenWrt: 使用 procd 进行服务管理
- Windows: 使用 nssm 注册系统服务

### ⚡ 真正的一键组网
- **快速部署**: 回车自动生成网络名称和密钥，无需手动输入
- **Token 分享**: 一键生成 easytier:// 邀请链接，其他节点复制即可加入
- **社区节点**: 内置多个公共节点可选，告别官方单点故障

### 🧠 超智能化
- 自动生成网络名/密钥: 部署时回车即可使用随机生成的安全凭证
- Token 组网: 生成 easytier:// 格式链接，一键分享给朋友
- 社区节点参考: 加入网络时显示可选节点列表作为参考
- 自动快捷方式: 自动创建 `et` 命令，随时唤出管理菜单
- 部署即自启: 自动启动服务并设为开机自启

### 💪 稳定可靠
- 最强进程守护策略，确保 7×24 小时稳定在线
- 自动检测并安装依赖 (curl, jq, unzip)
- 内置 GitHub 代理，解决国内下载困难
- 部署前网络要求提示，确保端口开放
