package config

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
	"github.com/sirupsen/logrus"
)

// EasyTierConfig EasyTier配置结构
type EasyTierConfig struct {
	Network struct {
		Name     string `toml:"name"`
		IP4Cidr  string `toml:"ipv4_cidr"`
		IP6Cidr  string `toml:"ipv6_cidr,omitempty"`
	} `toml:"network"`

	Peers []struct {
		URI string `toml:"uri"`
	} `toml:"peers"`

	DHCP struct {
		Enabled bool   `toml:"enabled"`
		IP4Pool string `toml:"ipv4_pool,omitempty"`
		IP6Pool string `toml:"ipv6_pool,omitempty"`
	} `toml:"dhcp"`

	Routing struct {
		Enabled      bool `toml:"enabled"`
		Table        int  `toml:"table,omitempty"`
		TablePriority int  `toml:"table_priority,omitempty"`
	} `toml:"routing"`

	NAT struct {
		Enabled bool `toml:"enabled"`
	} `toml:"nat"`

	DevName string `toml:"dev_name,omitempty"`
}

// ConfigManager 配置管理器
type ConfigManager struct {
	configPath   string
	backupDir    string
	templateDir  string
	logger       *logrus.Logger
}

// NewConfigManager 创建配置管理器
func NewConfigManager(configPath, backupDir, templateDir string) *ConfigManager {
	return &ConfigManager{
		configPath:  configPath,
		backupDir:   backupDir,
		templateDir: templateDir,
		logger:      logrus.New(),
	}
}

// LoadConfig 加载配置文件
func (cm *ConfigManager) LoadConfig() (*EasyTierConfig, error) {
	// 如果配置文件不存在，返回默认配置
	if _, err := os.Stat(cm.configPath); os.IsNotExist(err) {
		cm.logger.Info("配置文件不存在，使用默认配置")
		return cm.getDefaultConfig(), nil
	}

	data, err := os.ReadFile(cm.configPath)
	if err != nil {
		return nil, fmt.Errorf("读取配置文件失败: %v", err)
	}

	var config EasyTierConfig
	if err := toml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("解析配置文件失败: %v", err)
	}

	cm.logger.WithField("config", config).Info("配置文件加载成功")
	return &config, nil
}

// SaveConfig 保存配置文件
func (cm *ConfigManager) SaveConfig(config *EasyTierConfig) error {
	// 验证配置
	if err := cm.validateConfig(config); err != nil {
		return fmt.Errorf("配置验证失败: %v", err)
	}

	// 创建备份
	if err := cm.backupConfig(); err != nil {
		cm.logger.WithError(err).Warn("创建配置备份失败")
	}

	// 确保配置目录存在
	if err := os.MkdirAll(filepath.Dir(cm.configPath), 0755); err != nil {
		return fmt.Errorf("创建配置目录失败: %v", err)
	}

	// 生成配置内容
	var buf bytes.Buffer
	if err := toml.NewEncoder(&buf).Encode(config); err != nil {
		return fmt.Errorf("生成配置内容失败: %v", err)
	}

	// 写入文件
	if err := os.WriteFile(cm.configPath, buf.Bytes(), 0644); err != nil {
		return fmt.Errorf("写入配置文件失败: %v", err)
	}

	cm.logger.WithField("config", config).Info("配置文件保存成功")
	return nil
}

// UpdateConfig 更新配置
func (cm *ConfigManager) UpdateConfig(configData string) (*EasyTierConfig, error) {
	// 解析配置数据
	var config EasyTierConfig
	if err := toml.Unmarshal([]byte(configData), &config); err != nil {
		return nil, fmt.Errorf("解析配置数据失败: %v", err)
	}

	// 保存配置
	if err := cm.SaveConfig(&config); err != nil {
		return nil, err
	}

	return &config, nil
}

// GetConfigContent 获取配置文件内容
func (cm *ConfigManager) GetConfigContent() (string, error) {
	config, err := cm.LoadConfig()
	if err != nil {
		return "", err
	}

	var buf bytes.Buffer
	if err := toml.NewEncoder(&buf).Encode(config); err != nil {
		return "", fmt.Errorf("生成配置内容失败: %v", err)
	}

	return buf.String(), nil
}

// ValidateConfig 验证配置
func (cm *ConfigManager) ValidateConfig(configData string) error {
	var config EasyTierConfig
	if err := toml.Unmarshal([]byte(configData), &config); err != nil {
		return fmt.Errorf("TOML格式错误: %v", err)
	}

	return cm.validateConfig(&config)
}

// validateConfig 验证配置结构
func (cm *ConfigManager) validateConfig(config *EasyTierConfig) error {
	if config.Network.Name == "" {
		return fmt.Errorf("网络名称不能为空")
	}

	if config.Network.IP4Cidr == "" {
		return fmt.Errorf("IPv4 CIDR不能为空")
	}

	// 验证对等节点URI格式
	for _, peer := range config.Peers {
		if peer.URI == "" {
			continue
		}
		if !cm.isValidPeerURI(peer.URI) {
			return fmt.Errorf("无效的对等节点URI: %s", peer.URI)
		}
	}

	return nil
}

