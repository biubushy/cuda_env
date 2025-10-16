#!/bin/bash

# CUDA容器自动化创建脚本
# 功能：为每个用户创建隔离的CUDA环境容器

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker未安装，请先安装Docker"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker服务未运行或当前用户无权限访问Docker"
        exit 1
    fi
    
    print_success "Docker环境检查通过"
}

# 检查NVIDIA Docker运行时
check_nvidia_docker() {
    if ! docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        print_warning "NVIDIA Docker运行时可能未正确配置"
        read -p "是否继续？(y/n): " continue
        if [ "$continue" != "y" ]; then
            exit 1
        fi
    else
        print_success "NVIDIA Docker运行时检查通过"
    fi
}

# 配置文件路径
CONFIG_FILE="$(pwd)/.workspace_config"
DEFAULT_BASE_WORKSPACE="/home/cuda-container/workspace"

# 读取上次使用的基础工作目录
load_base_workspace() {
    if [ -f "$CONFIG_FILE" ]; then
        BASE_WORKSPACE=$(cat "$CONFIG_FILE")
        print_info "读取到上次的基础工作目录: $BASE_WORKSPACE"
    else
        BASE_WORKSPACE="$DEFAULT_BASE_WORKSPACE"
        print_info "使用默认基础工作目录: $BASE_WORKSPACE"
    fi
}

# 保存基础工作目录配置
save_base_workspace() {
    echo "$BASE_WORKSPACE" > "$CONFIG_FILE"
}

# 选择Ubuntu版本
select_ubuntu_version() {
    echo ""
    echo "========================================="
    echo "     选择Ubuntu版本"
    echo "========================================="
    echo "1) Ubuntu 22.04 (使用 Dockerfile)"
    echo "2) Ubuntu 24.04 (使用 Dockerfile.ubuntu24.04)"
    echo ""
    
    while true; do
        read -p "请选择Ubuntu版本 (1/2，默认1): " version_choice
        
        if [ -z "$version_choice" ]; then
            version_choice="1"
        fi
        
        case $version_choice in
            1)
                UBUNTU_VERSION="22.04"
                DOCKERFILE_PATH="Dockerfile"
                IMAGE_TAG="cuda-env:12.8-ubuntu22.04"
                print_success "已选择: Ubuntu 22.04"
                break
                ;;
            2)
                UBUNTU_VERSION="24.04"
                DOCKERFILE_PATH="Dockerfile.ubuntu24.04"
                IMAGE_TAG="cuda-env:12.8-ubuntu24.04"
                print_success "已选择: Ubuntu 24.04"
                break
                ;;
            *)
                print_error "无效选择，请输入1或2"
                ;;
        esac
    done
}

# 构建基础镜像
build_base_image() {
    if docker images | grep -q "cuda-env.*12.8-ubuntu${UBUNTU_VERSION}"; then
        print_info "基础镜像已存在: $IMAGE_TAG"
        read -p "是否重新构建？(y/n，默认n): " rebuild
        if [ "$rebuild" != "y" ]; then
            return 0
        fi
    fi
    
    print_info "开始构建CUDA基础镜像: $IMAGE_TAG"
    
    if [ ! -f "$DOCKERFILE_PATH" ]; then
        print_error "Dockerfile不存在: $DOCKERFILE_PATH"
        exit 1
    fi
    
    docker build -f "$DOCKERFILE_PATH" -t "$IMAGE_TAG" . || {
        print_error "镜像构建失败"
        exit 1
    }
    
    print_success "基础镜像构建完成: $IMAGE_TAG"
}

