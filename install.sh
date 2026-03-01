#!/bin/bash
set -e

echo "================================================="
echo "  OpenClaw Matrix Plugin 一键安装脚本"
echo "================================================="

# 默认 OpenClaw 目录为当前执行目录
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

if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo "[警告] 未找到 openclaw.json，请确保 OpenClaw 已正确安装并运行过一次。"
    echo "插件代码将被下载，但无法自动注册到 OpenClaw 配置文件中。"
else
    echo "[成功] 找到配置文件: $OPENCLAW_CONFIG"
    # 备份配置文件
    BACKUP_FILE="${OPENCLAW_CONFIG}.matrix_backup_$(date +%Y%m%d%H%M%S)"
    cp "$OPENCLAW_CONFIG" "$BACKUP_FILE"
    echo "[成功] 已备份配置文件至: $BACKUP_FILE"
fi

# 2. 从 GitHub 克隆插件
echo ""
echo ">>> 步骤 2: 从 GitHub 下载 Matrix 插件"
mkdir -p "$OPENCLAW_DIR/extensions"
if [ -d "$PLUGIN_DIR" ]; then
    echo "[提示] 插件目录已存在，正在更新..."
    cd "$PLUGIN_DIR"
    git pull origin main || git pull origin master
    cd - > /dev/null
else
    git clone https://github.com/lch541/matrix_plugin "$PLUGIN_DIR"
fi
echo "[成功] 插件下载完成。"

# 3. 安装依赖
echo ""
echo ">>> 步骤 3: 安装插件依赖"
cd "$PLUGIN_DIR"
if command -v npm &> /dev/null; then
    npm install --production
    echo "[成功] 依赖安装完成。"
else
    echo "[错误] 未找到 npm 命令，请确保已安装 Node.js。"
    exit 1
fi
cd - > /dev/null

# 4. 获取用户输入的 Matrix 配置信息
echo ""
echo ">>> 步骤 4: 配置 Matrix 账户信息"
# 注意：通过 curl | bash 执行时，标准输入被占用，需要从 /dev/tty 读取
read -p "请输入 Homeserver URL (默认: https://matrix.org): " HOMESERVER < /dev/tty
HOMESERVER=${HOMESERVER:-https://matrix.org}

read -p "请输入 User ID (例如: @bot:matrix.org): " USER_ID < /dev/tty
read -p "请输入 Access Token: " ACCESS_TOKEN < /dev/tty
read -p "请输入 Room ID (例如: !room:matrix.org): " ROOM_ID < /dev/tty
read -p "请输入设备 ID (可选, 默认: OPENCLAW_PROXY): " DEVICE_ID < /dev/tty
DEVICE_ID=${DEVICE_ID:-OPENCLAW_PROXY}

# 5. 写入配置信息到本地代理 (.env)
echo ""
echo ">>> 步骤 5: 写入配置信息到本地代理 (.env)"
cat > "$PLUGIN_DIR/.env" << EOF
REAL_HOMESERVER=$HOMESERVER
USER_ID=$USER_ID
ACCESS_TOKEN=$ACCESS_TOKEN
ROOM_ID=$ROOM_ID
DEVICE_ID=$DEVICE_ID
PROXY_PORT=3000
EOF
echo "[成功] 代理配置已保存到 .env。"

# 6. 注册官方信道到 OpenClaw 配置
echo ""
echo ">>> 步骤 6: 注册官方信道到 OpenClaw (指向本地代理)"
if [ -f "$OPENCLAW_CONFIG" ]; then
    # 使用 Node.js 脚本安全地修改 JSON5 文件
    cat > "$PLUGIN_DIR/update_config.cjs" << 'EOF'
const fs = require('fs');
const path = process.argv[2];
const proxyUrl = process.argv[3];
const userId = process.argv[4];
const accessToken = process.argv[5];
const roomId = process.argv[6];

try {
  let content = fs.readFileSync(path, 'utf8');
  
  // 彻底移除旧的插件配置 (解耦，不再需要注入插件)
  const regexNested = /"@openclaw\/matrix-plugin"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  const regexFlat = /"@openclaw\/matrix-plugin"\s*:\s*\{[^}]*\}\s*,?/g;
  const regexCustomNested = /"@openclaw\/matrix-plugin-custom"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  const regexCustomFlat = /"@openclaw\/matrix-plugin-custom"\s*:\s*\{[^}]*\}\s*,?/g;
  content = content.replace(regexNested, '');
  content = content.replace(regexFlat, '');
  content = content.replace(regexCustomNested, '');
  content = content.replace(regexCustomFlat, '');
  
  // 移除旧的 channels.matrix 配置
  const regexChannel = /"matrix"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  content = content.replace(regexChannel, '');
  
  // 注入官方信道 (Channel) 配置，Homeserver 指向本地代理！
  const channelEntry = `"matrix": {
      "enabled": true,
      "homeserver": "${proxyUrl}",
      "userId": "${userId}",
      "accessToken": "${accessToken}",
      "roomId": "${roomId}"
    }`;
  
  if (/"channels"\s*:/.test(content)) {
    content = content.replace(/"channels"\s*:\s*\{/, `"channels": {\n      ${channelEntry},`);
  } else {
    const lastBrace = content.lastIndexOf('}');
    if (lastBrace !== -1) {
      const beforeBrace = content.slice(0, lastBrace).trim();
      const needsComma = !beforeBrace.endsWith(',') && !beforeBrace.endsWith('{');
      const prefix = needsComma ? ',' : '';
      const insertStr = `${prefix}\n  "channels": {\n    ${channelEntry}\n  }\n`;
      content = content.slice(0, lastBrace) + insertStr + content.slice(lastBrace);
    }
  }

  // 清理多余逗号
  content = content.replace(/,\s*,/g, ',');
  content = content.replace(/,\s*\}/g, '\n  }');
  
  fs.writeFileSync(path, content, 'utf8');
  console.log('[成功] 已将官方 Matrix 信道配置为指向本地 E2EE 代理 (127.0.0.1:3000)');
} catch (e) {
  console.error('[错误] 修改配置文件失败:', e.message);
}
EOF
    
    node "$PLUGIN_DIR/update_config.cjs" "$OPENCLAW_CONFIG" "http://127.0.0.1:3000" "$USER_ID" "$ACCESS_TOKEN" "$ROOM_ID"
    rm -f "$PLUGIN_DIR/update_config.cjs"
