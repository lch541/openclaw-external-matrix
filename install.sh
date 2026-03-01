#!/bin/bash
set -e

echo "========================================="
echo "  OpenClaw External Matrix 一键安装"
echo "========================================="
echo ""

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "❌ 错误: 未安装 Node.js，请先安装 Node.js 18+"
    exit 1
fi

# 检查 npm
if ! command -v npm &> /dev/null; then
    echo "❌ 错误: 未安装 npm，请先安装 Node.js"
    exit 1
fi

# 创建临时目录安装
TEMP_DIR=$(mktemp -d)
echo ">>> 下载项目到临时目录..."
git clone https://github.com/lch541/openclaw-external-matrix.git "$TEMP_DIR"
cd "$TEMP_DIR"

echo ">>> 安装依赖..."
npm install --production

# 配置环境变量
echo ""
echo ">>> 配置 Matrix 账户信息"

if [ -z "$REAL_HOMESERVER" ]; then
    read -p "请输入 Homeserver URL (默认: https://matrix.org): " HOMESERVER < /dev/tty
    HOMESERVER=${HOMESERVER:-https://matrix.org}
else
    HOMESERVER=$REAL_HOMESERVER
fi

if [ -z "$USER_ID" ]; then
    read -p "请输入 User ID (例如: @bot:matrix.org): " USER_ID < /dev/tty
fi

if [ -z "$ACCESS_TOKEN" ]; then
    read -p "请输入 Access Token: " ACCESS_TOKEN < /dev/tty
fi

if [ -z "$ROOM_ID" ]; then
    read -p "请输入 Room ID (例如: !room:matrix.org): " ROOM_ID < /dev/tty
fi

# 写入配置
cat > "$TEMP_DIR/.env" << EOF
REAL_HOMESERVER=$HOMESERVER
USER_ID=$USER_ID
ACCESS_TOKEN=$ACCESS_TOKEN
ROOM_ID=$ROOM_ID
DEVICE_ID=OPENCLAW_PROXY
PROXY_PORT=3344
EOF

echo "✅ 配置已保存"

# 安装到 ~/.openclaw/external-matrix
INSTALL_DIR="$HOME/.openclaw/external-matrix"
rm -rf "$INSTALL_DIR"
mv "$TEMP_DIR" "$INSTALL_DIR"

echo ""
echo ">>> 配置 OpenClaw"

# 查找配置文件
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_CONFIG" ]; then
    # 备份
    BACKUP_FILE="${OPENCLAW_CONFIG}.external_matrix_backup_$(date +%Y%m%d%H%M%S)"
    cp "$OPENCLAW_CONFIG" "$BACKUP_FILE"
    echo "✅ 已备份配置到: $BACKUP_FILE"

    # 更新配置
    node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('$OPENCLAW_CONFIG', 'utf8'));

config.channels = config.channels || {};
config.channels.matrix = {
    enabled: true,
    homeserver: 'http://localhost:3344',
    userId: '$USER_ID',
    accessToken: '$ACCESS_TOKEN',
    roomId: '$ROOM_ID'
};

fs.writeFileSync('$OPENCLAW_CONFIG', JSON.stringify(config, null, 2));
console.log('配置已更新');
"
    echo "✅ OpenClaw Matrix 信道已配置"
else
    echo "⚠️ 未找到 OpenClaw 配置文件，请手动配置"
fi

echo ""
echo ">>> 启动服务"

# 尝试 pm2
if command -v pm2 &> /dev/null; then
    pm2 delete openclaw-external-matrix &> /dev/null || true
    cd "$INSTALL_DIR"
    pm2 start npm --name "openclaw-external-matrix" -- run dev
    pm2 save
    echo "✅ 已通过 pm2 启动"
else
    # systemd
    SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"
    NPM_PATH=$(command -v npm)

    cat > "$SERVICE_DIR/openclaw-external-matrix.service" << EOF
[Unit]
Description=OpenClaw External Matrix
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$NPM_PATH run dev
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now openclaw-external-matrix.service 2>/dev/null || true
    loginctl enable-linger $USER 2>/dev/null || true
    echo "✅ 已通过 systemd 启动"
fi

echo ""
echo "========================================="
echo "  安装完成！"
echo "========================================="
echo ""
echo "服务目录: $INSTALL_DIR"
echo ""
echo "下一步:"
echo "  1. 重启 OpenClaw: openclaw gateway restart"
echo "  2. 在 Matrix 房间发送消息测试"
echo ""