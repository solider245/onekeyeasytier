package web

import (
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"time"

	"github.com/onekeyeasytier/web/internal/config"
	"github.com/onekeyeasytier/web/internal/detector"
	"github.com/onekeyeasytier/web/internal/service"
	"github.com/sirupsen/logrus"
)

// Config Web服务器配置
type Config struct {
	Port       int    `json:"port"`
	ConfigDir  string `json:"config_dir"`
	BinaryDir  string `json:"binary_dir"`
	EnableAuth bool   `json:"enable_auth"`
	Username   string `json:"username"`
	Password   string `json:"password"`
}

// Server Web服务器
type Server struct {
	config        *Config
	detector      *detector.Detector
	configManager *config.ConfigManager
	serviceCtrl   *service.ServiceController
	logger        *logrus.Logger
	server        *http.Server
}

// NewServer 创建Web服务器
func NewServer(cfg *Config) (*Server, error) {
	// 初始化日志
	logger := logrus.New()
	logger.SetFormatter(&logrus.JSONFormatter{})

	// 初始化检测器
	det := detector.NewDetector(cfg.ConfigDir, cfg.BinaryDir)

	// 初始化配置管理器
	configMgr := config.NewConfigManager(
		filepath.Join(cfg.ConfigDir, "easytier.toml"),
		filepath.Join(cfg.ConfigDir, "backups"),
		filepath.Join("configs", "templates"),
	)

	// 初始化服务控制器
	serviceCtrl := service.NewServiceController(
		filepath.Join(cfg.BinaryDir, "easytier-core"),
		filepath.Join(cfg.ConfigDir, "easytier.toml"),
		"easytier",
	)

	return &Server{
		config:        cfg,
		detector:      det,
		configManager: configMgr,
		serviceCtrl:   serviceCtrl,
		logger:        logger,
	}, nil
}

// Start 启动Web服务器
func (s *Server) Start() error {
	mux := http.NewServeMux()

	// 静态文件服务
	mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("web/static"))))

	// 页面路由
	mux.HandleFunc("/", s.indexHandler)
	mux.HandleFunc("/dashboard", s.dashboardHandler)
	mux.HandleFunc("/config", s.configHandler)
	mux.HandleFunc("/logs", s.logsHandler)

	// API路由
	mux.HandleFunc("/api/status", s.authMiddleware(s.statusHandler))
	mux.HandleFunc("/api/config", s.authMiddleware(s.configAPIHandler))
	mux.HandleFunc("/api/service/start", s.authMiddleware(s.serviceStartHandler))
	mux.HandleFunc("/api/service/stop", s.authMiddleware(s.serviceStopHandler))
	mux.HandleFunc("/api/service/restart", s.authMiddleware(s.serviceRestartHandler))
	mux.HandleFunc("/api/service/reload", s.authMiddleware(s.serviceReloadHandler))
	mux.HandleFunc("/api/logs", s.authMiddleware(s.logsAPIHandler))
	mux.HandleFunc("/api/templates", s.authMiddleware(s.templatesHandler))

	s.server = &http.Server{
		Addr:    fmt.Sprintf(":%d", s.config.Port),
		Handler: mux,
	}

	s.logger.WithField("port", s.config.Port).Info("Web服务器启动")
	return s.server.ListenAndServe()
}

// Stop 停止Web服务器
func (s *Server) Stop() error {
	if s.server != nil {
		return s.server.Close()
	}
	return nil
}

