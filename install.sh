#!/bin/bash
set -e

echo "================================================="
echo "  OpenClaw Matrix Plugin 一键安装脚本"
echo "================================================="

# 默认 OpenClaw 目录为当前执行目录
OPENCLAW_DIR=$(pwd)
PLUGIN_DIR="$OPENCLAW_DIR/extensions/matrix-plugin"
CONFIG_FILE="$OPENCLAW_DIR/config.json"
BACKUP_FILE="$OPENCLAW_DIR/config.json.matrix_plugin_backup_$(date +%Y%m%d%H%M%S)"

# 1. 备份 OpenClaw 配置文件
echo ">>> 步骤 1: 备份 OpenClaw 配置文件"
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "[成功] 已备份配置文件至: $BACKUP_FILE"
else
    echo "[警告] 未在 $OPENCLAW_DIR 找到 config.json，跳过备份。"
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
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    ALT_CONFIG=$(ls /home/*/.openclaw/openclaw.json 2>/dev/null | head -n 1 || true)
    if [ -n "$ALT_CONFIG" ]; then
        OPENCLAW_CONFIG="$ALT_CONFIG"
    fi
fi

if [ -f "$OPENCLAW_CONFIG" ]; then
    echo "[提示] 找到 OpenClaw 配置文件: $OPENCLAW_CONFIG"
    cp "$OPENCLAW_CONFIG" "${OPENCLAW_CONFIG}.matrix_backup_$(date +%s)"
    
    # 使用 Node.js 脚本安全地修改 JSON5 文件，避免 jq 破坏格式
    cat > "$PLUGIN_DIR/update_config.cjs" << 'EOF'
const fs = require('fs');
const path = process.argv[2];
const pluginDir = process.argv[3];

try {
  // 尝试使用简单的正则替换，因为 openclaw.json 可能是 json5 格式，JSON.parse 可能会失败
  let content = fs.readFileSync(path, 'utf8');
  
  // 如果已经存在，先移除旧的
  const regex = /"@openclaw\/matrix-plugin"\s*:\s*\{[^}]*\}/g;
  content = content.replace(regex, '');
  
  // 找到 plugins.installs 的位置并插入
  const installsMatch = content.match(/"installs"\s*:\s*\{/);
  if (installsMatch) {
    const insertPos = installsMatch.index + installsMatch[0].length;
    const newPlugin = `\n      "@openclaw/matrix-plugin": { "source": "local", "path": "${pluginDir}" },`;
    content = content.slice(0, insertPos) + newPlugin + content.slice(insertPos);
    
    // 清理可能产生的多余逗号 (简单的清理，不完美但有效)
    content = content.replace(/,\s*,/g, ',');
    
    fs.writeFileSync(path, content, 'utf8');
    console.log('[成功] 已将插件注册到 openclaw.json');
  } else {
    console.log('[警告] 未找到 plugins.installs 节点，无法自动注册。');
  }
} catch (e) {
  console.error('[错误] 修改配置文件失败:', e.message);
}
EOF
    
    node "$PLUGIN_DIR/update_config.cjs" "$OPENCLAW_CONFIG" "$PLUGIN_DIR"
    rm "$PLUGIN_DIR/update_config.cjs"
else
    echo "[提示] 未找到 openclaw.json，跳过自动注册。"
fi

# 7. 运行 OpenClaw Doctor 修复潜在的配置错误
echo ""
echo ">>> 步骤 7: 运行 openclaw doctor --fix"
if command -v openclaw &> /dev/null; then
    openclaw doctor --fix || true
else
    # 尝试使用 npx 运行
    npx -y @openclaw/cli doctor --fix || true
fi

# 8. 重启 OpenClaw
echo ""
echo ">>> 步骤 8: 重启 OpenClaw"
if command -v pm2 &> /dev/null && pm2 describe openclaw &> /dev/null; then
    pm2 restart openclaw
    echo "[成功] 已通过 pm2 重启 OpenClaw。"
elif systemctl is-active --quiet openclaw; then
    sudo systemctl restart openclaw
    echo "[成功] 已通过 systemctl 重启 OpenClaw。"
else
    echo "[提示] 未检测到 pm2 或 systemctl 托管的 openclaw 服务。"
    echo "请手动重启 OpenClaw 以使插件生效。"
fi

echo "================================================="
echo "  安装完成！Matrix 插件已成功集成到 OpenClaw。"
echo "================================================="
