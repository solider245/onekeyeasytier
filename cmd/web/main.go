package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/onekeyeasytier/web/internal/web"
	"github.com/sirupsen/logrus"
)

func main() {
	// 解析命令行参数
	var (
		port       = flag.Int("port", 8080, "Web服务器端口")
		configDir  = flag.String("config-dir", "/etc/easytier", "配置文件目录")
		binaryDir  = flag.String("binary-dir", "/usr/local/bin", "二进制文件目录")
		logLevel   = flag.String("log-level", "info", "日志级别 (debug, info, warn, error)")
		enableAuth = flag.Bool("enable-auth", false, "启用HTTP认证")
		username   = flag.String("username", "admin", "认证用户名")
		password   = flag.String("password", "easytier", "认证密码")
	)
	flag.Parse()

	// 设置日志级别
	level, err := logrus.ParseLevel(*logLevel)
	if err != nil {
		log.Fatalf("无效的日志级别: %v", err)
	}
	logrus.SetLevel(level)

	// 检查权限
	if os.Geteuid() != 0 {
		logrus.Warn("建议以root权限运行此程序以确保完整功能")
	}

	// 创建Web服务器配置
	config := &web.Config{
		Port:       *port,
		ConfigDir:  *configDir,
		BinaryDir:  *binaryDir,
		EnableAuth: *enableAuth,
		Username:   *username,
		Password:   *password,
	}

	// 初始化Web服务器
	server, err := web.NewServer(config)
	if err != nil {
		log.Fatalf("创建Web服务器失败: %v", err)
	}

	// 启动服务器
	go func() {
		logrus.Infof("启动Web服务器，端口: %d", *port)
		if err := server.Start(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Web服务器启动失败: %v", err)
		}
	}()

	// 等待中断信号
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logrus.Info("正在关闭服务器...")
	if err := server.Stop(); err != nil {
		log.Fatalf("服务器关闭失败: %v", err)
	}

	logrus.Info("服务器已关闭")
	fmt.Println("OneKeyEasyTier Web管理器已停止")
}