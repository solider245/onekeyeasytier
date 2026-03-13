#!/bin/bash

# OneKeyEasyTier Web管理器测试脚本
# 用于测试Web管理器的各项功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 配置
WEB_PORT=8080
BASE_URL="http://localhost:${WEB_PORT}"
BINARY="./easytier-web"

# 清理函数
cleanup() {
    log_info "清理测试环境..."
    if [ ! -z "$WEB_PID" ]; then
        kill $WEB_PID 2>/dev/null || true
    fi
}

# 注册清理函数
trap cleanup EXIT

# 检查二进制文件
check_binary() {
    log_info "检查二进制文件..."
    if [ ! -f "$BINARY" ]; then
        log_error "二进制文件不存在: $BINARY"
        exit 1
    fi
    
    # 测试帮助信息
    $BINARY --help > /dev/null
    log_success "二进制文件检查通过"
}

# 启动Web服务器
start_web_server() {
    log_info "启动Web服务器..."
    
    # 检查端口是否被占用
    if lsof -i :$WEB_PORT >/dev/null 2>&1; then
        log_error "端口 $WEB_PORT 已被占用"
        exit 1
    fi
    
    # 启动服务器
    $BINARY --port $WEB_PORT --enable-auth false &
    WEB_PID=$!
    
    # 等待服务器启动
    for i in {1..10}; do
        if curl -s "$BASE_URL/api/status" >/dev/null 2>&1; then
            log_success "Web服务器启动成功 (PID: $WEB_PID)"
            return
        fi
        sleep 1
    done
    
    log_error "Web服务器启动失败"
    exit 1
}

# 测试API端点
test_api_endpoints() {
    log_info "测试API端点..."
    
    # 测试状态API
    log_info "测试 /api/status..."
    STATUS_RESPONSE=$(curl -s "$BASE_URL/api/status")
    if echo "$STATUS_RESPONSE" | grep -q "system"; then
        log_success "状态API测试通过"
    else
        log_error "状态API测试失败"
        echo "响应: $STATUS_RESPONSE"
    fi
    
    # 测试配置API
    log_info "测试 /api/config..."
    CONFIG_RESPONSE=$(curl -s "$BASE_URL/api/config")
    if echo "$CONFIG_RESPONSE" | grep -q "config"; then
        log_success "配置API测试通过"
    else
        log_error "配置API测试失败"
        echo "响应: $CONFIG_RESPONSE"
    fi
    
    # 测试模板API
    log_info "测试 /api/templates..."
    TEMPLATES_RESPONSE=$(curl -s "$BASE_URL/api/templates")
    if echo "$TEMPLATES_RESPONSE" | grep -q "templates"; then
        log_success "模板API测试通过"
    else
        log_error "模板API测试失败"
        echo "响应: $TEMPLATES_RESPONSE"
    fi
    
    # 测试日志API
    log_info "测试 /api/logs..."
    LOGS_RESPONSE=$(curl -s "$BASE_URL/api/logs?lines=10")
    if echo "$LOGS_RESPONSE" | grep -q "logs"; then
        log_success "日志API测试通过"
    else
        log_error "日志API测试失败"
        echo "响应: $LOGS_RESPONSE"
    fi
}

# 测试服务控制API
test_service_control() {
    log_info "测试服务控制API..."
    
    # 测试启动服务
    log_info "测试服务启动..."
    START_RESPONSE=$(curl -s -X POST "$BASE_URL/api/service/start")
    if echo "$START_RESPONSE" | grep -q "success"; then
        log_success "服务启动API测试通过"
    else
        log_warning "服务启动API测试失败 (可能因为缺少二进制文件)"
        echo "响应: $START_RESPONSE"
    fi
    
    # 测试停止服务
    log_info "测试服务停止..."
    STOP_RESPONSE=$(curl -s -X POST "$BASE_URL/api/service/stop")
    if echo "$STOP_RESPONSE" | grep -q "success"; then
        log_success "服务停止API测试通过"
    else
        log_warning "服务停止API测试失败 (可能因为服务未运行)"
        echo "响应: $STOP_RESPONSE"
    fi
    
    # 测试重载服务
    log_info "测试服务重载..."
    RELOAD_RESPONSE=$(curl -s -X POST "$BASE_URL/api/service/reload")
    if echo "$RELOAD_RESPONSE" | grep -q "success"; then
        log_success "服务重载API测试通过"
    else
        log_warning "服务重载API测试失败 (可能因为服务未运行)"
        echo "响应: $RELOAD_RESPONSE"
    fi
}

