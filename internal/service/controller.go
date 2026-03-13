package service

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
)

// ServiceController 服务控制器
type ServiceController struct {
	binaryPath  string
	configPath  string
	serviceName string
	logger      *logrus.Logger
	detector    SystemDetector
}

// ServiceStatus 服务状态
type ServiceStatus struct {
	Running     bool   `json:"running"`
	PID         int    `json:"pid"`
	Uptime      string `json:"uptime"`
	LastReload  string `json:"last_reload"`
	ConfigFile  string `json:"config_file"`
	BinaryPath  string `json:"binary_path"`
	ServiceName string `json:"service_name"`
}

// SystemDetector 系统检测器接口
type SystemDetector interface {
	DetectOS() string
	DetectServiceManager() string
	FindProcess(name string) (int, error)
}

// NewServiceController 创建服务控制器
func NewServiceController(binaryPath, configPath, serviceName string) *ServiceController {
	return &ServiceController{
		binaryPath:  binaryPath,
		configPath:  configPath,
		serviceName: serviceName,
		logger:      logrus.New(),
		detector:    &DefaultSystemDetector{},
	}
}

// StartService 启动服务
func (sc *ServiceController) StartService() error {
	// 检查是否已运行
	if status, err := sc.GetStatus(); err == nil && status.Running {
		return fmt.Errorf("服务已在运行中 (PID: %d)", status.PID)
	}

	// 检查二进制文件是否存在
	if _, err := os.Stat(sc.binaryPath); os.IsNotExist(err) {
		return fmt.Errorf("二进制文件不存在: %s", sc.binaryPath)
	}

	// 检查配置文件是否存在
	if _, err := os.Stat(sc.configPath); os.IsNotExist(err) {
		return fmt.Errorf("配置文件不存在: %s", sc.configPath)
	}

	// 根据系统类型启动服务
	switch sc.detector.DetectOS() {
	case "linux":
		return sc.startLinuxService()
	case "macos":
		return sc.startMacOSService()
	case "windows":
		return sc.startWindowsService()
	default:
		return sc.startDirectService()
	}
}

// StopService 停止服务
func (sc *ServiceController) StopService() error {
	// 检查是否在运行
	status, err := sc.GetStatus()
	if err != nil {
		return fmt.Errorf("获取服务状态失败: %v", err)
	}

	if !status.Running {
		return fmt.Errorf("服务未运行")
	}

	// 根据系统类型停止服务
	switch sc.detector.DetectOS() {
	case "linux":
		return sc.stopLinuxService()
	case "macos":
		return sc.stopMacOSService()
	case "windows":
		return sc.stopWindowsService()
	default:
		return sc.stopDirectService(status.PID)
	}
}

// RestartService 重启服务
func (sc *ServiceController) RestartService() error {
	if err := sc.StopService(); err != nil {
		return fmt.Errorf("停止服务失败: %v", err)
	}

	// 等待进程完全停止
	time.Sleep(2 * time.Second)

	return sc.StartService()
}

// ReloadService 重载配置
func (sc *ServiceController) ReloadService() error {
	// 检查服务是否运行
	status, err := sc.GetStatus()
	if err != nil {
		return fmt.Errorf("获取服务状态失败: %v", err)
	}

	if !status.Running {
		return fmt.Errorf("服务未运行，无法重载配置")
	}

	// 根据系统类型重载服务
	switch sc.detector.DetectServiceManager() {
	case "systemd":
		return sc.reloadSystemdService()
	case "launchd":
		return sc.reloadLaunchdService()
	case "windows_service":
		return sc.reloadWindowsService()
	default:
		return sc.reloadDirectService(status.PID)
	}
}

