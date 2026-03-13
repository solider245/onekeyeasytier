# onekeyeasytier

一键组网，天下无敌。上面有windows版本，复制了在powershell运行就可以

![ec9mmBQAWMdMVdkePVvogUYIT4YlodQo.png](https://cdn.nodeimage.com/i/ec9mmBQAWMdMVdkePVvogUYIT4YlodQo.png)
```
bash <(curl -sL https://raw.githubusercontent.com/ceocok/c.cococ/refs/heads/main/easytier.sh)
# 国内用户: bash <(curl -sL https://ghfast.top/https://raw.githubusercontent.com/ceocok/c.cococ/refs/heads/main/easytier.sh)
```
- ✨ 这个脚本凭什么被称为"宇宙无敌好用"？
- 🖥️ 全平台制霸
- 完美适配主流系统，并为每个系统提供了最佳实践：
- 
- Linux (Debian/Ubuntu): 使用 Systemd 管理。
- Alpine Linux: 使用 OpenRC + supervise-daemon 实现真·进程守护。
- macOS: 使用 Launchd 实现标准服务管理。
- ✨ 真正的一站式体验
- 从安装到卸载，所有操作集成在一个清爽的交互式菜单中：
- 
- 安装/更新: 自动检测最新版，支持 aarch64 和 x86_64 架构。
- 部署/加入网络: 引导式配置，告别手动编辑 toml 文件的烦恼。
- 服务管理: 轻松实现启动、停止、重启、查看状态、设置/取消开机自启。
- 配置/节点查看: 快速预览当前配置文件和网络节点信息。
- 一键卸载: 干净、彻底，不留任何残余。
- 🧠 超乎想象的智能化
- 脚本内置了大量自动化逻辑，让你"只做选择，不干杂活"：
- 
- 自动 IP/DHCP: 在配置节点时，虚拟 IP 地址留空即可自动启用 DHCP，省心省力。
- 默认公共节点: 加入网络时，如果忘记或懒得输入对端节点，脚本会自动使用官方公共节点作为默认值。
- 自动快捷方式: 首次运行时，会自动在 /usr/local/bin 创建 et 命令，之后你可以在任何地方输入 et 快速唤出管理菜单。
- 部署即自启: 在你选择"部署"或"加入"网络后，脚本会自动将服务启动并设置为开机自启，无需任何额外的手动操作！
- 💪 绝对的稳定可靠
- 
- 为不同系统量身打造了最强的进程守护策略 (Restart=always, supervise-daemon, KeepAlive)，确保你的 EasyTier 服务 7x24 小时稳定在线。
- 自动检测 curl, jq 等核心依赖，如果缺失会提示并帮助你自动安装。
- 内置 GitHub 代理选项，有效解决国内服务器下载困难的问题。