# 测试配置更新
test_config_update() {
    log_info "测试配置更新..."
    
    # 获取当前配置
    CURRENT_CONFIG=$(curl -s "$BASE_URL/api/config" | python3 -c "import sys, json; print(json.load(sys.stdin)['config'])")
    
    # 创建测试配置
    TEST_CONFIG='[network]
name = "Test-Network"
ipv4_cidr = "10.0.0.0/24"

[peers]
uri = "tcp://test.example.com:11010"

[dhcp]
enabled = true
ipv4_pool = "10.0.0.100-10.0.0.200"
'
    
    # 更新配置
    UPDATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/config" \
        -H "Content-Type: application/json" \
        -d "{\"config\": \"$TEST_CONFIG\"}")
    
    if echo "$UPDATE_RESPONSE" | grep -q "success"; then
        log_success "配置更新API测试通过"
        
        # 验证配置是否更新成功
        UPDATED_CONFIG=$(curl -s "$BASE_URL/api/config" | python3 -c "import sys, json; print(json.load(sys.stdin)['config'])")
        if echo "$UPDATED_CONFIG" | grep -q "Test-Network"; then
            log_success "配置更新验证通过"
        else
            log_error "配置更新验证失败"
        fi
    else
        log_error "配置更新API测试失败"
        echo "响应: $UPDATE_RESPONSE"
    fi
    
    # 恢复原始配置
    if [ ! -z "$CURRENT_CONFIG" ]; then
        curl -s -X POST "$BASE_URL/api/config" \
            -H "Content-Type: application/json" \
            -d "{\"config\": \"$CURRENT_CONFIG\"" > /dev/null
    fi
}

# 测试Web页面
test_web_pages() {
    log_info "测试Web页面..."
    
    # 测试仪表板页面
    if curl -s "$BASE_URL/dashboard" | grep -q "EasyTier Web管理器"; then
        log_success "仪表板页面测试通过"
    else
        log_error "仪表板页面测试失败"
    fi
    
    # 测试配置页面
    if curl -s "$BASE_URL/config" | grep -q "配置管理"; then
        log_success "配置页面测试通过"
    else
        log_error "配置页面测试失败"
    fi
    
    # 测试日志页面
    if curl -s "$BASE_URL/logs" | grep -q "日志查看"; then
        log_success "日志页面测试通过"
    else
        log_error "日志页面测试失败"
    fi
}

# 性能测试
test_performance() {
    log_info "测试性能..."
    
    # 测试并发请求
    log_info "测试并发请求 (10个并发请求)..."
    start_time=$(date +%s.%N)
    
    for i in {1..10}; do
        curl -s "$BASE_URL/api/status" > /dev/null &
    done
    
    wait
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc)
    
    if (( $(echo "$elapsed < 2.0" | bc -l) )); then
        log_success "并发请求性能测试通过 (${elapsed}s)"
    else
        log_warning "并发请求性能较慢 (${elapsed}s)"
    fi
}

# 主函数
main() {
    log_info "开始OneKeyEasyTier Web管理器测试..."
    
    # 检查依赖
    if ! command -v curl &> /dev/null; then
        log_error "curl 未安装，请先安装curl"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_warning "python3 未安装，某些测试可能无法进行"
    fi
    
    # 执行测试
    check_binary
    start_web_server
    test_api_endpoints
    test_service_control
    test_config_update
    test_web_pages
    test_performance
    
    log_success "所有测试完成！"
    
    # 显示访问信息
    echo ""
    log_info "Web管理器访问信息:"
    echo "  地址: $BASE_URL"
    echo "  仪表板: $BASE_URL/dashboard"
    echo "  配置管理: $BASE_URL/config"
    echo "  日志查看: $BASE_URL/logs"
    echo ""
    log_info "使用 Ctrl+C 停止服务器"
    
    # 保持服务器运行
    wait $WEB_PID
}

# 运行主函数
main "$@"