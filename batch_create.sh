#!/bin/bash

# 批量创建容器脚本
# 从配置文件批量创建多个用户容器

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 配置文件示例
create_sample_config() {
    cat > batch_config.example.txt << 'EOF'
# CUDA容器批量创建配置文件
# 格式：用户名|root密码|codeserver密码|GPU|CPU|内存|SSH端口|Code-server端口|工作目录|代理地址|代理端口
# 说明：
#   - 用#开头的行是注释
#   - 空行会被忽略
#   - GPU可以是：all, 0, 1, 0,1 等
#   - CPU为0表示不限制
#   - 内存为空表示不限制，否则如：16g
#   - 端口为0表示自动分配
#   - 工作目录为空表示自动创建
#   - 代理地址为空表示不使用代理，如：192.168.1.100
#   - 代理端口：如 7890

# 示例用户（不使用代理）
alice|password123|password123|0|4|16g|22001|8080|||
bob|password456|password456|1|4|16g|22002|8081|||

# 示例用户（使用代理）
charlie|password789|password789|2,3|8|32g|22003|8082|/data/charlie|192.168.1.100|7890
EOF
    
    print_success "示例配置文件已创建: batch_config.example.txt"
}

# 配置文件路径
CONFIG_FILE="$(pwd)/.workspace_config"
DEFAULT_BASE_WORKSPACE="/home/cuda-container/workspace"

# 读取上次使用的基础工作目录
load_base_workspace() {
    if [ -f "$CONFIG_FILE" ]; then
        BASE_WORKSPACE=$(cat "$CONFIG_FILE")
        print_info "读取到基础工作目录配置: $BASE_WORKSPACE"
    else
        BASE_WORKSPACE="$DEFAULT_BASE_WORKSPACE"
        print_info "使用默认基础工作目录: $BASE_WORKSPACE"
    fi
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
        return 0
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
    
    print_success "基础镜像构建完成"
}

