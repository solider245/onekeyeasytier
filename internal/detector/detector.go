package detector

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// SystemInfo 系统信息
type SystemInfo struct {
	OS           string   `json:"os"`             // 操作系统
	Arch         string   `json:"arch"`           // 架构
	ServiceMgr   string   `json:"service_manager"` // 服务管理器
	Components   ComponentStatus `json:"components"` // 组件状态
	Services     []ServiceInfo `json:"services"`     // 服务信息
}

// ComponentStatus 组件状态
type ComponentStatus struct {
	ConfigFile   string   `json:"config_file"`   // 配置文件路径
	BinaryPath   string   `json:"binary_path"`   // 二进制文件路径
	CliPath      string   `json:"cli_path"`      // CLI工具路径
	ConfigExists bool     `json:"config_exists"` // 配置文件是否存在
	BinaryExists bool     `json:"binary_exists"` // 二进制文件是否存在
	CliExists    bool     `json:"cli_exists"`    // CLI工具是否存在
}

// ServiceInfo 服务信息
type ServiceInfo struct {
	Name        string `json:"name"`        // 服务名称
	Status      string `json:"status"`      // 服务状态
	PID         int    `json:"pid"`         // 进程ID
	Description string `json:"description"` // 描述
}

// Detector 系统检测器
type Detector struct {
	configDir  string
	binaryDir  string
}

// NewDetector 创建新的检测器
func NewDetector(configDir, binaryDir string) *Detector {
	return &Detector{
		configDir: configDir,
		binaryDir: binaryDir,
	}
}

// Detect 执行系统检测
func (d *Detector) Detect() (*SystemInfo, error) {
	info := &SystemInfo{
		OS:         d.detectOS(),
		Arch:       d.detectArch(),
		ServiceMgr: d.detectServiceManager(),
	}

	// 检测组件状态
	info.Components = d.detectComponents()

	// 检测服务状态
	services, err := d.detectServices()
	if err != nil {
		return nil, fmt.Errorf("检测服务失败: %v", err)
	}
	info.Services = services

	return info, nil
}

// detectOS 检测操作系统
func (d *Detector) detectOS() string {
	switch runtime.GOOS {
	case "linux":
		return d.detectLinuxDistro()
	case "darwin":
		return "macos"
	case "windows":
		return "windows"
	default:
		return runtime.GOOS
	}
}

// detectArch 检测架构
func (d *Detector) detectArch() string {
	return runtime.GOARCH
}

// detectLinuxDistro 检测Linux发行版
func (d *Detector) detectLinuxDistro() string {
	if _, err := os.Stat("/etc/alpine-release"); err == nil {
		return "alpine"
	}
	if _, err := os.Stat("/etc/debian_version"); err == nil {
		return "debian"
	}
	if _, err := os.Stat("/etc/centos-release"); err == nil {
		return "centos"
	}
	if _, err := os.Stat("/etc/openwrt_release"); err == nil {
		return "openwrt"
	}
	return "linux"
}

// detectServiceManager 检测服务管理器
func (d *Detector) detectServiceManager() string {
	switch d.detectOS() {
	case "linux":
		if _, err := os.Stat("/bin/systemctl"); err == nil {
			return "systemd"
		}
		if _, err := os.Stat("/sbin/openrc"); err == nil {
			return "openrc"
		}
		if _, err := os.Stat("/etc/init.d"); err == nil {
			return "sysvinit"
		}
		if _, err := os.Stat("/etc/init.d"); err == nil && d.detectOS() == "openwrt" {
			return "procd"
		}
	case "macos":
		return "launchd"
	case "windows":
		return "windows_service"
	}
	return "unknown"
}

