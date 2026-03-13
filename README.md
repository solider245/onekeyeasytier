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

# 方法3: 备用代理
curl -sL https://ghfast.top/https://raw.githubusercontent.com/solider245/onekeyeasytier/main/easytier.sh -o /tmp/easytier.sh && bash /tmp/easytier.sh
```

## 功能特点

### 🖥️ 全平台制霸
- Linux (Debian/Ubuntu/CentOS): 使用 Systemd 管理
- Alpine Linux: 使用 OpenRC + supervise-daemon 实现真·进程守护
- macOS: 使用 Launchd 实现标准服务管理
- OpenWrt: 使用 procd 进行服务管理

### ⚡ 真正的一键组网
- **快速部署**: 回车自动生成网络名称和密钥，无需手动输入
- **Token 分享**: 一键生成邀请链接，其他节点扫码/复制即可加入
- **社区节点**: 内置 10+ 公共节点可选，告别官方单点故障

### 🧠 超智能化
- 自动生成网络名/密钥: 部署时回车即可使用随机生成的安全凭证
- Token 组网: 生成 easytier:// 格式链接，一键分享给朋友
- 社区节点选择: 加入网络时可选多个社区节点，支持自定义
- 自动快捷方式: 自动创建 `et` 命令，随时唤出管理菜单
- 部署即自启: 自动启动服务并设为开机自启

### 💪 稳定可靠
- 最强进程守护策略，确保 7×24 小时稳定在线
- 自动检测并安装依赖 (curl, jq, unzip)
- 内置 GitHub 代理，解决国内下载困难
