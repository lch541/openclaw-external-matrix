#!/bin/bash
set -e

echo "================================================="
echo "  OpenClaw Matrix Plugin 一键卸载脚本"
echo "================================================="

OPENCLAW_DIR=$(pwd)
PLUGIN_DIR="$OPENCLAW_DIR/extensions/matrix-plugin"
CONFIG_FILE="$OPENCLAW_DIR/config.json"

# 1. 恢复 OpenClaw 配置文件备份
echo ">>> 步骤 1: 恢复 OpenClaw 配置文件"
LATEST_BACKUP=$(ls -t "$OPENCLAW_DIR"/config.json.matrix_plugin_backup_* 2>/dev/null | head -n 1 || true)

if [ -n "$LATEST_BACKUP" ]; then
    echo "[提示] 找到最近的备份文件: $LATEST_BACKUP"
    cp "$LATEST_BACKUP" "$CONFIG_FILE"
    echo "[成功] 已恢复配置文件。"
else
    echo "[警告] 未找到配置文件备份，跳过恢复步骤。"
fi

# 2. 移除插件目录
echo ""
echo ">>> 步骤 2: 移除 Matrix 插件"
if [ -d "$PLUGIN_DIR" ]; then
    rm -rf "$PLUGIN_DIR"
    echo "[成功] 插件目录已删除。"
else
    echo "[提示] 插件目录不存在，可能已经被移除。"
fi

# 3. 从 OpenClaw 配置中移除插件
echo ""
echo ">>> 步骤 3: 从 OpenClaw 配置中移除插件"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    ALT_CONFIG=$(ls /home/*/.openclaw/openclaw.json 2>/dev/null | head -n 1 || true)
    if [ -n "$ALT_CONFIG" ]; then
        OPENCLAW_CONFIG="$ALT_CONFIG"
    fi
fi

if [ -f "$OPENCLAW_CONFIG" ]; then
    cat > "$OPENCLAW_DIR/remove_config.cjs" << 'EOF'
const fs = require('fs');
const path = process.argv[2];

try {
  let content = fs.readFileSync(path, 'utf8');
  
  // 匹配插件配置并移除，包括可能的前导逗号或尾随逗号
  const regex1 = /,\s*"@openclaw\/matrix-plugin"\s*:\s*\{[^}]*\}/g;
  const regex2 = /"@openclaw\/matrix-plugin"\s*:\s*\{[^}]*\}\s*,/g;
  const regex3 = /"@openclaw\/matrix-plugin"\s*:\s*\{[^}]*\}/g;
  
  content = content.replace(regex1, '');
  content = content.replace(regex2, '');
  content = content.replace(regex3, '');
  
  fs.writeFileSync(path, content, 'utf8');
  console.log('[成功] 已从 openclaw.json 移除插件注册信息。');
} catch (e) {
  console.error('[错误] 修改配置文件失败:', e.message);
}
EOF
    
    node "$OPENCLAW_DIR/remove_config.cjs" "$OPENCLAW_CONFIG"
    rm "$OPENCLAW_DIR/remove_config.cjs"
fi

# 4. 运行 OpenClaw Doctor 修复潜在的配置错误
echo ""
echo ">>> 步骤 4: 运行 openclaw doctor --fix"
if command -v openclaw &> /dev/null; then
    openclaw doctor --fix || true
else
    npx -y @openclaw/cli doctor --fix || true
fi

# 5. 重启 OpenClaw
echo ""
echo ">>> 步骤 5: 重启 OpenClaw"
if command -v pm2 &> /dev/null && pm2 describe openclaw &> /dev/null; then
    pm2 restart openclaw
    echo "[成功] 已通过 pm2 重启 OpenClaw。"
elif systemctl is-active --quiet openclaw; then
    sudo systemctl restart openclaw
    echo "[成功] 已通过 systemctl 重启 OpenClaw。"
else
    echo "[提示] 未检测到 pm2 或 systemctl 托管的 openclaw 服务。"
    echo "请手动重启 OpenClaw 以使卸载生效。"
fi

echo "================================================="
echo "  卸载完成！OpenClaw 已恢复到安装插件前的状态。"
echo "================================================="
