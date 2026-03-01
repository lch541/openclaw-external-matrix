#!/bin/bash
set -e

echo "================================================="
echo "  OpenClaw Matrix Client 卸载脚本"
echo "================================================="

# 默认 OpenClaw 目录为当前执行目录
OPENCLAW_DIR=$(pwd)
PLUGIN_DIR="$OPENCLAW_DIR/extensions/matrix-plugin"

# 1. 停止并移除本地 E2EE 代理服务
echo ">>> 步骤 1: 停止本地 E2EE 代理服务"
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

# 2. 移除插件目录和相关文件
echo ""
echo ">>> 步骤 2: 移除插件目录"
if [ -d "$PLUGIN_DIR" ]; then
    rm -rf "$PLUGIN_DIR"
    echo "[成功] 已删除插件目录: $PLUGIN_DIR"
else
    echo "[提示] 插件目录不存在，无需删除。"
fi

# 3. 清理 OpenClaw 配置文件
echo ""
echo ">>> 步骤 3: 清理 OpenClaw 配置文件中的 Matrix 配置"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    ALT_CONFIG=$(ls /home/*/.openclaw/openclaw.json 2>/dev/null | head -n 1 || true)
    if [ -n "$ALT_CONFIG" ]; then
        OPENCLAW_CONFIG="$ALT_CONFIG"
    fi
fi

if [ -f "$OPENCLAW_CONFIG" ]; then
    # 使用 Node.js 脚本安全地修改 JSON5 文件
    cat > "cleanup_config.cjs" << 'EOF'
const fs = require('fs');
const path = process.argv[2];

try {
  let content = fs.readFileSync(path, 'utf8');
  
  // 移除所有 Matrix 相关的插件配置
  const regexMatrixPlugin = /"@openclaw\/matrix-plugin(-custom)?"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  content = content.replace(regexMatrixPlugin, '');
  
  // 移除 channels.matrix 配置
  const regexChannel = /"matrix"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  content = content.replace(regexChannel, '');
  
  // 清理多余逗号和空行
  content = content.replace(/,\s*,/g, ',');
  content = content.replace(/,\s*\}/g, '\n  }');
  
  fs.writeFileSync(path, content, 'utf8');
  console.log('[成功] 已从 openclaw.json 中移除 Matrix 相关配置。');
} catch (e) {
  console.error('[错误] 修改配置文件失败:', e.message);
}
EOF
    node "cleanup_config.cjs" "$OPENCLAW_CONFIG"
    rm -f "cleanup_config.cjs"
else
    echo "[提示] 未找到 OpenClaw 配置文件，无需清理。"
fi

# 4. 重启 OpenClaw
echo ""
echo ">>> 步骤 4: 重启 OpenClaw"
if command -v pm2 &> /dev/null && pm2 describe openclaw &> /dev/null; then
    pm2 restart openclaw
    echo "[成功] 已通过 pm2 重启 OpenClaw。"
elif systemctl is-active --quiet openclaw-gateway; then
    systemctl --user restart openclaw-gateway || sudo systemctl restart openclaw-gateway || true
    echo "[成功] 已通过 systemctl 重启 OpenClaw。"
fi

echo "================================================="
echo "  卸载完成！Matrix 环境已彻底清理。"
echo "================================================="