// isValidPeerURI 验证对等节点URI格式
func (cm *ConfigManager) isValidPeerURI(uri string) bool {
	return strings.HasPrefix(uri, "tcp://") || 
		   strings.HasPrefix(uri, "udp://") || 
		   strings.HasPrefix(uri, "ws://") || 
		   strings.HasPrefix(uri, "wss://")
}

// backupConfig 备份配置文件
func (cm *ConfigManager) backupConfig() error {
	if _, err := os.Stat(cm.configPath); os.IsNotExist(err) {
		return nil // 配置文件不存在，无需备份
	}

	// 确保备份目录存在
	if err := os.MkdirAll(cm.backupDir, 0755); err != nil {
		return err
	}

	// 生成备份文件名
	timestamp := time.Now().Format("20060102-150405")
	backupPath := filepath.Join(cm.backupDir, fmt.Sprintf("easytier.toml.%s.bak", timestamp))

	// 复制配置文件
	data, err := os.ReadFile(cm.configPath)
	if err != nil {
		return err
	}

	return os.WriteFile(backupPath, data, 0644)
}

// ListBackups 列出备份文件
func (cm *ConfigManager) ListBackups() ([]string, error) {
	if _, err := os.Stat(cm.backupDir); os.IsNotExist(err) {
		return nil, nil
	}

	files, err := os.ReadDir(cm.backupDir)
	if err != nil {
		return nil, err
	}

	var backups []string
	for _, file := range files {
		if !file.IsDir() && strings.HasSuffix(file.Name(), ".bak") {
			backups = append(backups, file.Name())
		}
	}

	return backups, nil
}

// RestoreBackup 恢复备份
func (cm *ConfigManager) RestoreBackup(backupName string) error {
	backupPath := filepath.Join(cm.backupDir, backupName)
	if _, err := os.Stat(backupPath); os.IsNotExist(err) {
		return fmt.Errorf("备份文件不存在: %s", backupName)
	}

	// 创建当前配置的备份
	if err := cm.backupConfig(); err != nil {
		cm.logger.WithError(err).Warn("创建当前配置备份失败")
	}

	// 恢复备份
	data, err := os.ReadFile(backupPath)
	if err != nil {
		return fmt.Errorf("读取备份文件失败: %v", err)
	}

	return os.WriteFile(cm.configPath, data, 0644)
}

// GetTemplateList 获取配置模板列表
func (cm *ConfigManager) GetTemplateList() ([]string, error) {
	if _, err := os.Stat(cm.templateDir); os.IsNotExist(err) {
		return nil, nil
	}

	files, err := os.ReadDir(cm.templateDir)
	if err != nil {
		return nil, err
	}

	var templates []string
	for _, file := range files {
		if !file.IsDir() && strings.HasSuffix(file.Name(), ".toml") {
			templates = append(templates, strings.TrimSuffix(file.Name(), ".toml"))
		}
	}

	return templates, nil
}

// GetTemplate 获取配置模板
func (cm *ConfigManager) GetTemplate(templateName string) (*EasyTierConfig, error) {
	templatePath := filepath.Join(cm.templateDir, templateName+".toml")
	if _, err := os.Stat(templatePath); os.IsNotExist(err) {
		return nil, fmt.Errorf("模板不存在: %s", templateName)
	}

	data, err := os.ReadFile(templatePath)
	if err != nil {
		return nil, fmt.Errorf("读取模板失败: %v", err)
	}

	var config EasyTierConfig
	if err := toml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("解析模板失败: %v", err)
	}

	return &config, nil
}

// getDefaultConfig 获取默认配置
func (cm *ConfigManager) getDefaultConfig() *EasyTierConfig {
	return &EasyTierConfig{
		Network: struct {
			Name    string `toml:"name"`
			IP4Cidr string `toml:"ipv4_cidr"`
			IP6Cidr string `toml:"ipv6_cidr,omitempty"`
		}{
			Name:    "EasyTier-Network",
			IP4Cidr: "10.0.0.0/24",
		},
		Peers: []struct {
			URI string `toml:"uri"`
		}{
			{URI: "tcp://public.easytier.top:11010"},
		},
		DHCP: struct {
			Enabled bool   `toml:"enabled"`
			IP4Pool string `toml:"ipv4_pool,omitempty"`
			IP6Pool string `toml:"ipv6_pool,omitempty"`
		}{
			Enabled: true,
			IP4Pool: "10.0.0.100-10.0.0.200",
		},
		Routing: struct {
			Enabled       bool `toml:"enabled"`
			Table         int  `toml:"table,omitempty"`
			TablePriority int  `toml:"table_priority,omitempty"`
		}{
			Enabled: false,
		},
		NAT: struct {
			Enabled bool `toml:"enabled"`
		}{
			Enabled: false,
		},
		DevName: "easytier0",
	}
}