#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印函数
print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

# 检查是否以sudo权限运行
if [ "$EUID" -ne 0 ]; then
  print_error "请使用sudo权限运行此脚本。"
  exit 1
fi

print_info "开始检查系统依赖项..."

# ========== 依赖项检查 ==========

# 检查必需的命令是否存在
REQUIRED_COMMANDS=("curl" "tar" "zsh" "chsh" "mkdir" "chmod" "bash" "git")
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_COMMANDS+=("$cmd")
        print_error "未找到命令: $cmd"
    else
        print_success "检测到命令: $cmd"
    fi
done

# 如果有缺失的命令，提示安装
if [ ${#MISSING_COMMANDS[@]} -gt 0 ]; then
    print_error "缺少以下必需命令: ${MISSING_COMMANDS[*]}"
    print_info "正在尝试自动安装缺失的软件包..."
    
    # 检测系统包管理器并安装
    if command -v apt-get &> /dev/null; then
        print_info "检测到 apt-get 包管理器，正在安装依赖..."
        apt-get update -qq
        for cmd in "${MISSING_COMMANDS[@]}"; do
            case "$cmd" in
                "curl")
                    apt-get install -y curl
                    ;;
                "tar")
                    apt-get install -y tar
                    ;;
                "zsh")
                    apt-get install -y zsh
                    ;;
                "bash")
                    apt-get install -y bash
                    ;;
                "git")
                    apt-get install -y git
                    ;;
                *)
                    apt-get install -y "$cmd"
                    ;;
            esac
        done
    elif command -v yum &> /dev/null; then
        print_info "检测到 yum 包管理器，正在安装依赖..."
        for cmd in "${MISSING_COMMANDS[@]}"; do
            yum install -y "$cmd"
        done
    elif command -v dnf &> /dev/null; then
        print_info "检测到 dnf 包管理器，正在安装依赖..."
        for cmd in "${MISSING_COMMANDS[@]}"; do
            dnf install -y "$cmd"
        done
    else
        print_error "无法自动安装依赖，请手动安装以下命令: ${MISSING_COMMANDS[*]}"
        exit 1
    fi
    
    # 再次检查是否安装成功
    for cmd in "${MISSING_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "安装 $cmd 失败，请手动安装"
            exit 1
        fi
    done
    print_success "所有依赖项已成功安装"
fi

# 检查网络连接
print_info "检查网络连接..."
if curl -s --max-time 5 --head https://www.baidu.com > /dev/null; then
    print_success "网络连接正常"
else
    print_error "网络连接失败，请检查网络设置"
    exit 1
fi

# 检查磁盘空间（至少需要 500MB，因为需要安装 Miniconda）
print_info "检查磁盘空间..."
REQUIRED_SPACE=500000  # KB
AVAILABLE_SPACE=$(df /home | tail -1 | awk '{print $4}')

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    print_error "磁盘空间不足，至少需要 500MB，当前可用: $((AVAILABLE_SPACE / 1024))MB"
    exit 1
else
    print_success "磁盘空间充足: $((AVAILABLE_SPACE / 1024))MB 可用"
fi

# 检查目标目录权限
print_info "检查目录权限..."
TEST_DIRS=("/home/share" "/etc/profile.d")
for dir in "${TEST_DIRS[@]}"; do
    # 尝试创建目录（如果不存在）
    if [ ! -d "$dir" ]; then
        if mkdir -p "$dir" 2>/dev/null; then
            print_success "目录 $dir 创建成功"
        else
            print_error "无法创建目录 $dir，请检查权限"
            exit 1
        fi
    else
        # 检查写权限
        if [ -w "$dir" ]; then
            print_success "目录 $dir 可写"
        else
            print_error "目录 $dir 没有写权限"
            exit 1
        fi
    fi
done

print_success "所有依赖项检查通过！"
echo ""
print_info "开始下载和配置..."
echo ""

# 定义文件和目标路径
MINICONDA_URL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh"
MINICONDA_DEST="/home/share"

OH_MY_ZSH_RC_SRC="./oh-my-zsh-pkg.tar.gz"
OH_MY_ZSH_RC_DEST="/home/share"