# 获取用户输入
get_user_input() {
    echo ""
    echo "========================================="
    echo "     CUDA容器创建配置向导"
    echo "========================================="
    echo ""
    
    # 用户名
    while true; do
        read -p "请输入用户名（容器名将以此命名）: " USERNAME
        if [ -z "$USERNAME" ]; then
            print_error "用户名不能为空"
            continue
        fi
        
        # 检查容器是否已存在
        if docker ps -a --format '{{.Names}}' | grep -q "^cuda-${USERNAME}$"; then
            print_error "容器 cuda-${USERNAME} 已存在"
            read -p "是否删除现有容器并重新创建？(y/n): " recreate
            if [ "$recreate" = "y" ]; then
                docker rm -f "cuda-${USERNAME}" 2>/dev/null || true
                break
            fi
        else
            break
        fi
    done
    
    CONTAINER_NAME="cuda-${USERNAME}"
    
    # Root密码
    while true; do
        read -s -p "请输入root用户密码: " ROOT_PASSWORD
        echo ""
        read -s -p "请再次确认root密码: " ROOT_PASSWORD_CONFIRM
        echo ""
        
        if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
            print_error "两次密码输入不一致"
            continue
        fi
        
        if [ -z "$ROOT_PASSWORD" ]; then
            print_error "密码不能为空"
            continue
        fi
        
        break
    done
    
    # Code-server密码
    read -s -p "请输入Code-server密码（留空使用root密码）: " CODESERVER_PASSWORD
    echo ""
    if [ -z "$CODESERVER_PASSWORD" ]; then
        CODESERVER_PASSWORD="$ROOT_PASSWORD"
    fi
    
    # GPU资源
    echo ""
    print_info "可用GPU列表："
    nvidia-smi -L 2>/dev/null || print_warning "无法列出GPU，请手动输入"
    echo ""
    read -p "请输入要分配的GPU ID（多个用逗号分隔，如0,1 或 all）: " GPU_IDS
    if [ -z "$GPU_IDS" ]; then
        GPU_IDS="all"
    fi
    
    # CPU资源
    read -p "请输入CPU核心数限制（默认不限制，输入数字如4）: " CPU_LIMIT
    if [ -z "$CPU_LIMIT" ]; then
        CPU_LIMIT="0"
    fi
    
    # 内存资源
    read -p "请输入内存限制（如16g，默认不限制）: " MEMORY_LIMIT
    if [ -z "$MEMORY_LIMIT" ]; then
        MEMORY_LIMIT=""
    fi
    
    # 共享内存大小
    read -p "请输入共享内存大小（如8g，默认16g）: " SHM_SIZE
    if [ -z "$SHM_SIZE" ]; then
        SHM_SIZE="16g"
    fi
    
    # SSH端口
    while true; do
        read -p "请输入SSH端口（默认自动分配从22001开始）: " SSH_PORT
        if [ -z "$SSH_PORT" ]; then
            # 自动分配端口
            SSH_PORT=22001
            while netstat -tuln 2>/dev/null | grep -q ":$SSH_PORT " || docker ps --format '{{.Ports}}' | grep -q "$SSH_PORT"; do
                ((SSH_PORT++))
            done
            print_info "自动分配SSH端口: $SSH_PORT"
            break
        fi
        
        # 检查端口是否被占用
        if netstat -tuln 2>/dev/null | grep -q ":$SSH_PORT " || docker ps --format '{{.Ports}}' | grep -q "$SSH_PORT"; then
            print_error "端口 $SSH_PORT 已被占用"
            continue
        fi
        
        break
    done
    
    # Code-server端口
    while true; do
        read -p "请输入Code-server端口（默认自动分配从8080开始）: " CODESERVER_PORT
        if [ -z "$CODESERVER_PORT" ]; then
            # 自动分配端口
            CODESERVER_PORT=8080
            while netstat -tuln 2>/dev/null | grep -q ":$CODESERVER_PORT " || docker ps --format '{{.Ports}}' | grep -q "$CODESERVER_PORT"; do
                ((CODESERVER_PORT++))
            done
            print_info "自动分配Code-server端口: $CODESERVER_PORT"
            break
        fi
        
        # 检查端口是否被占用
        if netstat -tuln 2>/dev/null | grep -q ":$CODESERVER_PORT " || docker ps --format '{{.Ports}}' | grep -q "$CODESERVER_PORT"; then
            print_error "端口 $CODESERVER_PORT 已被占用"
            continue
        fi
        
        break
    done
    
    # 工作目录映射 - 改进版
    echo ""
    echo "----------------------------------------"
    echo "工作目录配置"
    echo "----------------------------------------"
    echo "当前基础工作目录: $BASE_WORKSPACE"
    echo "容器工作目录将映射到: ${BASE_WORKSPACE}/${USERNAME}"
    echo ""
    read -p "是否修改基础工作目录？(y/n，默认n): " change_base
    
    if [ "$change_base" = "y" ]; then
        read -p "请输入新的基础工作目录 (如 /data/workspaces): " new_base
        if [ -n "$new_base" ]; then
            BASE_WORKSPACE="$new_base"
            print_info "基础工作目录已更新为: $BASE_WORKSPACE"
        fi
    fi
    
    # 构建实际的工作目录路径
    HOST_WORKSPACE="${BASE_WORKSPACE}/${USERNAME}"
    
    # 创建目录
    if [ ! -d "$HOST_WORKSPACE" ]; then
        mkdir -p "$HOST_WORKSPACE" || {
            print_error "无法创建目录: $HOST_WORKSPACE"
            exit 1
        }
        print_success "创建工作目录: $HOST_WORKSPACE"
    else
        print_info "工作目录已存在: $HOST_WORKSPACE"
    fi
    
    # 保存配置
    save_base_workspace
    
    # 代理配置
    echo ""
    echo "----------------------------------------"
    echo "代理配置（可选）"
    echo "----------------------------------------"
    echo "如果需要通过宿主机代理访问网络（如科学上网），可以在此配置"
    echo ""
    read -p "是否配置宿主机代理？(y/n，默认n): " use_proxy
    
    if [ "$use_proxy" = "y" ]; then
        USE_PROXY="true"
        
        # 获取代理地址
        while true; do
            read -p "请输入宿主机IP地址（如 192.168.1.100）: " PROXY_HOST
            if [ -z "$PROXY_HOST" ]; then
                print_error "代理地址不能为空"
                continue
            fi
            break
        done
        
        # 获取代理端口
        while true; do
            read -p "请输入代理端口（如 7890）: " PROXY_PORT
            if [ -z "$PROXY_PORT" ]; then
                print_error "代理端口不能为空"
                continue
            fi
            if ! [[ "$PROXY_PORT" =~ ^[0-9]+$ ]]; then
                print_error "端口必须是数字"
                continue
            fi
            break
        done
        
        # 构建代理URL
        HTTP_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
        HTTPS_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
        
        # NO_PROXY配置
        read -p "请输入不走代理的地址（多个用逗号分隔，默认localhost,127.0.0.1）: " NO_PROXY
        if [ -z "$NO_PROXY" ]; then
            NO_PROXY="localhost,127.0.0.1"
        fi
        
        print_success "代理配置完成"
        echo "  HTTP代理:  $HTTP_PROXY"
        echo "  HTTPS代理: $HTTPS_PROXY"
        echo "  NO_PROXY:  $NO_PROXY"
    else
        USE_PROXY="false"
        HTTP_PROXY=""
        HTTPS_PROXY=""
        NO_PROXY=""
    fi
    
    # 确认信息
    echo ""
    echo "========================================="
    echo "           配置信息确认"
    echo "========================================="
    echo "用户名:           $USERNAME"
    echo "容器名:           $CONTAINER_NAME"
    echo "GPU资源:          $GPU_IDS"
    echo "CPU限制:          $([ "$CPU_LIMIT" = "0" ] && echo "无限制" || echo "${CPU_LIMIT}核")"
    echo "内存限制:         $([ -z "$MEMORY_LIMIT" ] && echo "无限制" || echo "$MEMORY_LIMIT")"
    echo "共享内存:         $SHM_SIZE"
    echo "SSH端口:          $SSH_PORT"
    echo "Code-server端口:  $CODESERVER_PORT"
    echo "工作目录:         $HOST_WORKSPACE"
    echo "使用代理:         $([ "$USE_PROXY" = "true" ] && echo "是 ($HTTP_PROXY)" || echo "否")"
    echo "========================================="
    echo ""
    
    read -p "确认创建容器？(y/n): " confirm
    if [ "$confirm" != "y" ]; then
        print_warning "用户取消操作"
        exit 0
    fi
}