// detectComponents 检测组件状态
func (d *Detector) detectComponents() ComponentStatus {
	status := ComponentStatus{}

	// 检测配置文件
	configPaths := []string{
		d.configDir + "/easytier.toml",
		"/etc/easytier/easytier.toml",
		"/usr/local/etc/easytier.toml",
		"/etc/config/easytier.toml", // OpenWrt
		"./easytier.toml",
	}

	for _, path := range configPaths {
		if _, err := os.Stat(path); err == nil {
			status.ConfigFile = path
			status.ConfigExists = true
			break
		}
	}

	// 检测二进制文件
	binaryPaths := []string{
		d.binaryDir + "/easytier-core",
		"/usr/local/bin/easytier-core",
		"/usr/bin/easytier-core",
		"./easytier-core",
	}

	for _, path := range binaryPaths {
		if _, err := os.Stat(path); err == nil {
			status.BinaryPath = path
			status.BinaryExists = true
			break
		}
	}

	// 检测CLI工具
	cliPaths := []string{
		d.binaryDir + "/easytier-cli",
		"/usr/local/bin/easytier-cli",
		"/usr/bin/easytier-cli",
		"./easytier-cli",
	}

	for _, path := range cliPaths {
		if _, err := os.Stat(path); err == nil {
			status.CliPath = path
			status.CliExists = true
			break
		}
	}

	return status
}

// detectServices 检测服务状态
func (d *Detector) detectServices() ([]ServiceInfo, error) {
	var services []ServiceInfo

	// 检测easytier-core进程
	if pid, err := d.findProcess("easytier-core"); err == nil && pid > 0 {
		services = append(services, ServiceInfo{
			Name:        "easytier-core",
			Status:      "running",
			PID:         pid,
			Description: "EasyTier核心服务",
		})
	}

	// 检测系统服务
	serviceName := "easytier"
	switch d.detectServiceManager() {
	case "systemd":
		if d.isSystemdServiceActive(serviceName) {
			services = append(services, ServiceInfo{
				Name:        serviceName,
				Status:      "active",
				Description: "EasyTier系统服务",
			})
		}
	case "launchd":
		if d.isLaunchdServiceRunning(serviceName) {
			services = append(services, ServiceInfo{
				Name:        serviceName,
				Status:      "running",
				Description: "EasyTier macOS服务",
			})
		}
	case "windows_service":
		if d.isWindowsServiceRunning(serviceName) {
			services = append(services, ServiceInfo{
				Name:        serviceName,
				Status:      "running",
				Description: "EasyTier Windows服务",
			})
		}
	}

	return services, nil
}

// findProcess 查找进程PID
func (d *Detector) findProcess(name string) (int, error) {
	var cmd *exec.Cmd

	switch d.detectOS() {
	case "linux", "macos":
		cmd = exec.Command("pgrep", name)
	case "windows":
		cmd = exec.Command("tasklist", "/FI", fmt.Sprintf("IMAGENAME eq %s", name), "/FO", "CSV", "/NH")
	default:
		return 0, fmt.Errorf("unsupported platform")
	}

	output, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	if d.detectOS() == "windows" {
		// Windows输出格式: "easytier-core.exe","1234","Session Name","Mem Usage"
		if len(output) > 0 {
			parts := strings.Split(string(output), "\",\"")
			if len(parts) > 1 {
				var pid int
				_, err := fmt.Sscanf(parts[1], "%d", &pid)
				return pid, err
			}
		}
	} else {
		// Linux/macOS输出格式: PID
		var pid int
		_, err := fmt.Sscanf(string(output), "%d", &pid)
		return pid, err
	}

	return 0, fmt.Errorf("process not found")
}

// isSystemdServiceActive 检查systemd服务是否激活
func (d *Detector) isSystemdServiceActive(serviceName string) bool {
	cmd := exec.Command("systemctl", "is-active", serviceName)
	if err := cmd.Run(); err != nil {
		return false
	}
	return true
}

// isLaunchdServiceRunning 检查launchd服务是否运行
func (d *Detector) isLaunchdServiceRunning(serviceName string) bool {
	cmd := exec.Command("launchctl", "list", serviceName)
	if err := cmd.Run(); err != nil {
		return false
	}
	return true
}

// isWindowsServiceRunning 检查Windows服务是否运行
func (d *Detector) isWindowsServiceRunning(serviceName string) bool {
	cmd := exec.Command("sc", "query", serviceName)
	output, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(output), "RUNNING")
}

// GetSystemInfo 获取系统信息（便捷函数）
func GetSystemInfo(configDir, binaryDir string) (*SystemInfo, error) {
	detector := NewDetector(configDir, binaryDir)
	return detector.Detect()
}