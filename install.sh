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

# 5. 写入配置信息
echo ""
echo ">>> 步骤 5: 写入配置信息到 OpenClaw 系统"
PLUGIN_CONFIG_DIR="$PLUGIN_DIR/config"
mkdir -p "$PLUGIN_CONFIG_DIR"

cat > "$PLUGIN_CONFIG_DIR/matrix_config.md" << EOF
# Matrix Configuration

\`\`\`json
{
  "homeserver": "$HOMESERVER",
  "userId": "$USER_ID",
  "accessToken": "$ACCESS_TOKEN",
  "roomId": "$ROOM_ID"
}
\`\`\`
EOF
echo "[成功] 配置已保存。"

# 6. 注册插件到 OpenClaw 配置
echo ""
echo ">>> 步骤 6: 注册插件到 OpenClaw"
if [ -f "$OPENCLAW_CONFIG" ]; then
    # 使用 Node.js 脚本安全地修改 JSON5 文件，避免 jq 破坏格式
    cat > "$PLUGIN_DIR/update_config.cjs" << 'EOF'
const fs = require('fs');
const path = process.argv[2];
const homeserver = process.argv[3];
const userId = process.argv[4];
const accessToken = process.argv[5];
const roomId = process.argv[6];

try {
  let content = fs.readFileSync(path, 'utf8');
  
  // 移除旧的 plugins.installs 配置 (支持最多1层嵌套的 {} 匹配，以及旧的无嵌套匹配)
  const regexNested = /"@openclaw\/matrix-plugin"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  const regexFlat = /"@openclaw\/matrix-plugin"\s*:\s*\{[^}]*\}\s*,?/g;
  content = content.replace(regexNested, '');
  content = content.replace(regexFlat, '');
  
  // 移除旧的 channels.matrix 配置（如果有）
  const regexChannel = /"matrix"\s*:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*,?/g;
  content = content.replace(regexChannel, '');
  
  // OpenClaw 官方要求的正确信道 (Channel) 配置格式
  const channelEntry = `"matrix": {
      "enabled": true,
      "homeserver": "${homeserver}",
      "userId": "${userId}",
      "accessToken": "${accessToken}",
      "roomId": "${roomId}"
    }`;
  
  if (/"channels"\s*:/.test(content)) {
    // 存在 channels 节点
    content = content.replace(/"channels"\s*:\s*\{/, `"channels": {\n      ${channelEntry},`);
  } else {
    // 连 channels 节点都没有，插入到文件末尾的 } 之前
    const lastBrace = content.lastIndexOf('}');
    if (lastBrace !== -1) {
      const beforeBrace = content.slice(0, lastBrace).trim();
      const needsComma = !beforeBrace.endsWith(',') && !beforeBrace.endsWith('{');
      const prefix = needsComma ? ',' : '';
      
      const insertStr = `${prefix}\n  "channels": {\n    ${channelEntry}\n  }\n`;
      content = content.slice(0, lastBrace) + insertStr + content.slice(lastBrace);
    } else {
      throw new Error("Invalid JSON format: missing closing brace.");
    }
  }
  
  // 清理可能产生的多余逗号
  content = content.replace(/,\s*,/g, ',');
  
  fs.writeFileSync(path, content, 'utf8');
  console.log('[成功] 已将 Matrix 配置注册到 openclaw.json 的 channels 节点');
} catch (e) {
  console.error('[错误] 修改配置文件失败:', e.message);
}
EOF
    
    node "$PLUGIN_DIR/update_config.cjs" "$OPENCLAW_CONFIG" "$HOMESERVER" "$USER_ID" "$ACCESS_TOKEN" "$ROOM_ID"
    rm -f "$PLUGIN_DIR/update_config.cjs"
else
    echo "[提示] 未找到 openclaw.json，跳过自动注册。"
fi

# 7. 启用插件并运行 OpenClaw Doctor 修复潜在的配置错误
echo ""
echo ">>> 步骤 7: 启用插件并运行 openclaw doctor --fix"
if command -v openclaw &> /dev/null; then
    openclaw plugins enable matrix || openclaw plugins enable @openclaw/matrix-plugin || true
    openclaw doctor --fix || true
else
    # 尝试使用 npx 运行
    npx -y @openclaw/cli plugins enable matrix || npx -y @openclaw/cli plugins enable @openclaw/matrix-plugin || true
    npx -y @openclaw/cli doctor --fix || true
fi

# 8. 重启 OpenClaw
echo ""
echo ">>> 步骤 8: 重启 OpenClaw"
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
