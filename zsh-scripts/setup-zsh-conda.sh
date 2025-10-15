#!/bin/bash

# 定义标记文件路径
ZSH_MARK_FILE="$HOME/.oh-my-zsh_setup_done"
MINICONDA_MARK_FILE="$HOME/.miniconda_setup_done"

# 配置 Oh My Zsh
if [ ! -f "$ZSH_MARK_FILE" ]; then
    echo "开始配置 Oh My Zsh..."

    # 解压到用户家目录
    echo "解压文件到个人家目录..."
    if tar -xzvf /home/share/oh-my-zsh-rc.tar.gz -C ~/; then
        echo "解压完成。"
    else
        echo "解压失败，请检查文件路径或权限。" >&2
        exit 1
    fi

    # 修正文件所有者和权限
    echo "修正文件所有者和权限..."
    chown -R "$(id -u):$(id -g)" "$HOME/.oh-my-zsh"
    chown "$(id -u):$(id -g)" "$HOME/.p10k.zsh"
    chown "$(id -u):$(id -g)" "$HOME/.zshrc"
    chmod -R 755 "$HOME/.oh-my-zsh"
    chmod 644 "$HOME/.p10k.zsh"
    chmod 644 "$HOME/.zshrc"
    
    # 禁用oh-my-zsh安全检查以避免权限警告
    echo 'export ZSH_DISABLE_COMPFIX="true"' >> "$HOME/.zshrc.pre"
    echo 'typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet' >> "$HOME/.zshrc.pre"
    
    # 在.zshrc开头插入配置
    if [ -f "$HOME/.zshrc" ]; then
        cat "$HOME/.zshrc.pre" "$HOME/.zshrc" > "$HOME/.zshrc.tmp"
        mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
        rm -f "$HOME/.zshrc.pre"
    fi

    # 设置默认 shell 为 zsh
    echo "设置默认 shell 为 zsh..."
    if chsh -s "$(which zsh)"; then
        echo "默认 shell 设置为 zsh 成功。"
    else
        echo "默认 shell 设置失败，请手动检查。" >&2
        exit 1
    fi

    # 创建标记文件
    touch "$ZSH_MARK_FILE"
    echo "Oh My Zsh 配置完成。"
else
    echo "Oh My Zsh 已经配置过，跳过执行。"
fi

# 配置 Miniconda
if [ ! -f "$MINICONDA_MARK_FILE" ]; then
    echo "开始安装 Miniconda..."

    # 进行 Miniconda 安装脚本路径配置
    INSTALLER_PATH="/home/share/Miniconda3-latest-Linux-x86_64.sh"

    if [ -f "$INSTALLER_PATH" ]; then
        echo "找到 Miniconda 安装脚本，将进行安装..."
    else
        echo "Miniconda 安装脚本未找到，请确保文件存在。" >&2
        exit 1
    fi

    # 执行安装脚本
    echo "正在运行 Miniconda 安装脚本..."
    if bash "$INSTALLER_PATH" -b -p "$HOME/miniconda3"; then
        echo "Miniconda 安装完成。"
    else
        echo "Miniconda 安装失败，请检查安装日志。" >&2
        exit 1
    fi

    # 创建 .condarc 配置文件
    echo "正在创建 .condarc 文件..."
    cat <<EOF > "$HOME/.condarc"
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  auto: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/
EOF
    echo ".condarc 文件创建完成。"

    # 初始化 conda for 所有常用shell
    echo "正在为所有shell初始化 conda..."
    "$HOME/miniconda3/bin/conda" init bash
    "$HOME/miniconda3/bin/conda" init zsh
    
    # 创建通用的conda环境变量配置（确保在所有shell中生效）
    echo "# Conda Environment" >> /etc/profile.d/conda.sh
    echo "export PATH=\"$HOME/miniconda3/bin:\$PATH\"" >> /etc/profile.d/conda.sh
    chmod +x /etc/profile.d/conda.sh

    # 创建标记文件
    touch "$MINICONDA_MARK_FILE"
    echo "Miniconda 配置完成（已支持bash、zsh等所有shell）。"
else
    echo "Miniconda 已经安装过，跳过安装过程。"
fi

# 提示用户重新加载 shell 配置
echo "配置完成"
