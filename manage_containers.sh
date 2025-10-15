#!/bin/bash

# CUDA容器管理脚本
# 用于查看、管理已创建的容器

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# 列出所有CUDA容器
list_containers() {
    echo ""
    echo "========================================="
    echo "      CUDA容器列表"
    echo "========================================="
    echo ""
    
    local containers=$(docker ps -a --filter "name=cuda-" --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        print_warning "没有找到任何CUDA容器"
        return
    fi
    
    printf "%-20s %-15s %-15s %-15s %-30s\n" "容器名称" "状态" "SSH端口" "Jupyter端口" "GPU"
    echo "--------------------------------------------------------------------------------------------------------"
    
    for container in $containers; do
        local status=$(docker inspect -f '{{.State.Status}}' $container)
        local ssh_port=$(docker port $container 22 2>/dev/null | cut -d: -f2)
        local jupyter_port=$(docker port $container 8888 2>/dev/null | cut -d: -f2)
        
        # 获取GPU信息
        local gpu_info=$(docker inspect -f '{{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}' $container 2>/dev/null)
        if [ -z "$gpu_info" ]; then
            gpu_info="all"
        else
            gpu_info=$(echo $gpu_info | grep -o 'nvidia[0-9]*' | sed 's/nvidia//' | tr '\n' ',' | sed 's/,$//')
        fi
        
        # 状态颜色
        if [ "$status" = "running" ]; then
            status="${GREEN}运行中${NC}"
        else
            status="${RED}已停止${NC}"
        fi
        
        printf "%-20s %-25s %-15s %-15s %-30s\n" "$container" "$(echo -e $status)" "${ssh_port:-N/A}" "${jupyter_port:-N/A}" "${gpu_info:-N/A}"
    done
    
    echo ""
}

# 显示容器详细信息
show_container_info() {
    local container_name=$1
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        print_error "容器不存在: $container_name"
        return 1
    fi
    
    echo ""
    echo "========================================="
    echo "  容器详细信息: $container_name"
    echo "========================================="
    echo ""
    
    local status=$(docker inspect -f '{{.State.Status}}' $container_name)
    local ssh_port=$(docker port $container_name 22 2>/dev/null | cut -d: -f2)
    local jupyter_port=$(docker port $container_name 8888 2>/dev/null | cut -d: -f2)
    local created=$(docker inspect -f '{{.Created}}' $container_name)
    local cpu_limit=$(docker inspect -f '{{.HostConfig.NanoCpus}}' $container_name)
    local memory_limit=$(docker inspect -f '{{.HostConfig.Memory}}' $container_name)
    
    echo "状态:           $status"
    echo "创建时间:       $created"
    echo "SSH端口:        ${ssh_port:-N/A}"
    echo "Jupyter端口:    ${jupyter_port:-N/A}"
    
    if [ "$cpu_limit" != "0" ]; then
        cpu_cores=$((cpu_limit / 1000000000))
        echo "CPU限制:        ${cpu_cores}核"
    else
        echo "CPU限制:        无限制"
    fi
    
    if [ "$memory_limit" != "0" ]; then
        memory_gb=$((memory_limit / 1024 / 1024 / 1024))
        echo "内存限制:       ${memory_gb}GB"
    else
        echo "内存限制:       无限制"
    fi
    
    # 获取工作目录挂载
    local workspace=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' $container_name)
    echo "工作目录:       ${workspace:-N/A}"
    
    # 如果容器在运行，显示资源使用情况
    if [ "$status" = "running" ]; then
        echo ""
        echo "资源使用情况:"
        docker stats --no-stream $container_name | tail -n +2
    fi
    
    # 检查是否有保存的信息文件
    local username=$(echo $container_name | sed 's/^cuda-//')
    local info_file="containers/${username}.txt"
    
    if [ -f "$info_file" ]; then
        echo ""
        echo "连接信息（来自保存的记录）:"
        echo "----------------------------------------"
        cat "$info_file"
    fi
    
    echo ""
}

# 启动容器
start_container() {
    local container_name=$1
    
    print_info "启动容器: $container_name"
    docker start $container_name || {
        print_error "启动失败"
        return 1
    }
    print_success "容器已启动"
}

# 停止容器
stop_container() {
    local container_name=$1
    
    print_info "停止容器: $container_name"
    docker stop $container_name || {
        print_error "停止失败"
        return 1
    }
    print_success "容器已停止"
}

# 重启容器
restart_container() {
    local container_name=$1
    
    print_info "重启容器: $container_name"
    docker restart $container_name || {
        print_error "重启失败"
        return 1
    }
    print_success "容器已重启"
}

# 删除容器
remove_container() {
    local container_name=$1
    
    print_warning "即将删除容器: $container_name"
    read -p "确认删除？(yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "取消删除"
        return 0
    fi
    
    print_info "删除容器: $container_name"
    docker rm -f $container_name || {
        print_error "删除失败"
        return 1
    }
    print_success "容器已删除"
}

# 进入容器
enter_container() {
    local container_name=$1
    
    local status=$(docker inspect -f '{{.State.Status}}' $container_name 2>/dev/null)
    
    if [ "$status" != "running" ]; then
        print_error "容器未运行，是否启动？(y/n)"
        read -p "> " start_it
        if [ "$start_it" = "y" ]; then
            start_container $container_name
        else
            return 1
        fi
    fi
    
    print_info "进入容器: $container_name"
    docker exec -it $container_name bash
}

# 查看容器日志
view_logs() {
    local container_name=$1
    local lines=${2:-100}
    
    print_info "查看容器日志: $container_name (最后${lines}行)"
    docker logs --tail $lines -f $container_name
}

# 显示资源使用统计
show_stats() {
    echo ""
    echo "========================================="
    echo "      CUDA容器资源统计"
    echo "========================================="
    echo ""
    
    local containers=$(docker ps --filter "name=cuda-" --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        print_warning "没有运行中的CUDA容器"
        return
    fi
    
    docker stats $containers
}

# 批量操作
batch_operation() {
    local operation=$1
    
    echo ""
    list_containers
    echo ""
    
    read -p "请输入要${operation}的容器名（用空格分隔，或输入'all'表示全部）: " containers
    
    if [ "$containers" = "all" ]; then
        containers=$(docker ps -a --filter "name=cuda-" --format "{{.Names}}")
    fi
    
    for container in $containers; do
        case $operation in
            "启动")
                start_container $container
                ;;
            "停止")
                stop_container $container
                ;;
            "重启")
                restart_container $container
                ;;
            "删除")
                remove_container $container
                ;;
        esac
    done
}

