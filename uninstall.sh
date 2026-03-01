#!/bin/bash
set -e

echo "================================================="
echo "  OpenClaw Matrix Plugin 一键卸载与清理脚本"
echo "================================================="

OPENCLAW_DIR=$(pwd)
PLUGIN_DIR="$OPENCLAW_DIR/extensions/matrix-plugin"

# 1. 查找 OpenClaw 配置文件
echo ">>> 步骤 1: 查找 OpenClaw 配置文件"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    ALT_CONFIG=$(ls /home/*/.openclaw/openclaw.json 2>/dev/null | head -n 1 || true)
    if [ -n "$ALT_CONFIG" ]; then
        OPENCLAW_CONFIG="$ALT_CONFIG"
    fi
fi

if [ -f "$OPENCLAW_CONFIG" ]; then
    # 尝试恢复备份
    echo ">>> 步骤 2: 恢复 OpenClaw 配置文件"
    CONFIG_DIR=$(dirname "$OPENCLAW_CONFIG")
    LATEST_BACKUP=$(ls -t "$CONFIG_DIR"/openclaw.json.matrix_backup_* 2>/dev/null | head -n 1 || true)
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo "[提示] 找到最近的备份文件: $LATEST_BACKUP"
        cp "$LATEST_BACKUP" "$OPENCLAW_CONFIG"
        echo "[成功] 已恢复配置文件。"
    else
        echo "[警告] 未找到配置文件备份，将尝试手动移除插件注册信息。"
        
        cat > "$OPENCLAW_DIR/remove_config.cjs" << 'EOF'
const fs = require('fs');
const path = process.argv[2];

try {
  let content = fs.readFileSync(path, 'utf8');
  
  // 移除旧的插件配置
  const regexNested = /"@openclaw\/matrix-plugin"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  const regexFlat = /"@openclaw\/matrix-plugin"\s*:\s*\{[^}]*\}\s*,?/g;
  content = content.replace(regexNested, '');
  content = content.replace(regexFlat, '');
  
  // 移除自定义插件配置
  const regexCustomNested = /"@openclaw\/matrix-plugin-custom"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  const regexCustomFlat = /"@openclaw\/matrix-plugin-custom"\s*:\s*\{[^}]*\}\s*,?/g;
  content = content.replace(regexCustomNested, '');
  content = content.replace(regexCustomFlat, '');
  
  // 移除 channels.matrix 配置（如果有）
  const regexChannel = /"matrix"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  content = content.replace(regexChannel, '');
  
  // 清理可能产生的多余逗号
  content = content.replace(/,\s*,/g, ',');
  content = content.replace(/,\s*\}/g, '\n  }');
  
  fs.writeFileSync(path, content, 'utf8');
  console.log('[成功] 已从 openclaw.json 移除所有 Matrix 插件和信道配置。');
} catch (e) {
  console.error('[错误] 修改配置文件失败:', e.message);
}
EOF
        
        node "$OPENCLAW_DIR/remove_config.cjs" "$OPENCLAW_CONFIG"
        rm -f "$OPENCLAW_DIR/remove_config.cjs"
    fi
else
    echo "[警告] 未找到 openclaw.json，跳过配置恢复。"
fi

# 3. 停止并移除本地 E2EE 代理服务
echo ""
echo ">>> 步骤 3: 停止本地 E2EE 代理服务"
if command -v pm2 &> /dev/null; then
    pm2 delete matrix-e2ee-proxy &> /dev/null || true
    pm2 save &> /dev/null || true
    echo "[成功] 已从 pm2 中移除 matrix-e2ee-proxy 服务。"
fi

if systemctl --user is-active --quiet matrix-e2ee-proxy.service 2>/dev/null || systemctl --user is-enabled --quiet matrix-e2ee-proxy.service 2>/dev/null; then
    systemctl --user stop matrix-e2ee-proxy.service || true
    systemctl --user disable matrix-e2ee-proxy.service || true
    rm -f "$HOME/.config/systemd/user/matrix-e2ee-proxy.service"
    systemctl --user daemon-reload || true
    echo "[成功] 已移除 systemd 中的 matrix-e2ee-proxy 服务。"
fi

# 尝试杀死后台进程 (兜底)
pkill -f "matrix-e2ee-proxy" || true
echo "[提示] 已清理后台运行的代理进程。"

# 4. 彻底移除插件目录和相关文件
echo ""
echo ">>> 步骤 4: 彻底清理 Matrix 插件文件"
if [ -d "$PLUGIN_DIR" ]; then
    rm -rf "$PLUGIN_DIR"
    echo "[成功] 插件目录 ($PLUGIN_DIR) 已彻底删除。"
else
    echo "[提示] 插件目录不存在，无需清理。"
fi

# 清理可能残留在当前目录的备份文件或临时文件
rm -f "$OPENCLAW_DIR"/config.json.matrix_plugin_backup_*
rm -f "$OPENCLAW_DIR"/remove_config.cjs
echo "[成功] 临时文件清理完毕。"

# 5. 清理 OpenClaw 未完成的 Session
echo ""
echo ">>> 步骤 5: 清理 OpenClaw 会话缓存"
SESSIONS_DIR="$HOME/.openclaw/sessions"
if [ ! -d "$SESSIONS_DIR" ]; then
    ALT_SESSIONS=$(ls -d /home/*/.openclaw/sessions 2>/dev/null | head -n 1 || true)
    if [ -n "$ALT_SESSIONS" ]; then
        SESSIONS_DIR="$ALT_SESSIONS"
    fi
fi

if [ -d "$SESSIONS_DIR" ]; then
    # 删除所有 session 文件，强制 OpenClaw 在重启后开启全新会话
    rm -rf "$SESSIONS_DIR"/*
    echo "[成功] 已清理 OpenClaw 会话缓存 ($SESSIONS_DIR)。"
else
    echo "[提示] 未找到 OpenClaw 会话目录，跳过清理。"
fi

# 6. 运行 OpenClaw Doctor 修复潜在的配置错误
echo ""
echo ">>> 步骤 6: 运行 openclaw doctor --fix"
if command -v openclaw &> /dev/null; then
    openclaw doctor --fix || true
else
    npx -y @openclaw/cli doctor --fix || true
fi

# 7. 重启 OpenClaw
echo ""
echo ">>> 步骤 7: 重启 OpenClaw"
if command -v pm2 &> /dev/null && pm2 describe openclaw &> /dev/null; then
    pm2 restart openclaw
    echo "[成功] 已通过 pm2 重启 OpenClaw。"
elif systemctl is-active --quiet openclaw-gateway; then
    systemctl --user restart openclaw-gateway || sudo systemctl restart openclaw-gateway || true
    echo "[成功] 已通过 systemctl 重启 OpenClaw。"
else
    echo "[提示] 未检测到 pm2 或 systemctl 托管的 openclaw 服务。"
    echo "请手动重启 OpenClaw 以使卸载生效。"
fi

echo "================================================="
echo "  卸载与清理完成！"
echo "  OpenClaw 已恢复纯净状态，随时可以重新安装插件。"
echo "================================================="