else
    echo "[提示] 未找到 openclaw.json，跳过自动注册。"
fi

# 7. 启用官方信道并运行 OpenClaw Doctor
echo ""
echo ">>> 步骤 7: 启用官方信道并运行 openclaw doctor --fix"
if command -v openclaw &> /dev/null; then
    openclaw plugins enable matrix || true
    openclaw doctor --fix || true
else
    npx -y @openclaw/cli plugins enable matrix || true
    npx -y @openclaw/cli doctor --fix || true
fi

# 8. 启动本地 E2EE 代理服务并设置开机自启
echo ""
echo ">>> 步骤 8: 启动本地 E2EE 代理服务并设置开机自启"
cd "$PLUGIN_DIR"
if command -v pm2 &> /dev/null; then
    # 使用 pm2 启动代理服务
    pm2 delete matrix-e2ee-proxy &> /dev/null || true
    pm2 start npm --name "matrix-e2ee-proxy" -- run dev
    pm2 save
    echo "[成功] 已通过 pm2 启动本地 E2EE 代理服务 (matrix-e2ee-proxy)。"
    echo "[提示] 请确保您已经运行过 'pm2 startup' 以启用 pm2 的开机自启功能。"
else
    # 如果没有 pm2，则使用 systemd 用户服务来实现开机自启
    echo "[提示] 未检测到 pm2，将使用 systemd 配置开机自启..."
    SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"
    SERVICE_FILE="$SERVICE_DIR/matrix-e2ee-proxy.service"
    
    NPM_PATH=$(command -v npm)
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Matrix E2EE Proxy for OpenClaw
After=network.target

[Service]
Type=simple
WorkingDirectory=$PLUGIN_DIR
ExecStart=$NPM_PATH run dev
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable matrix-e2ee-proxy.service
    systemctl --user restart matrix-e2ee-proxy.service
    
    # 尝试启用 loginctl linger 以确保用户未登录时也能自启
    if command -v loginctl &> /dev/null; then
        loginctl enable-linger $USER || true
    fi
    
    echo "[成功] 已通过 systemd 启动本地 E2EE 代理服务并设置开机自启。"
fi
cd - > /dev/null

# 9. 重启 OpenClaw
echo ""
echo ">>> 步骤 9: 重启 OpenClaw"
if command -v pm2 &> /dev/null && pm2 describe openclaw &> /dev/null; then
    pm2 restart openclaw
    echo "[成功] 已通过 pm2 重启 OpenClaw。"
elif systemctl is-active --quiet openclaw-gateway; then
    systemctl --user restart openclaw-gateway || sudo systemctl restart openclaw-gateway || true
    echo "[成功] 已通过 systemctl 重启 OpenClaw。"
else
    echo "[提示] 未检测到 pm2 或 systemctl 托管的 openclaw 服务。"
    echo "请手动重启 OpenClaw 以使插件生效。"
fi

echo "================================================="
echo "  安装完成！Matrix 插件已成功集成到 OpenClaw。"
echo "================================================="
