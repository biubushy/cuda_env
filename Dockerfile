# 基于CUDA 12.8的Ubuntu镜像
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04

# 设置环境变量避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 设置CUDA环境变量（确保在所有shell中生效）
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
ENV LIBRARY_PATH=${CUDA_HOME}/lib64:${LIBRARY_PATH}
ENV CUDA_TOOLKIT_ROOT_DIR=${CUDA_HOME}
ENV CUDNN_PATH=${CUDA_HOME}

# 安装基础工具和依赖
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    wget \
    vim \
    git \
    zsh \
    build-essential \
    ca-certificates \
    tzdata \
    tmux \
    syncthing \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# 配置时区为中国上海
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 配置SSH
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# 安装Code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# 创建Code-server配置目录
RUN mkdir -p /root/.config/code-server

# 配置CUDA环境变量到所有shell配置文件
RUN echo '# CUDA Environment Variables' >> /etc/profile && \
    echo 'export CUDA_HOME=/usr/local/cuda' >> /etc/profile && \
    echo 'export PATH=$CUDA_HOME/bin:$PATH' >> /etc/profile && \
    echo 'export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH' >> /etc/profile && \
    echo 'export LIBRARY_PATH=$CUDA_HOME/lib64:$LIBRARY_PATH' >> /etc/profile && \
    echo 'export CUDA_TOOLKIT_ROOT_DIR=$CUDA_HOME' >> /etc/profile && \
    echo 'export CUDNN_PATH=$CUDA_HOME' >> /etc/profile

# 配置CUDA环境变量到bash
RUN echo '' >> /etc/bash.bashrc && \
    echo '# CUDA Environment Variables' >> /etc/bash.bashrc && \
    echo 'export CUDA_HOME=/usr/local/cuda' >> /etc/bash.bashrc && \
    echo 'export PATH=$CUDA_HOME/bin:$PATH' >> /etc/bash.bashrc && \
    echo 'export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH' >> /etc/bash.bashrc && \
    echo 'export LIBRARY_PATH=$CUDA_HOME/lib64:$LIBRARY_PATH' >> /etc/bash.bashrc && \
    echo 'export CUDA_TOOLKIT_ROOT_DIR=$CUDA_HOME' >> /etc/bash.bashrc && \
    echo 'export CUDNN_PATH=$CUDA_HOME' >> /etc/bash.bashrc

# 配置CUDA环境变量到zsh
RUN echo '' >> /etc/zsh/zshenv && \
    echo '# CUDA Environment Variables' >> /etc/zsh/zshenv && \
    echo 'export CUDA_HOME=/usr/local/cuda' >> /etc/zsh/zshenv && \
    echo 'export PATH=$CUDA_HOME/bin:$PATH' >> /etc/zsh/zshenv && \
    echo 'export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH' >> /etc/zsh/zshenv && \
    echo 'export LIBRARY_PATH=$CUDA_HOME/lib64:$LIBRARY_PATH' >> /etc/zsh/zshenv && \
    echo 'export CUDA_TOOLKIT_ROOT_DIR=$CUDA_HOME' >> /etc/zsh/zshenv && \
    echo 'export CUDNN_PATH=$CUDA_HOME' >> /etc/zsh/zshenv

# 配置CUDA环境变量到sh
RUN echo '' >> /etc/environment && \
    echo 'CUDA_HOME=/usr/local/cuda' >> /etc/environment && \
    echo 'PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /etc/environment && \
    echo 'LD_LIBRARY_PATH=/usr/local/cuda/lib64' >> /etc/environment

# 创建工作目录
RUN mkdir -p /workspace

