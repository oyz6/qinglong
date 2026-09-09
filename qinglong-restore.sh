#!/bin/bash
set -u

if [ -z "${GH_BACKUP_REPO:-}" ] || [ -z "${GH_TOKEN:-}" ]; then
    echo "[ERROR] 请设置 GH_BACKUP_REPO 和 GH_TOKEN"
    exit 1
fi

# 配置
GH_BACKUP_BRANCH=${GH_BACKUP_BRANCH:-main}
DATA_DIR=${DATA_DIR:-/ql/data}
API_BASE="https://api.github.com/repos/$GH_BACKUP_REPO"

echo "=========================================="
echo "  青龙面板恢复"
echo "=========================================="

# 获取备份文件名
BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
    echo "[INFO] 获取最新备份..."
    BACKUP_FILE=$(curl -s -H "Authorization: token $GH_TOKEN" \
        "$API_BASE/contents?ref=$GH_BACKUP_BRANCH" \
        | jq -r '.[].name' | grep '^ql_backup_.*\.tar\.gz$' | sort -r | head -n1)
fi

if [ -z "$BACKUP_FILE" ]; then
    echo "[ERROR] 未找到备份文件"
    exit 1
fi

echo "[INFO] 备份文件: $BACKUP_FILE"

# 下载
echo "[INFO] 下载中..."
curl -sL -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github.v3.raw" \
    -o "/tmp/ql_backup.tar.gz" \
    "$API_BASE/contents/$BACKUP_FILE?ref=$GH_BACKUP_BRANCH"

if [ ! -s "/tmp/ql_backup.tar.gz" ]; then
    echo "[ERROR] 下载失败"
    exit 1
fi

echo "[INFO] 大小: $(du -h /tmp/ql_backup.tar.gz | cut -f1)"

# 解压
echo "[INFO] 恢复数据..."
if [ -n "${BACKUP_PASS:-}" ]; then
    openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$BACKUP_PASS" \
        -in "/tmp/ql_backup.tar.gz" | tar xz -C "$DATA_DIR" --strip-components=1
else
    tar xzf "/tmp/ql_backup.tar.gz" -C "$DATA_DIR" --strip-components=1
fi

rm -f /tmp/ql_backup.tar.gz

echo "[SUCCESS] 恢复完成 🎉"
echo "[INFO] 恢复的目录:"
ls -la "$DATA_DIR"