// authMiddleware 认证中间件
func (s *Server) authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.config.EnableAuth {
			next(w, r)
			return
		}

		username, password, ok := r.BasicAuth()
		if !ok || username != s.config.Username || password != s.config.Password {
			w.Header().Set("WWW-Authenticate", `Basic realm="EasyTier Web Manager"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		next(w, r)
	}
}

// indexHandler 首页处理器
func (s *Server) indexHandler(w http.ResponseWriter, r *http.Request) {
	http.Redirect(w, r, "/dashboard", http.StatusFound)
}

// dashboardHandler 仪表板处理器
func (s *Server) dashboardHandler(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EasyTier Web管理器</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-primary">
        <div class="container">
            <a class="navbar-brand" href="/"><i class="fas fa-network-wired"></i> EasyTier Web管理器</a>
            <div class="navbar-nav ms-auto">
                <a class="nav-link active" href="/dashboard"><i class="fas fa-tachometer-alt"></i> 仪表板</a>
                <a class="nav-link" href="/config"><i class="fas fa-cog"></i> 配置管理</a>
                <a class="nav-link" href="/logs"><i class="fas fa-file-alt"></i> 日志查看</a>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        <div class="row">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h5><i class="fas fa-server"></i> 系统状态</h5>
                    </div>
                    <div class="card-body">
                        <div id="system-info">加载中...</div>
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h5><i class="fas fa-play-circle"></i> 服务控制</h5>
                    </div>
                    <div class="card-body">
                        <div id="service-info">加载中...</div>
                        <div class="mt-3">
                            <button class="btn btn-success" onclick="startService()"><i class="fas fa-play"></i> 启动</button>
                            <button class="btn btn-warning" onclick="stopService()"><i class="fas fa-stop"></i> 停止</button>
                            <button class="btn btn-info" onclick="restartService()"><i class="fas fa-redo"></i> 重启</button>
                            <button class="btn btn-secondary" onclick="reloadService()"><i class="fas fa-sync"></i> 重载</button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function loadStatus() {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('system-info').innerHTML = 
                        '<p><strong>操作系统:</strong> ' + data.system.os + '</p>' +
                        '<p><strong>架构:</strong> ' + data.system.arch + '</p>' +
                        '<p><strong>服务管理器:</strong> ' + data.system.service_manager + '</p>' +
                        '<p><strong>配置文件:</strong> ' + (data.system.components.config_file || '未找到') + '</p>' +
                        '<p><strong>二进制文件:</strong> ' + (data.system.components.binary_path || '未找到') + '</p>';
                    
                    var statusHtml = '<p><strong>状态:</strong> ' + (data.service.running ? '<span class="text-success">运行中</span>' : '<span class="text-danger">已停止</span>') + '</p>' +
                                   '<p><strong>PID:</strong> ' + (data.service.pid || '无') + '</p>' +
                                   '<p><strong>运行时间:</strong> ' + (data.service.uptime || '无') + '</p>';
                    document.getElementById('service-info').innerHTML = statusHtml;
                })
                .catch(error => {
                    console.error('获取状态失败:', error);
                });
        }

        function startService() {
            fetch('/api/service/start', { method: 'POST' })
                .then(response => response.json())
                .then(data => {
                    alert(data.message);
                    loadStatus();
                })
                .catch(error => {
                    alert('启动服务失败');
                });
        }

        function stopService() {
            if (confirm('确定要停止服务吗？')) {
                fetch('/api/service/stop', { method: 'POST' })
                    .then(response => response.json())
                    .then(data => {
                        alert(data.message);
                        loadStatus();
                    })
                    .catch(error => {
                        alert('停止服务失败');
                    });
            }
        }

        function restartService() {
            if (confirm('确定要重启服务吗？')) {
                fetch('/api/service/restart', { method: 'POST' })
                    .then(response => response.json())
                    .then(data => {
                        alert(data.message);
                        loadStatus();
                    })
                    .catch(error => {
                        alert('重启服务失败');
                    });
            }
        }

        function reloadService() {
            fetch('/api/service/reload', { method: 'POST' })
                .then(response => response.json())
                .then(data => {
                    alert(data.message);
                    loadStatus();
                })
                .catch(error => {
                    alert('重载服务失败');
                });
        }

        // 页面加载时获取状态
        document.addEventListener('DOMContentLoaded', loadStatus);
        // 每5秒刷新一次状态
        setInterval(loadStatus, 5000);
    </script>
</body>
</html>`
	
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, html)
}