# 创建容器
create_container() {
    print_info "开始创建容器: $CONTAINER_NAME"
    
    # 构建docker run命令
    local docker_cmd="docker run -d --restart=unless-stopped"
    
    # 添加GPU支持
    if [ "$GPU_IDS" = "all" ]; then
        docker_cmd="$docker_cmd --gpus all"
    else
        docker_cmd="$docker_cmd --gpus '\"device=$GPU_IDS\"'"
    fi
    
    # 添加CPU限制
    if [ "$CPU_LIMIT" != "0" ]; then
        docker_cmd="$docker_cmd --cpus=$CPU_LIMIT"
    fi
    
    # 添加内存限制
    if [ -n "$MEMORY_LIMIT" ]; then
        docker_cmd="$docker_cmd --memory=$MEMORY_LIMIT"
    fi
    
    # 添加共享内存大小
    docker_cmd="$docker_cmd --shm-size=$SHM_SIZE"
    
    # 添加端口映射
    docker_cmd="$docker_cmd -p $SSH_PORT:22 -p $CODESERVER_PORT:8080"
    
    # 添加卷映射
    docker_cmd="$docker_cmd -v $HOST_WORKSPACE:/workspace"
    docker_cmd="$docker_cmd -v $(pwd)/banner.txt:/etc/banner.txt:ro"
    
    # 添加环境变量
    docker_cmd="$docker_cmd -e CODESERVER_PASSWORD='$CODESERVER_PASSWORD'"
    docker_cmd="$docker_cmd -e CONTAINER_USERNAME='$USERNAME'"
    docker_cmd="$docker_cmd -e CONTAINER_SSH_PORT='$SSH_PORT'"
    docker_cmd="$docker_cmd -e CONTAINER_CODESERVER_PORT='$CODESERVER_PORT'"
    docker_cmd="$docker_cmd -e CONTAINER_SYNCTHING_PORT='8384'"
    
    # 添加代理环境变量
    if [ "$USE_PROXY" = "true" ]; then
        docker_cmd="$docker_cmd -e USE_PROXY='true'"
        docker_cmd="$docker_cmd -e HTTP_PROXY='$HTTP_PROXY'"
        docker_cmd="$docker_cmd -e HTTPS_PROXY='$HTTPS_PROXY'"
        docker_cmd="$docker_cmd -e http_proxy='$HTTP_PROXY'"
        docker_cmd="$docker_cmd -e https_proxy='$HTTPS_PROXY'"
        docker_cmd="$docker_cmd -e NO_PROXY='$NO_PROXY'"
        docker_cmd="$docker_cmd -e no_proxy='$NO_PROXY'"
    fi
    
    # 添加容器名和镜像
    docker_cmd="$docker_cmd --name $CONTAINER_NAME"
    docker_cmd="$docker_cmd --hostname $CONTAINER_NAME"
    docker_cmd="$docker_cmd $IMAGE_TAG"
    
    # 执行创建命令
    print_info "执行: $docker_cmd"
    eval $docker_cmd || {
        print_error "容器创建失败"
        exit 1
    }
    
    # 等待容器启动
    print_info "等待容器启动..."
    sleep 3
    
    # 设置root密码
    print_info "配置root密码..."
    docker exec $CONTAINER_NAME bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd" || {
        print_error "设置root密码失败"
        exit 1
    }
    
    print_success "容器创建成功！"
}