// GetStatus 获取服务状态
func (sc *ServiceController) GetStatus() (*ServiceStatus, error) {
	status := &ServiceStatus{
		ConfigFile:  sc.configPath,
		BinaryPath:  sc.binaryPath,
		ServiceName: sc.serviceName,
	}

	// 检查进程是否运行
	if pid, err := sc.detector.FindProcess("easytier-core"); err == nil && pid > 0 {
		status.Running = true
		status.PID = pid
		status.Uptime = sc.getProcessUptime(pid)
	}

	// 获取最后重载时间
	if info, err := os.Stat(sc.configPath); err == nil {
		status.LastReload = info.ModTime().Format("2006-01-02 15:04:05")
	}

	return status, nil
}

// startLinuxService 启动Linux服务
func (sc *ServiceController) startLinuxService() error {
	serviceMgr := sc.detector.DetectServiceManager()

	switch serviceMgr {
	case "systemd":
		cmd := exec.Command("systemctl", "start", sc.serviceName)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("启动systemd服务失败: %v", err)
		}
	case "openrc":
		cmd := exec.Command("rc-service", sc.serviceName, "start")
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("启动openrc服务失败: %v", err)
		}
	default:
		return sc.startDirectService()
	}

	return nil
}

// stopLinuxService 停止Linux服务
func (sc *ServiceController) stopLinuxService() error {
	serviceMgr := sc.detector.DetectServiceManager()

	switch serviceMgr {
	case "systemd":
		cmd := exec.Command("systemctl", "stop", sc.serviceName)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("停止systemd服务失败: %v", err)
		}
	case "openrc":
		cmd := exec.Command("rc-service", sc.serviceName, "stop")
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("停止openrc服务失败: %v", err)
		}
	default:
		if pid, err := sc.detector.FindProcess("easytier-core"); err == nil && pid > 0 {
			return sc.stopDirectService(pid)
		}
	}

	return nil
}

// startMacOSService 启动macOS服务
func (sc *ServiceController) startMacOSService() error {
	cmd := exec.Command("launchctl", "load", "/Library/LaunchDaemons/com.easytier.core.plist")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("启动launchd服务失败: %v", err)
	}
	return nil
}

// stopMacOSService 停止macOS服务
func (sc *ServiceController) stopMacOSService() error {
	cmd := exec.Command("launchctl", "unload", "/Library/LaunchDaemons/com.easytier.core.plist")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("停止launchd服务失败: %v", err)
	}
	return nil
}

// startWindowsService 启动Windows服务
func (sc *ServiceController) startWindowsService() error {
	cmd := exec.Command("sc", "start", sc.serviceName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("启动Windows服务失败: %v", err)
	}
	return nil
}

// stopWindowsService 停止Windows服务
func (sc *ServiceController) stopWindowsService() error {
	cmd := exec.Command("sc", "stop", sc.serviceName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("停止Windows服务失败: %v", err)
	}
	return nil
}

// startDirectService 直接启动服务
func (sc *ServiceController) startDirectService() error {
	cmd := exec.Command(sc.binaryPath, "--config", sc.configPath)
	
	// 对于后台运行，使用nohup或StartProcess
	if runtime.GOOS != "windows" {
		cmd = exec.Command("nohup", sc.binaryPath, "--config", sc.configPath, ">", "/var/log/easytier.log", "2>&1", "&")
	} else {
		cmd = exec.Command("cmd", "/c", "start", "/b", sc.binaryPath, "--config", sc.configPath)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("启动服务失败: %v", err)
	}

	sc.logger.Info("服务已启动")
	return nil
}

// stopDirectService 直接停止服务
func (sc *ServiceController) stopDirectService(pid int) error {
	// 发送SIGTERM信号
	process, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("查找进程失败: %v", err)
	}

	if err := process.Signal(os.Interrupt); err != nil {
		return fmt.Errorf("发送中断信号失败: %v", err)
	}

	// 等待进程退出
	time.Sleep(2 * time.Second)

	// 如果进程仍在运行，强制终止
	if pid, err := sc.detector.FindProcess("easytier-core"); err == nil && pid > 0 {
		process, err := os.FindProcess(pid)
		if err == nil {
			process.Kill()
		}
	}

	sc.logger.Info("服务已停止")
	return nil
}

