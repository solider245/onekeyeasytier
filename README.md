# OneKeyEasyTier Web管理器

一个基于Go语言开发的EasyTier网络管理器，提供图形化Web界面来管理和监控EasyTier网络服务。

## ✨ 功能特性

### 🔍 智能系统检测
- **多平台支持**: 自动检测Linux、macOS、Windows、OpenWrt
- **架构识别**: 自动识别x86_64、aarch64等架构
- **组件检测**: 自动发现已安装的EasyTier组件
- **服务监控**: 实时监控服务进程状态

### ⚙️ 配置管理
- **可视化编辑**: TOML配置文件的图形化编辑器
- **语法高亮**: CodeMirror编辑器支持TOML语法
- **配置验证**: 实时验证配置文件格式
- **模板系统**: 提供基础、高级、服务器等配置模板
- **版本管理**: 配置文件备份和恢复

### 🎛️ 服务控制
- **安全启停**: 智能检测避免进程冲突
- **配置重载**: 热重载配置无需重启
- **状态监控**: 实时显示服务运行状态
- **日志查看**: 实时查看服务日志

### 🌐 Web界面
- **响应式设计**: 适配桌面和移动设备
- **实时更新**: 自动刷新状态和日志
- **直观操作**: 简洁易用的用户界面
- **多语言支持**: 中文界面

## 🏗️ 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    Go Web管理器                            │
├─────────────────────────────────────────────────────────────┤
│  HTTP Router   │  配置管理器   │  服务控制器  │  系统检测器  │
├─────────────────────────────────────────────────────────────┤
│  静态文件服务  │  RESTful API  │  WebSocket  │  系统命令执行 │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 快速开始

### 使用Docker（推荐）

#### 1. 构建和部署
```bash
# 克隆项目
git clone <repository-url>
cd onekeyeasytier

# 构建Docker镜像
./scripts/build.sh build

# 部署Web管理器
./scripts/build.sh deploy

# 部署Web管理器 + EasyTier核心服务
./scripts/build.sh deploy --with-core
```

#### 2. 访问Web界面
打开浏览器访问: http://localhost:8080

#### 3. 管理命令
```bash
# 查看状态
./scripts/build.sh status

# 查看日志
./scripts/build.sh logs

# 重启服务
./scripts/build.sh restart

# 停止服务
./scripts/build.sh stop

# 清理资源
./scripts/build.sh clean
```

### 使用Docker Compose

```bash
# 启动Web管理器
docker-compose -f docker/docker-compose.yml up -d

# 启动Web管理器 + EasyTier核心服务
docker-compose -f docker/docker-compose.yml --profile with-core up -d

# 查看日志
docker-compose -f docker/docker-compose.yml logs -f
```

### 使用 Shell 脚本（Linux/macOS/OpenWrt）

适用于 Linux、macOS、OpenWrt 等系统，无需 Docker。

#### 快速安装（国内用户推荐）

由于 GitHub 在国内访问较慢，建议使用代理下载脚本：

```bash
# Linux/macOS（通用版本）
bash <(curl -sL https://ghfast.top/https://raw.githubusercontent.com/EasyTier/onekeyeasytier/main/easytier.sh)

# OpenWrt（专为 OpenWrt aarch64 设计）
bash <(curl -sL https://ghfast.top/https://raw.githubusercontent.com/EasyTier/onekeyeasytier/main/opeasytier.sh)
```

#### 标准安装

```bash
# 克隆项目
git clone <repository-url>
cd onekeyeasytier

# Linux/macOS
chmod +x easytier.sh
sudo ./easytier.sh

# OpenWrt
chmod +x opeasytier.sh
./opeasytier.sh
```

#### 功能说明

- **安装/更新 EasyTier**: 自动下载并安装最新版本
- **部署新网络**: 创建首个节点
- **加入现有网络**: 连接到已有网络
- **服务管理**: 启停、查看状态、日志等
- **卸载**: 清理所有相关文件

---

### 本地开发

#### 1. 环境要求
- Go 1.21+
- Docker (可选)

#### 2. 安装依赖
```bash
go mod download
```

#### 3. 运行开发服务器
```bash
# 运行开发服务器
go run cmd/web/main.go --port 8080

# 或使用配置参数
go run cmd/web/main.go \
    --port 8080 \
    --config-dir /etc/easytier \
    --binary-dir /usr/local/bin \
    --enable-auth false
```

## ⚙️ 配置选项

