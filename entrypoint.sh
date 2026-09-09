#!/bin/bash
set -e

echo "=========================================="
echo "  青龙面板 - 启动脚本"
echo "=========================================="

# -------------------------------
# 脚本路径配置
# -------------------------------
BACKUP_SCRIPT="/ql/qinglong-backup.sh"
RESTORE_SCRIPT="/ql/qinglong-restore.sh"
DATA_DIR="${DATA_DIR:-/ql/data}"
PORT="${PORT:-5700}"

# -------------------------------
# 锁文件，防止重复启动
# -------------------------------
LOCK_FILE=/tmp/qinglong_start.lock
if [ -f "$LOCK_FILE" ]; then
    echo "[WARN] 已检测到启动锁文件，退出重复启动"
    exit 0
fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# -------------------------------
# 配置 Git
# -------------------------------
setup_git() {
    echo "[INFO] 配置 Git..."
    git config --global user.email "${GH_EMAIL:-qinglong@render.com}"
    git config --global user.name "${GH_USER:-QingLong-Backup}"
    git config --global init.defaultBranch main
}

# -------------------------------
# 启动时恢复数据
# -------------------------------
restore_on_startup() {
    if [ -z "${GH_BACKUP_REPO:-}" ] || [ -z "${GH_TOKEN:-}" ]; then
        echo "[INFO] 未配置 GitHub 备份，跳过恢复检查"
        return 0
    fi

    echo "[INFO] 尝试从 GitHub 恢复..."
    
    if [ ! -f "$RESTORE_SCRIPT" ]; then
        echo "[WARN] 恢复脚本不存在: $RESTORE_SCRIPT"
        return 0
    fi

    if bash "$RESTORE_SCRIPT"; then
        echo "[SUCCESS] 数据恢复成功"
    else
        echo "[WARN] 数据恢复失败或无备份可用，将使用全新安装"
    fi
}

# -------------------------------
# 写入管理员账户信息
# -------------------------------
write_auth_json() {
    if [ -z "${ADMIN_USERNAME:-}" ] || [ -z "${ADMIN_PASSWORD:-}" ]; then
        echo "[WARN] 未设置 ADMIN_USERNAME 或 ADMIN_PASSWORD，跳过写入 auth.json"
        return
    fi

    local auth_file="$DATA_DIR/config/auth.json"
    if [ ! -f "$auth_file" ]; then
        echo "[INFO] 写入管理员账户信息到 auth.json..."
        mkdir -p "$(dirname "$auth_file")"
        cat > "$auth_file" <<EOF
{
  "username": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "salt": "",
  "hash": ""
}
EOF
        echo "[SUCCESS] auth.json 已生成"
    else
        echo "[INFO] auth.json 已存在，跳过生成"
    fi
}

# -------------------------------
# 启动青龙面板
# -------------------------------
start_qinglong() {
    echo "[INFO] 启动青龙面板 (端口: $PORT)..."
    /ql/docker/docker-entrypoint.sh &
    QL_PID=$!
    echo "[INFO] 青龙面板 PID: $QL_PID"

    COUNT=0
    MAX_WAIT=120
    while [ $COUNT -lt $MAX_WAIT ]; do
        if curl -s "http://0.0.0.0:${PORT}/api/system" >/dev/null 2>&1; then
            echo "[INFO] API 服务已就绪"
            return 0
        fi
        sleep 2
        COUNT=$((COUNT + 2))
        echo "[INFO] 等待 API 就绪... ($COUNT/$MAX_WAIT)"
    done
    
    echo "[WARN] API 服务启动超时，但继续运行"
}

# -------------------------------
# 显示配置信息
# -------------------------------
show_config() {
    echo "=========================================="
    echo "  配置信息"
    echo "=========================================="
    echo "  服务端口: $PORT"
    echo "  GitHub 仓库: ${GH_BACKUP_REPO:-未配置}"
    echo "  GitHub 分支: ${GH_BACKUP_BRANCH:-main}"
    echo "  请在青龙面板中添加定时备份任务: task /ql/qinglong-backup.sh"
    echo "  保留备份数: ${KEEP_BACKUPS:-5}"
    echo "  加密备份: $([ -n "${BACKUP_PASS:-}" ] && echo '是' || echo '否')"
    echo "=========================================="
}

# -------------------------------
# 主函数
# -------------------------------
main() {
    show_config
    setup_git
    restore_on_startup
    write_auth_json
    start_qinglong

    echo "=========================================="
    echo "[SUCCESS] 初始化完成"
    echo "  - 青龙面板已启动 (端口: $PORT)"
    echo "  - 后台备份守护进程运行中"
    echo "=========================================="
    
    wait
}

main "$@"
