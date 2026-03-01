# OpenClaw External Matrix

OpenClaw 外部 Matrix 代理，提供以下功能：
- 进度条模式 (`/progress on`)
- 远程回滚 (`/openclaw revive <token>`)
- Gardian 通知 (`/api/notify`)
- E2EE 加解密支持

## 功能

| 命令 | 功能 |
|------|------|
| `/progress on` | 开启进度条模式 |
| `/progress off` | 关闭进度条模式 |
| `/verbose on` | 开启 verbose（不拦截） |
| `/verbose off` | 关闭 verbose（不拦截） |
| `/openclaw revive token set <密码>` | 设置回滚 Token |
| `/openclaw revive token show` | 查看 Token |
| `/openclaw revive <密码>` | 触发回滚 |

## 依赖

- Node.js 18+
- OpenClaw 已安装并运行

## 一键安装

```bash
# 安装
curl -sSL https://raw.githubusercontent.com/lch541/openclaw-external-matrix/main/install.sh | bash
```

或手动安装：

```bash
# 克隆项目
git clone https://github.com/lch541/openclaw-external-matrix.git ~/.openclaw/external-matrix
cd ~/.openclaw/external-matrix

# 安装依赖
npm install

# 配置
cp .env.example .env
# 编辑 .env 填入 Matrix 账号信息

# 启动
npm run dev
```

## 一键卸载

```bash
curl -sSL https://raw.githubusercontent.com/lch541/openclaw-external-matrix/main/uninstall.sh | bash
```

## 配置

安装时会交互式询问：

1. **Homeserver URL** - 例如 `https://matrix.org`
2. **User ID** - 例如 `@bot:matrix.org`
3. **Access Token** - 从 Element 设置中获取
4. **Room ID** - 例如 `!room:matrix.org`

## API 接口

### Gardian 通知

```bash
# 发送通知
curl -X POST "http://localhost:3344/api/notify" \
  -H "Content-Type: application/json" \
  -d '{"message": "备份完成"}'
```

## 与 OpenClaw 集成

安装脚本会自动：
1. 配置 Matrix 账号信息到 `.env`
2. 修改 `openclaw.json` 将 Matrix 信道指向本地代理 (`localhost:3344`)
3. 启动服务（pm2 或 systemd）

## 进度条效果

```
🔄 处理中 [████████░░] 80% - 读取文件...
```

## 目录结构

```
~/.openclaw/external-matrix/
├── src/
│   ├── server.ts           # 主入口
│   ├── config.ts           # 配置
│   ├── matrix/client.ts    # Matrix 客户端
│   ├── progress/           # 进度条模块
│   ├── commands/           # 命令处理
│   └── routes/             # API 路由
├── .env                    # 配置文件
└── package.json
```

## License

MIT