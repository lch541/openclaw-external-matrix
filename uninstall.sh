#!/bin/bash
set -e

echo "========================================="
echo "  OpenClaw External Matrix 卸载"
echo "========================================="
echo ""

INSTALL_DIR="$HOME/.openclaw/external-matrix"

# 停止服务
echo ">>> 停止服务"

if command -v pm2 &> /dev/null; then
    if pm2 describe openclaw-external-matrix &> /dev/null; then
        pm2 stop openclaw-external-matrix
        pm2 delete openclaw-external-matrix
        pm2 save
        echo "✅ pm2 服务已停止"
    fi
fi

if systemctl --user list-unit-files | grep -q "openclaw-external-matrix.service"; then
    systemctl --user stop openclaw-external-matrix.service 2>/dev/null || true
    systemctl --user disable openclaw-external-matrix.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/openclaw-external-matrix.service"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "✅ systemd 服务已停止"
fi

echo ""

# 恢复配置
echo ">>> 恢复 OpenClaw 配置"

OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"

# 查找最新的备份文件
BACKUP_FILE=$(ls -t "$HOME/.openclaw/openclaw.json.external_matrix_backup_"* 2>/dev/null | head -n 1 || true)

if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$OPENCLAW_CONFIG"
    echo "✅ 已恢复配置: $BACKUP_FILE"
    rm -f "$BACKUP_FILE"
else
    # 手动移除 matrix 配置
    if [ -f "$OPENCLAW_CONFIG" ]; then
        node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('$OPENCLAW_CONFIG', 'utf8'));
if (config.channels && config.channels.matrix) {
    delete config.channels.matrix;
    if (Object.keys(config.channels).length === 0) {
        delete config.channels;
    }
    fs.writeFileSync('$OPENCLAW_CONFIG', JSON.stringify(config, null, 2));
    console.log('Matrix 信道配置已移除');
}
"
    fi
fi

echo ""

# 删除安装目录
if [ -d "$INSTALL_DIR" ]; then
    echo ">>> 删除安装目录"
    read -p "确定要删除 $INSTALL_DIR 吗? [y/N]: " CONFIRM < /dev/tty
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        rm -rf "$INSTALL_DIR"
        echo "✅ 安装目录已删除"
    fi
fi

echo ""
echo "========================================="
echo "  卸载完成"
echo "========================================="
echo ""
echo "如需重新使用 Matrix 信道，请运行:"
echo "  openclaw configure --section channels"
echo ""