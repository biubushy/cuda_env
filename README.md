# CUDA 容器化环境管理系统

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CUDA Version](https://img.shields.io/badge/CUDA-12.8-green.svg)](https://developer.nvidia.com/cuda-toolkit)
[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)

一个基于 Docker 的 CUDA 开发环境自动化管理系统，专为多用户 GPU 服务器设计，提供隔离的开发环境和完整的工具链支持。

## 📋 目录

- [项目简介](#项目简介)
- [核心特性](#核心特性)
- [系统架构](#系统架构)
- [快速开始](#快速开始)
- [详细使用](#详细使用)
- [配置说明](#配置说明)
- [技术栈](#技术栈)
- [常见问题](#常见问题)
- [许可证](#许可证)

## 🎯 项目简介

本项目旨在解决多用户共享 GPU 服务器时的环境隔离和资源管理问题。通过 Docker 容器化技术，为每个用户创建独立的 CUDA 开发环境，支持：

- **完全隔离**：每个用户拥有独立的文件系统和运行环境
- **GPU 共享**：灵活分配 GPU 资源，支持独占或共享模式
- **资源限制**：可配置 CPU、内存等资源上限
- **开箱即用**：预配置 CUDA、Zsh、Miniconda 等开发工具
- **远程访问**：集成 SSH 和 Code-server（Web IDE）
- **数据同步**：内置 Syncthing 实现多端文件同步

## ✨ 核心特性

### 1. 环境隔离
- 基于 Docker 容器，用户之间完全隔离
- 每个用户拥有 root 权限，可自由安装软件
- 独立的工作目录映射到宿主机

### 2. GPU 支持
- 基于 NVIDIA CUDA 12.8 官方镜像
- 支持动态分配 GPU 资源（单卡、多卡或全部）
- 预配置 CUDA 环境变量和工具链

### 3. 开发工具
- **Zsh + Oh-My-Zsh + Powerlevel10k**：现代化终端体验
- **Miniconda**：Python 环境管理，预配置清华镜像源
- **Code-server**：基于 Web 的 VS Code 编辑器
- **Syncthing**：跨设备文件同步工具
- **tmux**：终端复用器，支持后台任务

### 4. 自动化管理
- 交互式单用户创建脚本
- 批量创建多个用户容器
- 统一的容器管理界面
- 端口自动分配机制

### 5. 网络代理支持
- 可选的宿主机代理配置
- 支持 APT、Git、wget 等工具的代理设置
- 适用于需要科学上网的场景

## 🏗 系统架构

### 架构图

```
宿主机 (Ubuntu + NVIDIA Driver)
├── Docker Engine (with NVIDIA Container Toolkit)
│   ├── 基础镜像: cuda-env:12.8
│   │   ├── CUDA 12.8 Toolkit
│   │   ├── SSH Server
│   │   ├── Code-server
│   │   ├── Syncthing
│   │   ├── Zsh + Oh-My-Zsh
│   │   └── Miniconda
│   │
│   ├── 用户容器 1: cuda-alice
│   │   ├── GPU: 0
│   │   ├── SSH: 22001
│   │   ├── Code-server: 8080
│   │   └── 工作目录: /workspace
│   │
│   ├── 用户容器 2: cuda-bob
│   │   ├── GPU: 1
│   │   ├── SSH: 22002
│   │   ├── Code-server: 8081
│   │   └── 工作目录: /workspace
│   │
│   └── 用户容器 N: cuda-charlie
│       ├── GPU: all
│       ├── SSH: 22003
│       ├── Code-server: 8082
│       └── 工作目录: /workspace
│
└── 宿主机目录映射
    ├── /home/cuda-container/workspace/alice -> 容器1:/workspace
    ├── /home/cuda-container/workspace/bob -> 容器2:/workspace
    └── /home/cuda-container/workspace/charlie -> 容器N:/workspace
```

### 工作流程

1. **镜像构建阶段**
   - 基于 NVIDIA CUDA 12.8 Ubuntu 22.04
   - 安装系统依赖和开发工具
   - 配置 SSH、Code-server、Syncthing
   - 预装 Zsh + Oh-My-Zsh + Miniconda
   - 设置全局 CUDA 环境变量

2. **容器创建阶段**
   - 从基础镜像创建用户容器
   - 分配 GPU 资源和端口
   - 挂载用户工作目录
   - 设置 root 密码和 Code-server 密码
   - 配置可选的网络代理

3. **容器运行阶段**
   - 启动 SSH 服务（端口 22）
   - 启动 Code-server（端口 8080）
   - 启动 Syncthing（端口 8384）
   - 显示登录欢迎信息
   - 持久化运行（除非手动停止）

## 🚀 快速开始

### 系统要求

- **操作系统**：Ubuntu 20.04+ 或其他支持 Docker 的 Linux 发行版
- **GPU**：NVIDIA GPU（支持 CUDA 12.8）
- **驱动**：NVIDIA Driver 525+ 
- **Docker**：Docker 20.10+
- **NVIDIA Container Toolkit**：用于 Docker GPU 支持
- **磁盘空间**：至少 20GB 可用空间（镜像约 8GB）

### 环境准备

#### 1. 安装 Docker

```bash
# 更新系统
sudo apt-get update

# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 将当前用户加入 docker 组（避免每次使用 sudo）
sudo usermod -aG docker $USER
```

#### 2. 安装 NVIDIA Container Toolkit

```bash
# 添加 NVIDIA 仓库
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    sudo tee /etc/apt/sources.list.d/nvidia-docker.list

# 安装
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# 重启 Docker
sudo systemctl restart docker
```

#### 3. 验证环境

```bash
# 运行环境检查脚本
./check_env.sh
```

该脚本会检查：
- Docker 安装和权限
- NVIDIA 驱动
- NVIDIA Docker 运行时
- 必要的系统命令
- 端口占用情况
- 磁盘空间

### 创建第一个容器

#### 方式一：交互式创建（推荐新手）

```bash
# 运行创建脚本
./create_user_container.sh
```

脚本会引导你完成以下配置：
1. 输入用户名（容器名为 `cuda-用户名`）
2. 设置 root 密码
3. 设置 Code-server 密码（可选，默认与 root 密码相同）
4. 选择 GPU 资源（如 `0,1` 或 `all`）
5. 设置 CPU 限制（可选）
6. 设置内存限制（可选）
7. 配置 SSH 端口（可选，默认自动分配）
8. 配置 Code-server 端口（可选，默认自动分配）
9. 设置工作目录（默认 `/home/cuda-container/workspace/用户名`）
10. 配置网络代理（可选）

创建完成后，脚本会显示连接信息并保存到 `containers/用户名.txt`。

#### 方式二：批量创建

1. **生成配置文件示例**

```bash
./batch_create.sh example
```

这会创建 `batch_config.example.txt` 文件。

2. **编辑配置文件**

```bash
# 复制示例文件
cp batch_config.example.txt my_users.txt

# 编辑配置（每行一个用户）
vim my_users.txt
```

配置格式：
```
用户名|root密码|codeserver密码|GPU|CPU|内存|SSH端口|Code-server端口|工作目录|代理地址|代理端口
```

示例：
```
alice|pass123|pass123|0|4|16g|22001|8080|||
bob|pass456|pass456|1|8|32g|22002|8081|||
charlie|pass789|pass789|all|0||0|0|/data/charlie|192.168.1.100|7890
```

3. **批量创建**

```bash
./batch_create.sh my_users.txt
```

## 📖 详细使用

### 容器管理

#### 交互式管理界面

```bash
./manage_containers.sh
```

提供以下功能：
1. 列出所有容器
2. 查看容器详情
3. 启动容器
4. 停止容器
5. 重启容器
6. 删除容器
7. 进入容器
8. 查看容器日志
9. 查看资源统计
10. 批量操作

#### 命令行管理

```bash
# 列出所有容器
./manage_containers.sh list

# 查看容器详情
./manage_containers.sh info cuda-alice

# 启动容器
./manage_containers.sh start cuda-alice

# 停止容器
./manage_containers.sh stop cuda-alice

# 重启容器
./manage_containers.sh restart cuda-alice

# 删除容器
./manage_containers.sh remove cuda-alice

# 进入容器
./manage_containers.sh enter cuda-alice

# 查看日志
./manage_containers.sh logs cuda-alice 100

# 查看资源统计
./manage_containers.sh stats
```

### 访问容器

#### SSH 访问

```bash
# 使用分配的端口连接
ssh root@服务器IP -p 22001

# 示例
ssh root@192.168.1.100 -p 22001
```

#### Code-server（Web IDE）

在浏览器中访问：
```
http://服务器IP:8080
```

首次访问需要输入 Code-server 密码。

#### Syncthing（文件同步）

在浏览器中访问：
```
http://服务器IP:8080/proxy/8384/
```

注意：Syncthing 通过 Code-server 的反向代理访问。

### 容器内使用

#### GPU 验证

```bash
# 检查 CUDA 版本
nvcc --version

# 查看 GPU 信息
nvidia-smi

# 测试 PyTorch GPU 支持（需先安装 PyTorch）
conda create -n pytorch python=3.10
conda activate pytorch
conda install pytorch torchvision torchaudio pytorch-cuda=12.1 -c pytorch -c nvidia
python -c "import torch; print(torch.cuda.is_available())"
```

#### Conda 环境管理

```bash
# 创建环境
conda create -n myenv python=3.10

# 激活环境
conda activate myenv

# 安装包
conda install numpy pandas scikit-learn

# 列出环境
conda env list

# 删除环境
conda env remove -n myenv
```

#### 后台任务

使用 `nohup` 运行长时间任务：
```bash
nohup python train.py > train.log 2>&1 &
```

使用 `tmux` 管理多个会话：
```bash
# 创建新会话
tmux new -s training

# 分离会话（Ctrl+B, D）
# 列出会话
tmux ls

# 重新连接
tmux attach -t training
```

## ⚙️ 配置说明

### Dockerfile 配置

`Dockerfile` 定义了基础镜像的构建过程：

- **基础镜像**：`nvidia/cuda:12.8.0-devel-ubuntu22.04`
- **时区设置**：`Asia/Shanghai`
- **系统包**：openssh-server, vim, git, zsh, tmux, syncthing 等
- **Code-server**：从官方安装脚本安装
- **CUDA 环境变量**：配置到所有 shell（bash, zsh, sh）
- **启动脚本**：`/start.sh`

可根据需求修改以下内容：
- 添加额外的系统包
- 修改时区配置
- 调整 CUDA 版本
- 自定义启动逻辑

修改后需重新构建镜像：
```bash
docker build -t cuda-env:12.8 .
```

### Banner 配置

`banner.txt` 是用户登录时显示的欢迎信息，支持环境变量替换：

- `${CONTAINER_USERNAME}`：容器用户名
- `${CONTAINER_SSH_PORT}`：SSH 端口
- `${CONTAINER_CODESERVER_PORT}`：Code-server 端口
- `${CONTAINER_SYNCTHING_PORT}`：Syncthing 端口
- `${CONTAINER_HOST_IP}`：宿主机 IP

可根据需要自定义欢迎信息、使用规则等。

### 代理配置

如果服务器需要通过代理访问外网，可在创建容器时配置：

```bash
# 交互式创建时会提示
是否配置宿主机代理？(y/n，默认n): y
请输入宿主机IP地址（如 192.168.1.100）: 192.168.1.100
请输入代理端口（如 7890）: 7890
```

代理会自动配置到：
- APT 包管理器
- Git
- wget
- 环境变量（所有 shell）

### 工作目录配置

默认工作目录结构：
```
/home/cuda-container/workspace/
├── alice/          # 用户 alice 的工作目录
├── bob/            # 用户 bob 的工作目录
└── charlie/        # 用户 charlie 的工作目录
```

可在创建容器时修改基础路径，所有用户的工作目录会自动创建在该路径下。

## 🛠 技术栈

### Docker 相关
- **基础镜像**：nvidia/cuda:12.8.0-devel-ubuntu22.04
- **容器运行时**：NVIDIA Container Toolkit
- **资源管理**：Docker Resource Constraints

### CUDA 工具链
- **CUDA Toolkit**：12.8
- **CUDA 驱动 API**：完整开发工具
- **环境变量**：全局配置（所有 shell）

### 开发工具
- **Shell**：Zsh + Oh-My-Zsh + Powerlevel10k 主题
- **Python 环境**：Miniconda（清华镜像源）
- **Web IDE**：Code-server（VS Code 浏览器版）
- **文件同步**：Syncthing
- **终端复用**：tmux
- **远程访问**：OpenSSH Server

### 脚本语言
- **Bash**：所有自动化脚本
- **环境变量替换**：envsubst（用于 banner 显示）

## 🔧 常见问题

### 1. Docker 权限问题

**问题**：运行 `docker` 命令时提示权限不足

**解决**：
```bash
# 方法1：将用户加入 docker 组
sudo usermod -aG docker $USER
# 注销并重新登录

# 方法2：使用 sudo（临时）
sudo docker ps
```

### 2. NVIDIA Docker 运行时问题

**问题**：创建容器时找不到 GPU

**解决**：
```bash
# 验证 NVIDIA Docker 支持
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi

# 如果失败，重新安装 NVIDIA Container Toolkit
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

### 3. 端口冲突

**问题**：创建容器时提示端口已被占用

**解决**：
```bash
# 查看端口占用
netstat -tuln | grep :22001

# 使用自动分配端口（创建时留空）
# 或手动指定其他端口
```

### 4. Conda 初始化问题

**问题**：容器内 `conda` 命令不可用

**解决**：
```bash
# 手动初始化 conda
~/miniconda3/bin/conda init zsh
source ~/.zshrc
```

### 5. GPU 显存不足

**问题**：运行深度学习任务时显存不足

**解决**：
```bash
# 查看 GPU 使用情况
nvidia-smi

# 调整批次大小或模型参数
# 或为容器分配专用 GPU
```

### 6. Code-server 无法访问

**问题**：浏览器无法打开 Code-server

**解决**：
```bash
# 检查容器是否运行
docker ps | grep cuda-

# 检查端口映射
docker port cuda-用户名

# 检查防火墙设置
sudo ufw status
sudo ufw allow 8080
```

### 7. Syncthing 配置

**问题**：如何配置 Syncthing 同步

**解决**：
1. 访问 `http://服务器IP:Code-server端口/proxy/8384/`
2. 点击 "Actions" -> "Settings"
3. 添加同步文件夹（如 `/workspace`）
4. 在其他设备安装 Syncthing 并配对

### 8. 容器数据持久化

**问题**：容器删除后数据丢失

**说明**：
- 工作目录（`/workspace`）映射到宿主机，数据持久化
- 容器内其他位置的数据会随容器删除而丢失
- 建议所有重要数据保存在 `/workspace`

### 9. 修改 root 密码

**问题**：忘记容器 root 密码

**解决**：
```bash
# 从宿主机重置密码
docker exec cuda-用户名 bash -c "echo 'root:新密码' | chpasswd"
```

### 10. 网络代理不生效

**问题**：配置代理后仍无法访问外网

**解决**：
```bash
# 检查代理配置
docker exec cuda-用户名 env | grep -i proxy

# 重新启动容器
docker restart cuda-用户名

# 手动配置代理（容器内）
export http_proxy=http://代理地址:端口
export https_proxy=http://代理地址:端口
```

## 📂 项目结构

```
cuda_env/
├── Dockerfile                      # CUDA 基础镜像定义
├── create_user_container.sh        # 交互式创建单个容器
├── batch_create.sh                 # 批量创建容器
├── manage_containers.sh            # 容器管理工具
├── check_env.sh                    # 环境检查脚本
├── banner.txt                      # 登录欢迎信息（可自定义）
├── banner.example.txt              # 欢迎信息示例
├── batch_config.example.txt        # 批量创建配置示例
├── LICENSE                         # MIT 许可证
├── README.md                       # 项目文档（本文件）
├── containers/                     # 容器信息存储目录
│   └── jiyuan.txt                  # 用户容器信息示例
└── zsh-scripts/                    # Zsh 和 Conda 配置脚本
    ├── oh-my-zsh-pkg.tar.gz        # Oh-My-Zsh 预配置包
    ├── setup-zsh-conda.sh          # root 用户环境配置
    └── user-setup-zsh-conda.sh     # 镜像构建时环境准备
```

### 文件说明

| 文件 | 说明 |
|------|------|
| `Dockerfile` | 定义 CUDA 基础镜像，包含所有工具和配置 |
| `create_user_container.sh` | 交互式脚本，逐步引导创建单个用户容器 |
| `batch_create.sh` | 从配置文件批量创建多个容器 |
| `manage_containers.sh` | 容器管理工具，支持启动、停止、删除等操作 |
| `check_env.sh` | 检查 Docker、NVIDIA 驱动等环境依赖 |
| `banner.txt` | 用户登录时显示的欢迎信息，支持变量替换 |
| `zsh-scripts/setup-zsh-conda.sh` | 配置 Zsh + Oh-My-Zsh + Miniconda |
| `zsh-scripts/user-setup-zsh-conda.sh` | 镜像构建时的环境准备脚本 |
| `containers/` | 存储每个用户的容器信息（端口、密码等） |

## 🤝 贡献指南

欢迎提交问题报告、功能建议或代码贡献！

### 报告问题

在 [GitHub Issues](https://github.com/biubushy/cuda_env/issues) 中提交问题时，请包含：
- 操作系统版本
- Docker 版本
- NVIDIA 驱动版本
- 详细的错误信息
- 复现步骤

### 功能建议

如果您有新功能建议，请在 Issues 中说明：
- 功能描述
- 使用场景
- 预期效果

### 代码贡献

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 📝 更新日志

### v1.0.0 (2025-10-15)

初始版本发布，包含以下功能：
- ✅ 基于 CUDA 12.8 的基础镜像
- ✅ 交互式和批量容器创建
- ✅ GPU 资源分配和限制
- ✅ SSH、Code-server、Syncthing 集成
- ✅ Zsh + Oh-My-Zsh + Miniconda 预配置
- ✅ 网络代理支持
- ✅ 容器管理工具
- ✅ 环境检查脚本
- ✅ 自定义登录欢迎信息

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

**特别声明**：本软件仅供学术科研使用，禁止用于商业或其他私人用途。

## 👥 作者

- **biubushy** - [GitHub](https://github.com/biubushy)

## 🙏 致谢

- NVIDIA CUDA 官方镜像
- Oh-My-Zsh 社区
- Code-server 项目
- Syncthing 项目
- Docker 社区

## 📮 联系方式

- GitHub: [biubushy/cuda_env](https://github.com/biubushy/cuda_env)
- Issues: [提交问题](https://github.com/biubushy/cuda_env/issues)

---

**Star ⭐ 本项目以获取更新通知！**

