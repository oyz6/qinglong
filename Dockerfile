FROM whyour/qinglong:debian

WORKDIR /ql

# 安装依赖（Debian 版）
RUN set -x \
    && apt-get update \
    && apt-get install -y \
        jq \
        gcc \
        g++ \
        python3-dev \
        libffi-dev \
        libssl-dev \
        build-essential \
        default-libmysqlclient-dev \
        pkg-config \
        libcairo2-dev \
        libjpeg-dev \
        libpango1.0-dev \
        libgif-dev \
        librsvg2-dev \
        git \
        tzdata \
        curl \
        coreutils \
        chromium \
        chromium-driver \
        fonts-freefont-ttf \
        fonts-noto-cjk \
        libnss3 \
        libfreetype6 \
        libharfbuzz0b \
        ca-certificates \
        sshpass \
        udev \
        xvfb \
        dbus \
    && pip3 install --no-cache-dir \
        user-agent aiohttp jieba ping3 requests selenium \
    && npm install -g \
        axios js-base64 typescript crypto-js jsdom tough-cookie \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 设置 Chromium 环境变量
ENV TZ=Asia/Shanghai \
    CHROME_BIN=/usr/bin/chromium \
    CHROME_PATH=/usr/lib/chromium/ \
    CHROMIUM_FLAGS="--disable-software-rasterizer --disable-dev-shm-usage --no-sandbox"

# 复制脚本
COPY entrypoint.sh /entrypoint.sh
COPY qinglong-backup.sh /ql/qinglong-backup.sh
COPY qinglong-restore.sh /ql/qinglong-restore.sh

# 权限
RUN chmod +x /entrypoint.sh /ql/qinglong-backup.sh /ql/qinglong-restore.sh

ENTRYPOINT ["/entrypoint.sh"]
