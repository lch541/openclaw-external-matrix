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

# 3. 重启 OpenClaw
echo ""
echo ">>> 步骤 3: 重启 OpenClaw"
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