# 创建单个容器
create_single_container() {
    local username=$1
    local root_password=$2
    local codeserver_password=$3
    local gpu_ids=$4
    local cpu_limit=$5
    local memory_limit=$6
    local ssh_port=$7
    local codeserver_port=$8
    local workspace=$9
    local proxy_host=${10}
    local proxy_port=${11}
    
    local container_name="cuda-${username}"
    
    print_info "创建容器: $container_name"
    
    # 检查容器是否已存在
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        print_error "容器已存在: $container_name，跳过"
        return 1
    fi
    
    # 设置工作目录 - 改进版
    # 如果配置文件中指定了工作目录且不为空，则使用它作为该用户的专属目录
    # 否则使用基础工作目录 + 用户名
    if [ -z "$workspace" ]; then
        workspace="${BASE_WORKSPACE}/${username}"
    else
        # 如果指定了绝对路径，直接使用；否则追加用户名
        if [[ "$workspace" = /* ]]; then
            # 绝对路径，使用指定路径 + 用户名
            workspace="${workspace}/${username}"
        else
            # 相对路径，基于当前目录
            workspace="$(pwd)/${workspace}/${username}"
        fi
    fi
    
    # 创建目录
    mkdir -p "$workspace" || {
        print_error "无法创建工作目录: $workspace"
        return 1
    }
    print_info "工作目录: $workspace"
    
    # 自动分配端口
    if [ "$ssh_port" = "0" ]; then
        ssh_port=22001
        while netstat -tuln 2>/dev/null | grep -q ":$ssh_port " || docker ps --format '{{.Ports}}' | grep -q "$ssh_port"; do
            ((ssh_port++))
        done
    fi
    
    if [ "$codeserver_port" = "0" ]; then
        codeserver_port=8080
        while netstat -tuln 2>/dev/null | grep -q ":$codeserver_port " || docker ps --format '{{.Ports}}' | grep -q "$codeserver_port"; do
            ((codeserver_port++))
        done
    fi
    
    # 构建docker run命令
    local docker_cmd="docker run -d --restart=unless-stopped"
    
    # GPU
    if [ "$gpu_ids" = "all" ]; then
        docker_cmd="$docker_cmd --gpus all"
    else
        docker_cmd="$docker_cmd --gpus '\"device=$gpu_ids\"'"
    fi
    
    # CPU
    if [ "$cpu_limit" != "0" ]; then
        docker_cmd="$docker_cmd --cpus=$cpu_limit"
    fi
    
    # 内存
    if [ -n "$memory_limit" ]; then
        docker_cmd="$docker_cmd --memory=$memory_limit"
    fi
    
    # 端口
    docker_cmd="$docker_cmd -p $ssh_port:22 -p $codeserver_port:8080"
    
    # 卷
    docker_cmd="$docker_cmd -v $workspace:/workspace"
    docker_cmd="$docker_cmd -v $(pwd)/banner.txt:/etc/banner.txt:ro"
    
    # 环境变量
    docker_cmd="$docker_cmd -e CODESERVER_PASSWORD='$codeserver_password'"
    docker_cmd="$docker_cmd -e CONTAINER_USERNAME='$username'"
    docker_cmd="$docker_cmd -e CONTAINER_SSH_PORT='$ssh_port'"
    docker_cmd="$docker_cmd -e CONTAINER_CODESERVER_PORT='$codeserver_port'"
    docker_cmd="$docker_cmd -e CONTAINER_SYNCTHING_PORT='8384'"
    
    # 代理配置
    if [ -n "$proxy_host" ] && [ -n "$proxy_port" ]; then
        local http_proxy="http://${proxy_host}:${proxy_port}"
        docker_cmd="$docker_cmd -e USE_PROXY='true'"
        docker_cmd="$docker_cmd -e HTTP_PROXY='$http_proxy'"
        docker_cmd="$docker_cmd -e HTTPS_PROXY='$http_proxy'"
        docker_cmd="$docker_cmd -e http_proxy='$http_proxy'"
        docker_cmd="$docker_cmd -e https_proxy='$http_proxy'"
        docker_cmd="$docker_cmd -e NO_PROXY='localhost,127.0.0.1'"
        docker_cmd="$docker_cmd -e no_proxy='localhost,127.0.0.1'"
        print_info "代理配置: $http_proxy"
    fi
    
    # 名称
    docker_cmd="$docker_cmd --name $container_name"
    docker_cmd="$docker_cmd --hostname $container_name"
    docker_cmd="$docker_cmd $IMAGE_TAG"
    
    # 执行创建
    eval $docker_cmd || {
        print_error "容器创建失败: $container_name"
        return 1
    }
    
    # 等待启动
    sleep 2
    
    # 设置root密码
    docker exec $container_name bash -c "echo 'root:$root_password' | chpasswd" || {
        print_error "设置root密码失败: $container_name"
        return 1
    }
    
    # 保存信息
    local info_file="$(pwd)/containers/${username}.txt"
    mkdir -p "$(pwd)/containers"
    
    cat > "$info_file" << EOF
容器名称: $container_name
创建时间: $(date '+%Y-%m-%d %H:%M:%S')

SSH连接:
  端口: $ssh_port
  用户: root
  密码: $root_password
  命令: ssh root@localhost -p $ssh_port

Code-server:
  端口: $codeserver_port
  地址: http://localhost:$codeserver_port
  密码: $codeserver_password

资源配置:
  GPU: $gpu_ids
  CPU: $([ "$cpu_limit" = "0" ] && echo "无限制" || echo "${cpu_limit}核")
  内存: $([ -z "$memory_limit" ] && echo "无限制" || echo "$memory_limit")

工作目录: $workspace
EOF
    
    print_success "容器创建成功: $container_name (SSH:$ssh_port, Code-server:$codeserver_port)"
    return 0
}

# 从配置文件批量创建
batch_create() {
    local config_file=$1
    
    if [ ! -f "$config_file" ]; then
        print_error "配置文件不存在: $config_file"
        exit 1
    fi
    
    print_info "读取配置文件: $config_file"
    
    local total=0
    local success=0
    local failed=0
    
    # 读取配置文件
    while IFS='|' read -r username root_password codeserver_password gpu cpu memory ssh_port codeserver_port workspace proxy_host proxy_port; do
        # 跳过注释和空行
        [[ "$username" =~ ^#.*$ ]] && continue
        [[ -z "$username" ]] && continue
        
        ((total++))
        
        echo ""
        echo "========================================="
        echo "  [$total] 创建用户容器: $username"
        echo "========================================="
        
        if create_single_container "$username" "$root_password" "$codeserver_password" \
            "$gpu" "$cpu" "$memory" "$ssh_port" "$codeserver_port" "$workspace" "$proxy_host" "$proxy_port"; then
            ((success++))
        else
            ((failed++))
        fi
        
        # 避免端口冲突，稍作延迟
        sleep 1
    done < "$config_file"
    
    echo ""
    echo "========================================="
    echo "           批量创建完成"
    echo "========================================="
    echo "总计: $total"
    echo "成功: $success"
    echo "失败: $failed"
    echo "========================================="
}

# 主函数
main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   CUDA容器批量创建工具               ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    if [ "$1" = "example" ]; then
        create_sample_config
        exit 0
    fi
    
    if [ -z "$1" ]; then
        echo "用法："
        echo "  $0 <配置文件>     - 从配置文件批量创建容器"
        echo "  $0 example        - 生成示例配置文件"
        echo ""
        echo "示例："
        echo "  $0 example                      # 生成示例配置"
        echo "  $0 batch_config.example.txt     # 从配置文件创建"
        echo ""
        exit 1
    fi
    
    # 选择Ubuntu版本
    select_ubuntu_version
    
    # 加载基础工作目录配置
    load_base_workspace
    
    # 构建基础镜像
    build_base_image
    
    # 批量创建
    batch_create "$1"
}

main "$@"

