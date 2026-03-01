# OpenClaw External Matrix - 进度条功能规格

## 概述

在 external-matrix 中实现进度条功能，通过**观察** OpenClaw 的响应自动检测 verbose 模式，然后将操作日志格式化为进度条并持续更新同一条消息。

---

## 核心设计

### 1. Verbose 状态检测（自动）

external-matrix **不拦截命令**，而是观察 OpenClaw 的响应来自动检测 verbose 状态：

| OpenClaw 响应关键词 | 状态变化 |
|---------------------|----------|
| `进度条模式已开启` / `verbose on` / `Verbose mode enabled` | → progressState.enable() |
| `进度条模式已关闭` / `verbose off` / `Verbose mode disabled` | → progressState.disable() |
| `Thinking...` / `Analyzing...` / `🔄` | → verbose 输出中 |

### 2. 进度条格式化

将 OpenClaw 的操作日志转换为进度条格式：

```
🔄 处理中 [████████░░░] 80% - 读取文件...
```

**格式规范**:
- 前缀: `🔄 处理中`
- 进度条: `[████████░░░]` (10个字符)
- 百分比: `[██████░░░] 60%`
- 附加信息: 操作描述（截取前 50 字符）

### 3. 消息编辑

使用 Matrix API 编辑同一条消息：

- API: `PUT /_matrix/client/r0/rooms/{roomId}/send/m.room.edit/{eventId}`
- 或使用 `m.edits` 事件

### 4. 状态存储

进度条模式状态保存在内存中：

```typescript
interface ProgressState {
  enabled: boolean;
  currentMessageId: string | null;  // 当前进度条消息的 eventId
  currentRoomId: string | null;
}
```

---

## 架构设计

```
用户: "/verbose on"
      │
      ▼
OpenClaw 处理命令
      │
      ▼
返回响应: "✅ 进度条模式已开启"
      │
      ▼
external-matrix 观察到响应
      │
      ▼
自动检测 verbose 状态
      │
      ├─► 匹配关键词 → progressState.enable()
      │
      ▼
后续消息 → 格式化成进度条
```

---

## 实现方案

### 1. 新增/修改文件

```
src/
├── progress/
│   ├── bar.ts          # 进度条格式化 (已存在)
│   └── state.ts        # 状态管理 (已存在)
├── matrix/
│   └── client.ts       # 需要添加 editMessage 方法
└── routes/
    └── matrix.ts       # 集成进度条逻辑
```

### 2. 关键词检测函数

在 `src/progress/state.ts` 或新文件中添加：

```typescript
const VERBOSE_ENABLE_KEYWORDS = [
  '进度条模式已开启',
  'verbose mode enabled',
  'verbose on',
  'verbose: on',
];

const VERBOSE_DISABLE_KEYWORDS = [
  '进度条模式已关闭',
  'verbose mode disabled',
  'verbose off',
  'verbose: off',
];

export function detectVerboseState(message: string): 'enable' | 'disable' | null {
  const lowerMessage = message.toLowerCase();
  
  if (VERBOSE_ENABLE_KEYWORDS.some(k => lowerMessage.includes(k.toLowerCase()))) {
    return 'enable';
  }
  if (VERBOSE_DISABLE_KEYWORDS.some(k => lowerMessage.includes(k.toLowerCase()))) {
    return 'disable';
  }
  return null;
}
```

### 3. 在 matrix.ts 中集成

在 `routes/matrix.ts` 的 `/send` 路由中：

```typescript
// 处理发送消息
app.put("/rooms/:roomId/send/:eventType/:txnId", async (req, res) => {
  const { roomId, eventType, txnId } = req.params;
  const content = req.body;
  
  // 1. 检测 verbose 状态变化
  if (content.body) {
    const stateChange = detectVerboseState(content.body);
    if (stateChange === 'enable') {
      progressState.enable();
    } else if (stateChange === 'disable') {
      progressState.disable();
    }
  }
  
  // 2. 如果在 verbose 模式，格式化消息
  if (progressState.isEnabled() && content.msgtype === 'm.text') {
    const progressBar = formatProgressBar(content.body);
    
    // 如果没有当前进度条消息，发送新消息
    if (!progressState.getCurrentMessage().messageId) {
      const response = await client.sendMessage(roomId, progressBar);
      progressState.setCurrentMessage(roomId, response.event_id);
    } else {
      // 更新现有进度条
      const { roomId: currentRoomId, messageId } = progressState.getCurrentMessage();
      await client.editMessage(currentRoomId, messageId, progressBar);
    }
  }
  
  // 3. 继续发送消息给 Matrix
  // ...
});
```

### 4. 添加 editMessage 方法

在 `src/matrix/client.ts` 中添加：

```typescript
public async editMessage(roomId: string, eventId: string, newContent: string) {
  return await this.client.sendEvent(
    roomId,
    "m.room.edit",
    {
      "m.new_content": {
        "msgtype": "m.text",
        "body": newContent,
      },
      "m.relates_to": {
        "event_id": eventId,
        "rel_type": "m.replace",
      },
    },
    `edit_${Date.now()}`
  );
}
```

---

## 数据流

```
用户发送消息
       │
       ▼
OpenClaw 处理
       │
       ▼
返回响应 (via /sync)
       │
       ▼
matrix.ts 接收消息
       │
       ▼
detectVerboseState() 检测状态变化
       │
       ├─► enable → progressState.enable()
       ├─► disable → progressState.disable()
       │
       ▼
检查 progressState.isEnabled()
       │
       ├─► 是 → 格式化进度条 + 编辑消息
       │
       └─► 否 → 直接发送原始消息
```

---

## 测试用例

- [ ] OpenClaw 返回 "verbose on" → 自动启用进度条
- [ ] OpenClaw 返回 "verbose off" → 自动禁用进度条
- [ ] 进度条消息正确更新
- [ ] 最终回复替换进度条
- [ ] 关闭时只显示最终回复
- [ ] 命令不经过 external-matrix 拦截

---

## 注意事项

1. **不拦截命令**: `/verbose` 命令直接传给 OpenClaw，external-matrix 只观察响应
2. **消息频率**: 不要每条日志都更新，合并相似操作
3. **错误处理**: 如果编辑失败，降级为发送新消息
4. **关键词扩展**: 可根据 OpenClaw 的实际输出扩展检测关键词

---

*文档版本: 1.1*
*更新: 2026-03-01 - 改为自动检测 verbose 状态*