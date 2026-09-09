#!/bin/bash
set -u

###########################################
#  青龙面板备份脚本
###########################################

if [ -z "${GH_BACKUP_REPO:-}" ] || [ -z "${GH_TOKEN:-}" ]; then
    echo "[WARN] 缺少 GH_BACKUP_REPO 或 GH_TOKEN，跳过备份"
    exit 0
fi

# 配置
DATA_DIR=${DATA_DIR:-/ql/data}
GH_BACKUP_BRANCH=${GH_BACKUP_BRANCH:-main}
KEEP=${KEEP_BACKUPS:-5}
API_BASE="https://api.github.com/repos/$GH_BACKUP_REPO"
TIMESTAMP=$(TZ='Asia/Shanghai' date +"%Y-%m-%d-%H-%M-%S")
BACKUP_FILE="ql_backup_${TIMESTAMP}.tar.gz"

# 只备份这些目录
BACKUP_DIRS="config db scripts"

echo "[INFO] 开始备份: $BACKUP_FILE"
echo "[INFO] 备份目录: $BACKUP_DIRS"

# 临时目录
TEMP_DIR="/tmp/ql-backup-$$"
mkdir -p "$TEMP_DIR/data"
cd "$TEMP_DIR" || exit 1

# 复制必要目录
echo "[INFO] 复制必要数据..."
for dir in $BACKUP_DIRS; do
    if [ -d "$DATA_DIR/$dir" ]; then
        cp -R "$DATA_DIR/$dir" "$TEMP_DIR/data/" && echo "  ✓ $dir"
    else
        echo "  ⚠ $dir 不存在，跳过"
    fi
done

# 压缩备份
echo "[INFO] 压缩数据..."
if [ -n "${BACKUP_PASS:-}" ]; then
    echo "[INFO] 使用密码加密..."
    tar czf - -C "$TEMP_DIR" data/ | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$BACKUP_PASS" -out "$BACKUP_FILE"
else
    tar czf "$BACKUP_FILE" -C "$TEMP_DIR" data/
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "[INFO] 备份文件大小: $BACKUP_SIZE"

# Base64 编码到文件
base64 -w 0 "$BACKUP_FILE" > content.b64 2>/dev/null || base64 "$BACKUP_FILE" > content.b64

# 检查大小
B64_SIZE=$(wc -c < content.b64)
echo "[INFO] Base64 大小: $((B64_SIZE / 1024))K"
if [ "$B64_SIZE" -gt 100000000 ]; then
    echo "[ERROR] 文件太大（>100MB），无法上传"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 1. 上传备份文件
echo "[INFO] 上传备份文件..."
EXISTING_SHA=$(curl -s -H "Authorization: token $GH_TOKEN" \
    "$API_BASE/contents/$BACKUP_FILE?ref=$GH_BACKUP_BRANCH" 2>/dev/null | jq -r '.sha // empty')

# 关键修复：使用 --rawfile 从文件读取 base64 内容
if [ -n "$EXISTING_SHA" ]; then
    jq -n --rawfile content content.b64 \
          --arg msg "更新备份: $BACKUP_FILE" \
          --arg sha "$EXISTING_SHA" \
          --arg branch "$GH_BACKUP_BRANCH" \
          '{message: $msg, content: $content, sha: $sha, branch: $branch}' > payload.json
else
    jq -n --rawfile content content.b64 \
          --arg msg "备份: $BACKUP_FILE ($BACKUP_SIZE)" \
          --arg branch "$GH_BACKUP_BRANCH" \
          '{message: $msg, content: $content, branch: $branch}' > payload.json
fi

RESPONSE=$(curl -s -X PUT \
    -H "Authorization: token $GH_TOKEN" \
    -H "Content-Type: application/json" \
    -d @payload.json \
    "$API_BASE/contents/$BACKUP_FILE")

rm -f payload.json content.b64

if echo "$RESPONSE" | jq -e '.content.sha' >/dev/null 2>&1; then
    echo "[SUCCESS] 备份文件已上传 ✓"
else
    echo "[ERROR] 上传失败: $(echo "$RESPONSE" | jq -r '.message // "未知错误"')"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 2. 更新 README.md
echo "[INFO] 更新 README.md..."
README_SHA=$(curl -s -H "Authorization: token $GH_TOKEN" \
    "$API_BASE/contents/README.md?ref=$GH_BACKUP_BRANCH" | jq -r '.sha // empty')

README_TEXT="# 青龙面板备份

**最新备份:** \`$BACKUP_FILE\`  
**备份时间:** $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')  
**文件大小:** $BACKUP_SIZE  
**备份内容:** $BACKUP_DIRS
"

README_B64=$(echo -n "$README_TEXT" | base64 -w 0 2>/dev/null || echo -n "$README_TEXT" | base64)

if [ -n "$README_SHA" ]; then
    echo "{\"message\":\"更新README\",\"content\":\"$README_B64\",\"sha\":\"$README_SHA\",\"branch\":\"$GH_BACKUP_BRANCH\"}" > readme.json
else
    echo "{\"message\":\"创建README\",\"content\":\"$README_B64\",\"branch\":\"$GH_BACKUP_BRANCH\"}" > readme.json
fi

curl -s -X PUT \
    -H "Authorization: token $GH_TOKEN" \
    -H "Content-Type: application/json" \
    -d @readme.json \
    "$API_BASE/contents/README.md" >/dev/null

rm -f readme.json
echo "[SUCCESS] README.md 已更新 ✓"

# 3. 删除旧备份
echo "[INFO] 清理旧备份（保留 $KEEP 个）..."
OLD_BACKUPS=$(curl -s -H "Authorization: token $GH_TOKEN" \
    "$API_BASE/contents?ref=$GH_BACKUP_BRANCH" \
    | jq -r '.[].name' | grep '^ql_backup_.*\.tar\.gz$' | sort -r | tail -n +$((KEEP + 1)))

for old_file in $OLD_BACKUPS; do
    echo "[INFO] 删除: $old_file"
    OLD_SHA=$(curl -s -H "Authorization: token $GH_TOKEN" \
        "$API_BASE/contents/$old_file?ref=$GH_BACKUP_BRANCH" | jq -r '.sha')
    
    curl -s -X DELETE \
        -H "Authorization: token $GH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"message\":\"删除旧备份\",\"sha\":\"$OLD_SHA\",\"branch\":\"$GH_BACKUP_BRANCH\"}" \
        "$API_BASE/contents/$old_file" >/dev/null
done

# 4. 清理
rm -rf "$TEMP_DIR"

echo "[SUCCESS] 备份完成: $BACKUP_FILE 🎉"