# 复制zsh初始化脚本到镜像
COPY zsh-scripts /opt/zsh-scripts
RUN chmod +x /opt/zsh-scripts/*.sh

# 执行zsh初始化脚本（必须在镜像构建时执行）
RUN cd /opt/zsh-scripts && bash /opt/zsh-scripts/user-setup-zsh-conda.sh

# 为root用户执行zsh和conda配置
RUN cd /opt/zsh-scripts && bash /opt/zsh-scripts/setup-zsh-conda.sh

# 创建banner显示脚本（将通过挂载banner.txt文件）
RUN echo '#!/bin/bash\n\
if [ -f /etc/banner.txt ]; then\n\
    # 从配置文件加载容器信息\n\
    if [ -f /etc/container-info.env ]; then\n\
        set -a\n\
        source /etc/container-info.env\n\
        set +a\n\
    fi\n\
    # 使用envsubst替换变量，如果失败则直接显示原文件\n\
    if command -v envsubst >/dev/null 2>&1; then\n\
        envsubst < /etc/banner.txt 2>/dev/null || cat /etc/banner.txt\n\
    else\n\
        cat /etc/banner.txt\n\
    fi\n\
fi\n\
' > /etc/profile.d/show-banner.sh && chmod +x /etc/profile.d/show-banner.sh

# 为zsh配置banner显示
RUN echo '# Show banner on login' >> /etc/zsh/zshrc && \
    echo 'if [ -f /etc/banner.txt ]; then' >> /etc/zsh/zshrc && \
    echo '    # 从配置文件加载容器信息' >> /etc/zsh/zshrc && \
    echo '    if [ -f /etc/container-info.env ]; then' >> /etc/zsh/zshrc && \
    echo '        set -a' >> /etc/zsh/zshrc && \
    echo '        source /etc/container-info.env' >> /etc/zsh/zshrc && \
    echo '        set +a' >> /etc/zsh/zshrc && \
    echo '    fi' >> /etc/zsh/zshrc && \
    echo '    # 使用envsubst替换变量，如果失败则直接显示原文件' >> /etc/zsh/zshrc && \
    echo '    if command -v envsubst >/dev/null 2>&1; then' >> /etc/zsh/zshrc && \
    echo '        envsubst < /etc/banner.txt 2>/dev/null || cat /etc/banner.txt' >> /etc/zsh/zshrc && \
    echo '    else' >> /etc/zsh/zshrc && \
    echo '        cat /etc/banner.txt' >> /etc/zsh/zshrc && \
    echo '    fi' >> /etc/zsh/zshrc && \
    echo 'fi' >> /etc/zsh/zshrc

# 创建启动脚本
RUN echo '#!/bin/bash\n\
# 启动SSH服务\n\
service ssh start\n\
\n\
# 保存容器信息到配置文件（用于banner显示）\n\
echo "CONTAINER_USERNAME=${CONTAINER_USERNAME}" > /etc/container-info.env\n\
echo "CONTAINER_SSH_PORT=${CONTAINER_SSH_PORT}" >> /etc/container-info.env\n\
echo "CONTAINER_CODESERVER_PORT=${CONTAINER_CODESERVER_PORT}" >> /etc/container-info.env\n\
echo "CONTAINER_SYNCTHING_PORT=${CONTAINER_SYNCTHING_PORT}" >> /etc/container-info.env\n\
chmod 644 /etc/container-info.env\n\
\n\
# 配置代理（如果启用）\n\
if [ "$USE_PROXY" = "true" ]; then\n\
    echo "正在配置宿主机代理: $HTTP_PROXY"\n\
    \n\
    # 配置APT代理\n\
    echo "Acquire::http::Proxy \"$HTTP_PROXY\";" > /etc/apt/apt.conf.d/95proxies\n\
    echo "Acquire::https::Proxy \"$HTTPS_PROXY\";" >> /etc/apt/apt.conf.d/95proxies\n\
    \n\
    # 配置Git代理\n\
    git config --global http.proxy "$HTTP_PROXY"\n\
    git config --global https.proxy "$HTTPS_PROXY"\n\
    \n\
    # 配置wget代理\n\
    echo "use_proxy = on" > /root/.wgetrc\n\
    echo "http_proxy = $HTTP_PROXY" >> /root/.wgetrc\n\
    echo "https_proxy = $HTTPS_PROXY" >> /root/.wgetrc\n\
    echo "no_proxy = $NO_PROXY" >> /root/.wgetrc\n\
    \n\
    # 配置环境变量到profile（永久生效）\n\
    echo "export HTTP_PROXY=$HTTP_PROXY" >> /etc/profile.d/proxy.sh\n\
    echo "export HTTPS_PROXY=$HTTPS_PROXY" >> /etc/profile.d/proxy.sh\n\
    echo "export http_proxy=$HTTP_PROXY" >> /etc/profile.d/proxy.sh\n\
    echo "export https_proxy=$HTTPS_PROXY" >> /etc/profile.d/proxy.sh\n\
    echo "export NO_PROXY=$NO_PROXY" >> /etc/profile.d/proxy.sh\n\
    echo "export no_proxy=$NO_PROXY" >> /etc/profile.d/proxy.sh\n\
    \n\
    echo "代理配置完成: $HTTP_PROXY"\n\
fi\n\
\n\
# 配置Code-server\n\
if [ ! -z "$CODESERVER_PASSWORD" ]; then\n\
    echo "bind-addr: 0.0.0.0:8080" > /root/.config/code-server/config.yaml\n\
    echo "auth: password" >> /root/.config/code-server/config.yaml\n\
    echo "password: $CODESERVER_PASSWORD" >> /root/.config/code-server/config.yaml\n\
    echo "cert: false" >> /root/.config/code-server/config.yaml\n\
else\n\
    echo "bind-addr: 0.0.0.0:8080" > /root/.config/code-server/config.yaml\n\
    echo "auth: none" >> /root/.config/code-server/config.yaml\n\
    echo "cert: false" >> /root/.config/code-server/config.yaml\n\
fi\n\
\n\
# 启动Code-server\n\
nohup code-server /workspace > /var/log/code-server.log 2>&1 &\n\
\n\
# 配置并启动Syncthing\n\
if [ ! -f /root/.config/syncthing/config.xml ]; then\n\
    echo "初始化Syncthing配置..."\n\
    syncthing -generate="/root/.config/syncthing" > /dev/null 2>&1\n\
fi\n\
\n\
# 修改Syncthing GUI地址为0.0.0.0\n\
if [ -f /root/.config/syncthing/config.xml ]; then\n\
    sed -i "s/<address>127\\.0\\.0\\.1:/<address>0.0.0.0:/" /root/.config/syncthing/config.xml\n\
fi\n\
\n\
# 启动Syncthing\n\
nohup syncthing -no-browser -home="/root/.config/syncthing" > /var/log/syncthing.log 2>&1 &\n\
\n\
# 保持容器运行\n\
tail -f /dev/null\n\
' > /start.sh && chmod +x /start.sh

WORKDIR /workspace

# 暴露SSH和Code-server端口
EXPOSE 22 8080

# 启动脚本
CMD ["/start.sh"]

