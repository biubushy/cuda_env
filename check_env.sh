#!/bin/bash

# 环境检查脚本
# 检查Docker和NVIDIA Docker环境是否正确配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[检查]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     环境检查工具                      ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# 检查Docker
print_info "检查Docker安装..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    print_success "Docker已安装: $DOCKER_VERSION"
else
    print_error "Docker未安装"
    echo "请安装Docker: https://docs.docker.com/engine/install/"
    exit 1
fi

# 检查Docker服务
print_info "检查Docker服务..."
if docker info &> /dev/null; then
    print_success "Docker服务正常运行"
else
    print_error "Docker服务未运行或权限不足"
    echo "请启动Docker服务: sudo systemctl start docker"
    echo "或将当前用户添加到docker组: sudo usermod -aG docker $USER"
    exit 1
fi

# 检查NVIDIA驱动
print_info "检查NVIDIA驱动..."
if command -v nvidia-smi &> /dev/null; then
    print_success "NVIDIA驱动已安装"
    echo ""
    nvidia-smi
    echo ""
else
    print_error "NVIDIA驱动未安装"
    echo "请安装NVIDIA驱动"
    exit 1
fi

# 检查NVIDIA Docker运行时
print_info "检查NVIDIA Docker运行时..."
if docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
    print_success "NVIDIA Docker运行时配置正确"
else
    print_error "NVIDIA Docker运行时配置有问题"
    echo "请安装NVIDIA Container Toolkit:"
    echo "https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    exit 1
fi

# 检查所需命令
print_info "检查所需命令..."
MISSING_COMMANDS=()

for cmd in curl wget git; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_COMMANDS+=($cmd)
    fi
done

if [ ${#MISSING_COMMANDS[@]} -eq 0 ]; then
    print_success "所有必需命令都已安装"
else
    print_warning "以下命令未安装: ${MISSING_COMMANDS[*]}"
    echo "建议安装: sudo apt-get install ${MISSING_COMMANDS[*]}"
fi

# 检查端口
print_info "检查常用端口占用情况..."
check_port() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo "  端口 $port: 已占用"
    else
        echo "  端口 $port: 可用"
    fi
}

check_port 22
check_port 8888
check_port 22001
check_port 8889

# 检查磁盘空间
print_info "检查磁盘空间..."
AVAILABLE_SPACE=$(df -h . | awk 'NR==2 {print $4}')
echo "  当前目录可用空间: $AVAILABLE_SPACE"

# 检查现有容器
print_info "检查现有CUDA容器..."
EXISTING_CONTAINERS=$(docker ps -a --filter "name=cuda-" --format "{{.Names}}" | wc -l)
if [ $EXISTING_CONTAINERS -eq 0 ]; then
    echo "  未发现现有CUDA容器"
else
    echo "  发现 $EXISTING_CONTAINERS 个CUDA容器"
    docker ps -a --filter "name=cuda-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
fi

# 检查镜像
print_info "检查CUDA镜像..."
if docker images | grep -q "cuda-env.*12.8"; then
    print_success "基础镜像 cuda-env:12.8 已存在"
    IMAGE_SIZE=$(docker images cuda-env:12.8 --format "{{.Size}}")
    echo "  镜像大小: $IMAGE_SIZE"
else
    print_warning "基础镜像 cuda-env:12.8 不存在"
    echo "  首次运行时会自动构建"
fi

echo ""
echo "========================================="
echo "           环境检查完成"
echo "========================================="
echo ""
print_success "环境配置正确，可以开始创建容器"
echo ""
echo "下一步："
echo "  1. 创建容器: ./create_user_container.sh"
echo "  2. 管理容器: ./manage_containers.sh"
echo "  3. 查看文档: cat README.md"
echo ""

