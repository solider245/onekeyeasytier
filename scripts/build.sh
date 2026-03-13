#!/bin/bash

# OneKeyEasyTier Web管理器构建脚本
# 用于构建Docker镜像和部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目信息
PROJECT_NAME="easytier-web"
VERSION="1.0.0"
DOCKER_IMAGE="easytier/web-manager"
DOCKER_TAG="${VERSION}"

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

# 显示帮助信息
show_help() {
    cat << EOF
OneKeyEasyTier Web管理器构建脚本

用法: $0 [选项]

选项:
    build       构建Docker镜像
    deploy      部署Docker容器
    stop        停止容器
    restart     重启容器
    logs        查看容器日志
    clean       清理容器和镜像
    status      查看容器状态
    help        显示帮助信息

示例:
    $0 build                    # 构建Docker镜像
    $0 deploy                   # 部署容器
    $0 deploy --with-core       # 部署容器并启动EasyTier核心服务
    $0 logs                     # 查看日志
    $0 clean                    # 清理

EOF
}

# 构建Docker镜像
build_image() {
    log_info "开始构建Docker镜像..."
    
    # 检查Docker是否安装
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        exit 1
    fi
    
    # 检查Dockerfile是否存在
    if [ ! -f "docker/Dockerfile" ]; then
        log_error "Dockerfile不存在: docker/Dockerfile"
        exit 1
    fi
    
    # 构建镜像
    docker build -t "${DOCKER_IMAGE}:${DOCKER_TAG}" -f docker/Dockerfile ..
    docker tag "${DOCKER_IMAGE}:${DOCKER_TAG}" "${DOCKER_IMAGE}:latest"
    
    log_success "Docker镜像构建完成: ${DOCKER_IMAGE}:${DOCKER_TAG}"
}

# 部署Docker容器
deploy_container() {
    log_info "开始部署Docker容器..."
    
    # 检查docker-compose.yml是否存在
    if [ ! -f "docker/docker-compose.yml" ]; then
        log_error "docker-compose.yml不存在: docker/docker-compose.yml"
        exit 1
    fi
    
    # 检查是否已有容器运行
    if docker ps -q -f name=${PROJECT_NAME} | grep -q .; then
        log_warning "容器已运行，停止现有容器..."
        docker-compose -f docker/docker-compose.yml down
    fi
    
    # 部署容器
    if [ "$1" = "--with-core" ]; then
        log_info "部署包含EasyTier核心服务的容器..."
        docker-compose -f docker/docker-compose.yml --profile with-core up -d
    else
        docker-compose -f docker/docker-compose.yml up -d
    fi
    
    log_success "容器部署完成"
    log_info "Web管理器地址: http://localhost:8080"
}

# 停止容器
stop_container() {
    log_info "停止容器..."
    
    if [ -f "docker/docker-compose.yml" ]; then
        docker-compose -f docker/docker-compose.yml down
    else
        docker stop ${PROJECT_NAME} 2>/dev/null || true
        docker rm ${PROJECT_NAME} 2>/dev/null || true
    fi
    
    log_success "容器已停止"
}

# 重启容器
restart_container() {
    log_info "重启容器..."
    
    if [ -f "docker/docker-compose.yml" ]; then
        docker-compose -f docker/docker-compose.yml restart
    else
        docker restart ${PROJECT_NAME} 2>/dev/null || log_error "容器未运行"
    fi
    
    log_success "容器已重启"
}

# 查看日志
show_logs() {
    log_info "显示容器日志..."
    
    if [ -f "docker/docker-compose.yml" ]; then
        docker-compose -f docker/docker-compose.yml logs -f easytier-web
    else
        docker logs -f ${PROJECT_NAME} 2>/dev/null || log_error "容器未运行"
    fi
}

# 清理容器和镜像
clean_all() {
    log_warning "清理容器和镜像..."
    
    read -p "确定要清理所有容器和镜像吗？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "取消清理"
        return
    fi
    
    # 停止并删除容器
    if [ -f "docker/docker-compose.yml" ]; then
        docker-compose -f docker/docker-compose.yml down -v --remove-orphans
    else
        docker stop ${PROJECT_NAME} 2>/dev/null || true
        docker rm ${PROJECT_NAME} 2>/dev/null || true
    fi
    
    # 删除镜像
    docker rmi "${DOCKER_IMAGE}:${DOCKER_TAG}" 2>/dev/null || true
    docker rmi "${DOCKER_IMAGE}:latest" 2>/dev/null || true
    
    # 清理未使用的Docker资源
    docker system prune -f
    
    log_success "清理完成"
}

# 查看状态
show_status() {
    log_info "容器状态:"
    
    if [ -f "docker/docker-compose.yml" ]; then
        docker-compose -f docker/docker-compose.yml ps
    else
        docker ps -f name=${PROJECT_NAME}
    fi
    
    echo ""
    log_info "镜像状态:"
    docker images | grep ${DOCKER_IMAGE} || echo "未找到相关镜像"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        exit 1
    fi
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_warning "Docker Compose未安装，某些功能可能不可用"
    fi
    
    # 检查Docker服务
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker服务未运行，请启动Docker服务"
        exit 1
    fi
    
    log_success "依赖检查完成"
}

# 主函数
main() {
    case "${1:-help}" in
        build)
            check_dependencies
            build_image
            ;;
        deploy)
            check_dependencies
            deploy_container "$2"
            ;;
        stop)
            stop_container
            ;;
        restart)
            restart_container
            ;;
        logs)
            show_logs
            ;;
        clean)
            clean_all
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"