# 显示连接信息
show_connection_info() {
    echo ""
    echo "========================================="
    echo "          容器创建完成"
    echo "========================================="
    echo ""
    print_success "容器名称: $CONTAINER_NAME"
    echo ""
    echo "SSH连接信息："
    echo "  地址: localhost:$SSH_PORT"
    echo "  用户: root"
    echo "  密码: ********"
    echo "  命令: ssh root@localhost -p $SSH_PORT"
    echo ""
    echo "Code-server信息："
    echo "  地址: http://localhost:$CODESERVER_PORT"
    echo "  密码: ********"
    echo ""
    echo "容器管理命令："
    echo "  查看日志:   docker logs $CONTAINER_NAME"
    echo "  进入容器:   docker exec -it $CONTAINER_NAME bash"
    echo "  停止容器:   docker stop $CONTAINER_NAME"
    echo "  启动容器:   docker start $CONTAINER_NAME"
    echo "  删除容器:   docker rm -f $CONTAINER_NAME"
    echo ""
    echo "工作目录: $HOST_WORKSPACE"
    echo ""
    echo "========================================="
    
    # 保存信息到文件
    local info_file="$(pwd)/containers/${USERNAME}.txt"
    mkdir -p "$(pwd)/containers"
    
    cat > "$info_file" << EOF
容器名称: $CONTAINER_NAME
创建时间: $(date '+%Y-%m-%d %H:%M:%S')

SSH连接:
  端口: $SSH_PORT
  用户: root
  命令: ssh root@localhost -p $SSH_PORT

Code-server:
  端口: $CODESERVER_PORT
  地址: http://localhost:$CODESERVER_PORT

资源配置:
  GPU: $GPU_IDS
  CPU: $([ "$CPU_LIMIT" = "0" ] && echo "无限制" || echo "${CPU_LIMIT}核")
  内存: $([ -z "$MEMORY_LIMIT" ] && echo "无限制" || echo "$MEMORY_LIMIT")
  共享内存: $SHM_SIZE

工作目录: $HOST_WORKSPACE
EOF
    
    print_info "容器信息已保存到: $info_file"
}

# 主函数
main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   CUDA容器自动化创建脚本             ║"
    echo "║   支持GPU/CPU/内存资源限制            ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    # 检查环境
    check_docker
    check_nvidia_docker
    
    # 选择Ubuntu版本
    select_ubuntu_version
    
    # 加载基础工作目录配置
    load_base_workspace
    
    # 构建基础镜像
    build_base_image
    
    # 获取用户输入
    get_user_input
    
    # 创建容器
    create_container
    
    # 显示连接信息
    show_connection_info
    
    echo ""
    print_success "全部完成！容器已在后台运行"
    echo ""
}

# 运行主函数
main