// configHandler 配置页面处理器
func (s *Server) configHandler(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>配置管理 - EasyTier Web管理器</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-primary">
        <div class="container">
            <a class="navbar-brand" href="/"><i class="fas fa-network-wired"></i> EasyTier Web管理器</a>
            <div class="navbar-nav ms-auto">
                <a class="nav-link" href="/dashboard"><i class="fas fa-tachometer-alt"></i> 仪表板</a>
                <a class="nav-link active" href="/config"><i class="fas fa-cog"></i> 配置管理</a>
                <a class="nav-link" href="/logs"><i class="fas fa-file-alt"></i> 日志查看</a>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        <div class="row">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5><i class="fas fa-edit"></i> 配置文件编辑</h5>
                    </div>
                    <div class="card-body">
                        <div class="mb-3">
                            <textarea id="config-editor" class="form-control" rows="20" placeholder="请输入TOML配置..."></textarea>
                        </div>
                        <div class="d-flex justify-content-between">
                            <div>
                                <button class="btn btn-success" onclick="saveConfig()"><i class="fas fa-save"></i> 保存配置</button>
                                <button class="btn btn-info" onclick="loadConfig()"><i class="fas fa-refresh"></i> 重新加载</button>
                            </div>
                            <div>
                                <button class="btn btn-secondary" onclick="reloadService()"><i class="fas fa-sync"></i> 重载服务</button>
                            </div>
                        </div>
                        <div id="status-message" class="mt-2"></div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function loadConfig() {
            fetch('/api/config')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('config-editor').value = data.config;
                    showStatus('配置加载成功', 'success');
                })
                .catch(error => {
                    showStatus('加载配置失败: ' + error.message, 'danger');
                });
        }

        function saveConfig() {
            const config = document.getElementById('config-editor').value;
            
            fetch('/api/config', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ config: config })
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    showStatus('配置保存成功', 'success');
                } else {
                    showStatus('配置保存失败: ' + data.message, 'danger');
                }
            })
            .catch(error => {
                showStatus('保存配置失败', 'danger');
            });
        }

        function reloadService() {
            if (confirm('确定要重载服务吗？')) {
                fetch('/api/service/reload', { method: 'POST' })
                    .then(response => response.json())
                    .then(data => {
                        alert(data.message);
                    })
                    .catch(error => {
                        alert('重载服务失败');
                    });
            }
        }

        function showStatus(message, type) {
            const statusDiv = document.getElementById('status-message');
            statusDiv.innerHTML = '<div class="alert alert-' + type + '">' + message + '</div>';
            setTimeout(() => {
                statusDiv.innerHTML = '';
            }, 3000);
        }

        // 页面加载时加载配置
        document.addEventListener('DOMContentLoaded', loadConfig);
    </script>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, html)
}

// logsHandler 日志页面处理器
func (s *Server) logsHandler(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>日志查看 - EasyTier Web管理器</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-primary">
        <div class="container">
            <a class="navbar-brand" href="/"><i class="fas fa-network-wired"></i> EasyTier Web管理器</a>
            <div class="navbar-nav ms-auto">
                <a class="nav-link" href="/dashboard"><i class="fas fa-tachometer-alt"></i> 仪表板</a>
                <a class="nav-link" href="/config"><i class="fas fa-cog"></i> 配置管理</a>
                <a class="nav-link active" href="/logs"><i class="fas fa-file-alt"></i> 日志查看</a>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        <div class="card">
            <div class="card-header">
                <h5><i class="fas fa-terminal"></i> 服务日志</h5>
            </div>
            <div class="card-body">
                <div class="mb-3">
                    <div class="input-group">
                        <input type="number" class="form-control" id="log-lines" value="50" min="10" max="200" placeholder="日志行数">
                        <button class="btn btn-primary" onclick="refreshLogs()">刷新</button>
                    </div>
                </div>
                <div id="log-container" class="border p-3" style="height: 400px; overflow-y: auto; background-color: #f8f9fa; font-family: monospace; font-size: 12px;">
                    <div class="text-muted">点击刷新按钮加载日志...</div>
                </div>
                <div class="mt-2">
                    <small class="text-muted">最后更新: <span id="last-update">--</span></small>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function refreshLogs() {
            const lines = document.getElementById('log-lines').value || 50;
            
            fetch('/api/logs?lines=' + lines)
                .then(response => response.json())
                .then(data => {
                    const container = document.getElementById('log-container');
                    if (data.logs && data.logs.length > 0) {
                        container.innerHTML = data.logs.map(log => 
                            '<div style="margin-bottom: 2px;">' + log + '</div>'
                        ).join('');
                    } else {
                        container.innerHTML = '<div class="text-muted">暂无日志数据</div>';
                    }
                    document.getElementById('last-update').textContent = new Date().toLocaleString();
                })
                .catch(error => {
                    document.getElementById('log-container').innerHTML = 
                        '<div class="text-danger">获取日志失败: ' + error.message + '</div>';
                });
        }

        // 页面加载时刷新日志
        document.addEventListener('DOMContentLoaded', refreshLogs);
        // 每10秒自动刷新日志
        setInterval(refreshLogs, 10000);
    </script>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, html)
}