SETUP_SCRIPT_SRC="./setup-zsh-conda.sh"
SETUP_SCRIPT_DEST="/etc/profile.d"

# 下载Miniconda安装脚本
if [ ! -d "$MINICONDA_DEST" ]; then
  print_info "目标文件夹$MINICONDA_DEST不存在，正在创建..."
  mkdir -p "$MINICONDA_DEST"
  print_success "已成功创建文件夹：$MINICONDA_DEST"
fi

print_info "正在下载Miniconda安装脚本到$MINICONDA_DEST..."
curl -fSL "$MINICONDA_URL" -o "$MINICONDA_DEST/Miniconda3-latest-Linux-x86_64.sh"
if [ $? -eq 0 ]; then
  print_success "Miniconda安装脚本下载成功。"
  chmod 644 "$MINICONDA_DEST/Miniconda3-latest-Linux-x86_64.sh"
  print_success "已赋予文件644权限。"
else
  print_error "Miniconda安装脚本下载失败，请检查网络连接或URL。"
  exit 1
fi

# 复制oh-my-zsh-pkg.tar.gz
if [ ! -d "$OH_MY_ZSH_RC_DEST" ]; then
  print_info "目标文件夹$OH_MY_ZSH_RC_DEST不存在，正在创建..."
  mkdir -p "$OH_MY_ZSH_RC_DEST"
  print_success "已成功创建文件夹：$OH_MY_ZSH_RC_DEST"
fi

print_info "正在复制oh-my-zsh-pkg.tar.gz到$OH_MY_ZSH_RC_DEST..."
if [ ! -f "$OH_MY_ZSH_RC_SRC" ]; then
  print_error "本地文件$OH_MY_ZSH_RC_SRC不存在。"
  exit 1
fi
cp "$OH_MY_ZSH_RC_SRC" "$OH_MY_ZSH_RC_DEST/oh-my-zsh-rc.tar.gz"
if [ $? -eq 0 ]; then
  print_success "oh-my-zsh-pkg.tar.gz复制成功。"
  chmod 644 "$OH_MY_ZSH_RC_DEST/oh-my-zsh-rc.tar.gz"
  print_success "已赋予文件644权限。"
else
  print_error "oh-my-zsh-pkg.tar.gz复制失败。"
  exit 1
fi

# 复制setup-zsh-conda.sh
if [ ! -d "$SETUP_SCRIPT_DEST" ]; then
  print_info "目标文件夹$SETUP_SCRIPT_DEST不存在，正在创建..."
  mkdir -p "$SETUP_SCRIPT_DEST"
  print_success "已成功创建文件夹：$SETUP_SCRIPT_DEST"
fi

print_info "正在复制setup-zsh-conda.sh到$SETUP_SCRIPT_DEST..."
if [ ! -f "$SETUP_SCRIPT_SRC" ]; then
  print_error "本地文件$SETUP_SCRIPT_SRC不存在。"
  exit 1
fi
cp "$SETUP_SCRIPT_SRC" "$SETUP_SCRIPT_DEST/setup-zsh-conda.sh"
if [ $? -eq 0 ]; then
  print_success "setup-zsh-conda.sh复制成功。"
  chmod 755 "$SETUP_SCRIPT_DEST/setup-zsh-conda.sh"
  print_success "已赋予文件755权限。"
else
  print_error "setup-zsh-conda.sh复制失败。"
  exit 1
fi

# 提示用户操作完成
echo ""
echo "========================================"
print_success "所有任务已成功完成！"
echo "========================================"
print_info "Miniconda安装脚本已下载到$MINICONDA_DEST并赋予权限。"
print_info "oh-my-zsh-rc.tar.gz已复制到$OH_MY_ZSH_RC_DEST并赋予权限。"
print_info "setup-zsh-conda.sh已复制到$SETUP_SCRIPT_DEST并赋予权限。"
echo ""
print_info "下一步："
echo "  1. 使用 'sudo adduser 用户名' 创建新用户"
echo "  2. 新用户首次登录时将自动配置 zsh + conda 环境"
echo ""