# 主菜单
show_menu() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║     CUDA容器管理工具                 ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "1)  列出所有容器"
    echo "2)  查看容器详情"
    echo "3)  启动容器"
    echo "4)  停止容器"
    echo "5)  重启容器"
    echo "6)  删除容器"
    echo "7)  进入容器"
    echo "8)  查看容器日志"
    echo "9)  查看资源统计"
    echo "10) 批量启动"
    echo "11) 批量停止"
    echo "12) 批量重启"
    echo "0)  退出"
    echo ""
}

# 主函数
main() {
    while true; do
        show_menu
        read -p "请选择操作 [0-12]: " choice
        
        case $choice in
            1)
                list_containers
                ;;
            2)
                list_containers
                echo ""
                read -p "请输入容器名: " container_name
                show_container_info $container_name
                ;;
            3)
                list_containers
                echo ""
                read -p "请输入要启动的容器名: " container_name
                start_container $container_name
                ;;
            4)
                list_containers
                echo ""
                read -p "请输入要停止的容器名: " container_name
                stop_container $container_name
                ;;
            5)
                list_containers
                echo ""
                read -p "请输入要重启的容器名: " container_name
                restart_container $container_name
                ;;
            6)
                list_containers
                echo ""
                read -p "请输入要删除的容器名: " container_name
                remove_container $container_name
                ;;
            7)
                list_containers
                echo ""
                read -p "请输入要进入的容器名: " container_name
                enter_container $container_name
                ;;
            8)
                list_containers
                echo ""
                read -p "请输入容器名: " container_name
                read -p "显示行数 (默认100): " lines
                view_logs $container_name ${lines:-100}
                ;;
            9)
                show_stats
                ;;
            10)
                batch_operation "启动"
                ;;
            11)
                batch_operation "停止"
                ;;
            12)
                batch_operation "重启"
                ;;
            0)
                print_info "退出程序"
                exit 0
                ;;
            *)
                print_error "无效的选择"
                ;;
        esac
        
        read -p "按回车键继续..."
    done
}

# 如果有命令行参数，直接执行命令
if [ $# -gt 0 ]; then
    case $1 in
        list|ls)
            list_containers
            ;;
        info)
            if [ -z "$2" ]; then
                print_error "请指定容器名"
                exit 1
            fi
            show_container_info $2
            ;;
        start)
            if [ -z "$2" ]; then
                print_error "请指定容器名"
                exit 1
            fi
            start_container $2
            ;;
        stop)
            if [ -z "$2" ]; then
                print_error "请指定容器名"
                exit 1
            fi
            stop_container $2
            ;;
        restart)
            if [ -z "$2" ]; then
                print_error "请指定容器名"
                exit 1
            fi
            restart_container $2
            ;;
        rm|remove)
            if [ -z "$2" ]; then
                print_error "请指定容器名"
                exit 1
            fi
            remove_container $2
            ;;
        enter|exec)
            if [ -z "$2" ]; then
                print_error "请指定容器名"
                exit 1
            fi
            enter_container $2
            ;;
        logs)
            if [ -z "$2" ]; then
                print_error "请指定容器名"
                exit 1
            fi
            view_logs $2 ${3:-100}
            ;;
        stats)
            show_stats
            ;;
        *)
            print_error "未知命令: $1"
            echo "用法: $0 [list|info|start|stop|restart|remove|enter|logs|stats] [容器名]"
            exit 1
            ;;
    esac
else
    # 没有参数，显示交互式菜单
    main
fi