// reloadSystemdService 重载systemd服务
func (sc *ServiceController) reloadSystemdService() error {
	cmd := exec.Command("systemctl", "reload", sc.serviceName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("重载systemd服务失败: %v", err)
	}
	return nil
}

// reloadLaunchdService 重载launchd服务
func (sc *ServiceController) reloadLaunchdService() error {
	cmd := exec.Command("launchctl", "stop", sc.serviceName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("停止launchd服务失败: %v", err)
	}

	time.Sleep(1 * time.Second)

	cmd = exec.Command("launchctl", "start", sc.serviceName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("启动launchd服务失败: %v", err)
	}

	return nil
}

// reloadWindowsService 重载Windows服务
func (sc *ServiceController) reloadWindowsService() error {
	cmd := exec.Command("sc", "stop", sc.serviceName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("停止Windows服务失败: %v", err)
	}

	time.Sleep(1 * time.Second)

	cmd = exec.Command("sc", "start", sc.serviceName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("启动Windows服务失败: %v", err)
	}

	return nil
}

// reloadDirectService 直接重载服务
func (sc *ServiceController) reloadDirectService(pid int) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("查找进程失败: %v", err)
	}

	if err := process.Signal(os.Interrupt); err != nil {
		return fmt.Errorf("发送重载信号失败: %v", err)
	}

	sc.logger.Info("服务配置已重载")
	return nil
}

// getProcessUptime 获取进程运行时间
func (sc *ServiceController) getProcessUptime(pid int) string {
	if runtime.GOOS == "windows" {
		return "unknown"
	}

	cmd := exec.Command("ps", "-o", "etime=", "-p", fmt.Sprintf("%d", pid))
	output, err := cmd.Output()
	if err != nil {
		return "unknown"
	}

	return strings.TrimSpace(string(output))
}

// GetServiceLogs 获取服务日志
func (sc *ServiceController) GetServiceLogs(lines int) ([]string, error) {
	logPaths := []string{
		"/var/log/easytier.log",
		"/var/log/easytier/core.log",
		"/usr/local/var/log/easytier.log",
		"C:\\ProgramData\\EasyTier\\easytier.log",
	}

	for _, logPath := range logPaths {
		if _, err := os.Stat(logPath); err == nil {
			return sc.readLastLines(logPath, lines)
		}
	}

	return nil, fmt.Errorf("未找到日志文件")
}

// readLastLines 读取文件最后几行
func (sc *ServiceController) readLastLines(filePath string, lines int) ([]string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var result []string
	scanner := bufio.NewScanner(file)
	
	// 读取所有行
	var allLines []string
	for scanner.Scan() {
		allLines = append(allLines, scanner.Text())
	}

	// 获取最后几行
	start := len(allLines) - lines
	if start < 0 {
		start = 0
	}

	result = allLines[start:]

	return result, nil
}

// DefaultSystemDetector 默认系统检测器
type DefaultSystemDetector struct{}

func (d *DefaultSystemDetector) DetectOS() string {
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

func (d *DefaultSystemDetector) detectLinuxDistro() string {
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

func (d *DefaultSystemDetector) DetectServiceManager() string {
	switch d.DetectOS() {
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
	case "macos":
		return "launchd"
	case "windows":
		return "windows_service"
	}
	return "unknown"
}

func (d *DefaultSystemDetector) FindProcess(name string) (int, error) {
	var cmd *exec.Cmd

	switch d.DetectOS() {
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

	if d.DetectOS() == "windows" {
		if len(output) > 0 {
			parts := strings.Split(string(output), "\",\"")
			if len(parts) > 1 {
				var pid int
				_, err := fmt.Sscanf(parts[1], "%d", &pid)
				return pid, err
			}
		}
	} else {
		var pid int
		_, err := fmt.Sscanf(string(output), "%d", &pid)
		return pid, err
	}

	return 0, fmt.Errorf("process not found")
}