### 环境变量
| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `EASYTIER_WEB_PORT` | 8080 | Web服务端口 |
| `EASYTIER_CONFIG_DIR` | /etc/easytier | 配置文件目录 |
| `EASYTIER_BINARY_DIR` | /usr/local/bin | 二进制文件目录 |
| `EASYTIER_ENABLE_AUTH` | false | 启用HTTP认证 |
| `EASYTIER_USERNAME` | admin | 认证用户名 |
| `EASYTIER_PASSWORD` | easytier | 认证密码 |
| `EASYTIER_DOWNLOAD_URL` | - | 自动下载EasyTier二进制文件的URL |

### 命令行参数
```bash
./easytier-web [选项]

选项:
  --port int           Web服务器端口 (默认 8080)
  --config-dir string  配置文件目录 (默认 "/etc/easytier")
  --binary-dir string  二进制文件目录 (默认 "/usr/local/bin")
  --log-level string   日志级别 (debug, info, warn, error) (默认 "info")
  --enable-auth        启用HTTP认证
  --username string    认证用户名 (默认 "admin")
  --password string    认证密码 (默认 "easytier")
```

## 📁 项目结构

```
onekeyeasytier/
├── cmd/web/                    # 主程序入口
│   └── main.go
├── internal/                   # 内部包
│   ├── config/                 # 配置管理
│   │   ├── config.go
│   │   └── validator.go
│   ├── detector/               # 系统检测
│   │   └── detector.go
│   ├── service/                # 服务控制
│   │   └── controller.go
│   └── web/                    # Web界面
│       └── server.go
├── web/                        # Web资源
│   ├── static/                 # 静态文件
│   └── templates/              # HTML模板
├── configs/                    # 配置文件和模板
│   └── templates/
├── docker/                     # Docker配置
│   ├── Dockerfile
│   └── docker-compose.yml
├── scripts/                    # 构建脚本
│   └── build.sh
├── go.mod
└── README.md
```

## 🔧 API文档

### RESTful API

#### 获取系统状态
```http
GET /api/status
```

#### 配置管理
```http
GET /api/config                # 获取配置
POST /api/config               # 更新配置
```

#### 服务控制
```http
POST /api/service/start        # 启动服务
POST /api/service/stop         # 停止服务
POST /api/service/restart      # 重启服务
POST /api/service/reload       # 重载配置
```

#### 日志管理
```http
GET /api/logs?lines=100        # 获取日志
```

#### 模板管理
```http
GET /api/templates             # 获取配置模板
```

### 响应格式
```json
{
  "success": true,
  "message": "操作成功",
  "data": {},
  "time": "2024-01-01 12:00:00"
}
```

## 🛡️ 安全特性

### 认证和授权
- HTTP Basic认证
- 可配置的用户名和密码
- 支持禁用认证（仅限可信环境）

### 进程安全
- 智能进程检测，避免重复启动
- 优雅停止和重载
- 信号处理和资源清理

### 文件安全
- 配置文件权限验证
- 备份和恢复机制
- TOML格式验证

## 🔍 故障排除

### 常见问题

#### 1. 容器启动失败
```bash
# 检查Docker服务状态
docker info

# 查看容器日志
docker logs easytier-web

# 检查端口占用
netstat -tlnp | grep 8080
```

#### 2. 服务控制失败
```bash
# 检查权限
sudo ./easytier-web

# 检查二进制文件
ls -la /usr/local/bin/easytier-core

# 检查配置文件
ls -la /etc/easytier/easytier.toml
```

#### 3. Web界面无法访问
```bash
# 检查防火墙
sudo ufw status

# 检查容器状态
docker ps | grep easytier-web

# 检查网络连接
curl http://localhost:8080/api/status
```

### 日志查看
```bash
# 查看容器日志
docker logs -f easytier-web

# 查看服务日志
docker logs -f easytier-core

# 查看系统日志
journalctl -u easytier-web -f
```

## 🤝 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [EasyTier](https://github.com/EasyTier/EasyTier) - 核心网络库
- [Go](https://golang.org/) - 编程语言
- [Bootstrap](https://getbootstrap.com/) - UI框架
- [CodeMirror](https://codemirror.net/) - 代码编辑器

## 📞 支持

如果您遇到问题或有建议，请：

1. 查看 [故障排除](#故障排除) 部分
2. 搜索已有的 [Issues](https://github.com/your-repo/issues)
3. 创建新的 Issue 描述问题

---

**OneKeyEasyTier Web管理器** - 让EasyTier网络管理更简单！