// statusHandler 状态API处理器
func (s *Server) statusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 获取系统状态
	systemStatus, err := s.detector.Detect()
	if err != nil {
		http.Error(w, fmt.Sprintf("获取系统状态失败: %v", err), http.StatusInternalServerError)
		return
	}

	// 获取服务状态
	serviceStatus, err := s.serviceCtrl.GetStatus()
	if err != nil {
		http.Error(w, fmt.Sprintf("获取服务状态失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"system":  systemStatus,
		"service": serviceStatus,
		"time":    time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// configAPIHandler 配置API处理器
func (s *Server) configAPIHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.getConfigHandler(w, r)
	case http.MethodPost:
		s.updateConfigHandler(w, r)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// getConfigHandler 获取配置
func (s *Server) getConfigHandler(w http.ResponseWriter, r *http.Request) {
	content, err := s.configManager.GetConfigContent()
	if err != nil {
		http.Error(w, fmt.Sprintf("获取配置失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"config": content,
		"time":   time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// updateConfigHandler 更新配置
func (s *Server) updateConfigHandler(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Config string `json:"config"`
	}

	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, fmt.Sprintf("解析请求失败: %v", err), http.StatusBadRequest)
		return
	}

	// 验证配置
	if err := s.configManager.ValidateConfig(request.Config); err != nil {
		http.Error(w, fmt.Sprintf("配置验证失败: %v", err), http.StatusBadRequest)
		return
	}

	// 更新配置
	config, err := s.configManager.UpdateConfig(request.Config)
	if err != nil {
		http.Error(w, fmt.Sprintf("更新配置失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"success": true,
		"message": "配置更新成功",
		"config":  config,
		"time":    time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// serviceStartHandler 启动服务处理器
func (s *Server) serviceStartHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := s.serviceCtrl.StartService(); err != nil {
		http.Error(w, fmt.Sprintf("启动服务失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"success": true,
		"message": "服务启动成功",
		"time":    time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// serviceStopHandler 停止服务处理器
func (s *Server) serviceStopHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := s.serviceCtrl.StopService(); err != nil {
		http.Error(w, fmt.Sprintf("停止服务失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"success": true,
		"message": "服务停止成功",
		"time":    time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// serviceRestartHandler 重启服务处理器
func (s *Server) serviceRestartHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := s.serviceCtrl.RestartService(); err != nil {
		http.Error(w, fmt.Sprintf("重启服务失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"success": true,
		"message": "服务重启成功",
		"time":    time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// serviceReloadHandler 重载服务处理器
func (s *Server) serviceReloadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := s.serviceCtrl.ReloadService(); err != nil {
		http.Error(w, fmt.Sprintf("重载服务失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"success": true,
		"message": "服务重载成功",
		"time":    time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// logsAPIHandler 日志API处理器
func (s *Server) logsAPIHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 获取行数参数
	lines := 50
	if l := r.URL.Query().Get("lines"); l != "" {
		if _, err := fmt.Sscanf(l, "%d", &lines); err != nil {
			lines = 50
		}
	}

	logs, err := s.serviceCtrl.GetServiceLogs(lines)
	if err != nil {
		http.Error(w, fmt.Sprintf("获取日志失败: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"logs": logs,
		"time": time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// templatesHandler 模板API处理器
func (s *Server) templatesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 获取模板列表
	templates, err := s.configManager.GetTemplateList()
	if err != nil {
		http.Error(w, fmt.Sprintf("获取模板列表失败: %v", err), http.StatusInternalServerError)
		return
	}

	// 获取模板内容
	templateContents := make(map[string]string)
	for _, template := range templates {
		if config, err := s.configManager.GetTemplate(template); err == nil {
			templateContents[template] = s.configToToml(config)
		}
	}

	response := map[string]interface{}{
		"templates": templateContents,
		"time":     time.Now().Format("2006-01-02 15:04:05"),
	}

	s.jsonResponse(w, response)
}

// jsonResponse JSON响应
func (s *Server) jsonResponse(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(data); err != nil {
		s.logger.WithError(err).Error("JSON编码失败")
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// configToToml 配置转TOML字符串
func (s *Server) configToToml(config *config.EasyTierConfig) string {
	return fmt.Sprintf("%+v", config)
}