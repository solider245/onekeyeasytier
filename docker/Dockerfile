# 多阶段构建
FROM golang:1.21-alpine AS builder

# 安装必要的工具
RUN apk add --no-cache git ca-certificates tzdata

# 设置工作目录
WORKDIR /app

# 复制go mod文件
COPY go.mod go.sum ./

# 下载依赖
RUN go mod download

# 复制源代码
COPY . .

# 构建应用
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o easytier-web cmd/web/main.go

# 运行阶段
FROM alpine:latest

# 安装必要的工具
RUN apk --no-cache add ca-certificates bash curl

# 创建用户和组
RUN addgroup -g 1000 easytier && \
    adduser -u 1000 -G easytier -s /bin/sh -D easytier

# 创建必要的目录
RUN mkdir -p /etc/easytier /var/log/easytier /usr/local/bin && \
    chown -R easytier:easytier /etc/easytier /var/log/easytier /usr/local/bin

# 设置工作目录
WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder /app/easytier-web /usr/local/bin/

# 复制配置模板
COPY configs/ /app/configs/

# 复制Web静态文件
COPY web/ /app/web/

# 创建符号链接
RUN ln -sf /usr/local/bin/easytier-web /usr/bin/easytier-web

# 创建默认配置文件
RUN echo "# EasyTier默认配置文件" > /etc/easytier/easytier.toml

# 设置环境变量
ENV EASYTIER_CONFIG_DIR=/etc/easytier
ENV EASYTIER_BINARY_DIR=/usr/local/bin
ENV EASYTIER_WEB_PORT=8080
ENV EASYTIER_ENABLE_AUTH=false
ENV EASYTIER_USERNAME=admin
ENV EASYTIER_PASSWORD=easytier

# 创建启动脚本
RUN echo '#!/bin/bash' > /app/start.sh && \
    echo '# 如果环境变量指定了EasyTier二进制文件，下载它' >> /app/start.sh && \
    echo 'if [ ! -z "$EASYTIER_DOWNLOAD_URL" ]; then' >> /app/start.sh && \
    echo '    echo "下载EasyTier二进制文件..."' >> /app/start.sh && \
    echo '    curl -L -o /tmp/easytier.zip "$EASYTIER_DOWNLOAD_URL"' >> /app/start.sh && \
    echo '    cd /tmp && unzip easytier.zip' >> /app/start.sh && \
    echo '    cp easytier-core easytier-cli /usr/local/bin/' >> /app/start.sh && \
    echo '    chmod +x /usr/local/bin/easytier-*' >> /app/start.sh && \
    echo '    rm -f /tmp/easytier.zip' >> /app/start.sh && \
    echo 'fi' >> /app/start.sh && \
    echo '' >> /app/start.sh && \
    echo '# 启动Web管理器' >> /app/start.sh && \
    echo 'exec /usr/local/bin/easytier-web \\ ' >> /app/start.sh && \
    echo '    --port=${EASYTIER_WEB_PORT:-8080} \\ ' >> /app/start.sh && \
    echo '    --config-dir=${EASYTIER_CONFIG_DIR:-/etc/easytier} \\ ' >> /app/start.sh && \
    echo '    --binary-dir=${EASYTIER_BINARY_DIR:-/usr/local/bin} \\ ' >> /app/start.sh && \
    echo '    --enable-auth=${EASYTIER_ENABLE_AUTH:-false} \\ ' >> /app/start.sh && \
    echo '    --username=${EASYTIER_USERNAME:-admin} \\ ' >> /app/start.sh && \
    echo '    --password=${EASYTIER_PASSWORD:-easytier}' >> /app/start.sh && \
    chmod +x /app/start.sh

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/api/status || exit 1

# 切换到非root用户
USER easytier

# 设置启动命令
CMD ["/app/start.sh"]