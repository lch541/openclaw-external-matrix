# OpenClaw External Matrix - 进度条功能规格

## 概述

在 external-matrix 中实现进度条功能，当用户开启 `/verbose on` 时，将 OpenClaw 的操作日志格式化为进度条并持续更新同一条消息。

---

## 功能需求

### 1. 进度条格式化

将 OpenClaw 的操作日志转换为进度条格式：

```
🔄 处理中 [████████░░░] 80% - 读取文件...
```

**格式规范**:
- 前缀: `🔄 处理中`
- 进度条: `[████████░░░]` (10个字符)
- 百分比: `[██████░░░] 60%`
- 附加信息: 操作描述（截取前 50 字符）

### 2. 消息编辑

使用 Matrix API 编辑同一条消息：

- API: `PUT /_matrix/client/r0/rooms/{roomId}/send/m.room.edit/{eventId}`
- 或使用 `m.edits` 事件

### 3. /verbose 开关

| 命令 | 功能 |
|------|------|
| `/verbose on` | 开启进度条模式 |
| `/verbose off` | 关闭进度条模式，只显示最终回复 |

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
OpenClaw Matrix 信道
       │
       ▼ (HTTP 请求)
external-matrix (server.ts)
       │
       ├──► 路由层 (routes/matrix.ts)
       │         │
       │         ▼
       │    检查 /sync 请求
       │         │
       ├──► 消息处理 (消息队列)
       │         │
       │         ▼
       │    检查 verbose 模式
       │         │
       └──► 进度条模块 (新增)
                 │
                 ├─► 格式化进度条
                 ├─► 编辑消息
                 └─► 管理消息状态
```

---

## 实现方案

### 1. 新增文件

```
src/
├── progress/
│   ├── bar.ts          # 进度条格式化
│   └── state.ts        # 进度条状态管理
└── server.ts           # 集成
```

### 2. 核心模块

#### progress/bar.ts

```typescript
export function formatProgressBar(operation: string, percentage?: number): string {
  // 如果没有百分比，自动计算
  const percent = percentage || calculateProgress(operation);
  
  // 生成进度条
  const filled = Math.floor(percent / 10);
  const bar = '█'.repeat(filled) + '░'.repeat(10 - filled);
  
  // 截断操作描述
  const desc = operation.length > 50 
    ? operation.slice(0, 47) + '...' 
    : operation;
  
  return `🔄 处理中 [${bar}] ${percent}% - ${desc}`;
}

export function calculateProgress(operation: string): number {
  // 根据关键词估算进度
  if (operation.includes('reading') || operation.includes('读取')) return 20;
  if (operation.includes('analyzing') || operation.includes('分析')) return 40;
  if (operation.includes('searching') || operation.includes('搜索')) return 50;
  if (operation.includes('generating') || operation.includes('生成')) return 70;
  if (operation.includes('sending') || operation.includes('发送')) return 90;
  return 50; // 默认
}
```

#### progress/state.ts

```typescript
interface ProgressState {
  enabled: boolean;
  currentMessageId: string | null;
  currentRoomId: string | null;
}

class ProgressStateManager {
  private state: ProgressState = {
    enabled: false,
    currentMessageId: null,
    currentRoomId: null,
  };

  enable() { this.state.enabled = true; }
  disable() { this.state.enabled = false; }
  isEnabled() { return this.state.enabled; }

  setCurrentMessage(roomId: string, messageId: string) {
    this.state.currentRoomId = roomId;
    this.state.currentMessageId = messageId;
  }

  clearCurrentMessage() {
    this.state.currentRoomId = null;
    this.state.currentMessageId = null;
  }

  getCurrentMessage() {
    return {
      roomId: this.state.currentRoomId,
      messageId: this.state.currentMessageId,
    };
  }
}

export const progressState = new ProgressStateManager();
```

### 3. 集成到 server.ts

#### 3.1 监听 /send 消息

当 OpenClaw 发送消息时：

```typescript
// 在 routes/matrix.ts 的 send 路由中

// 检查 verbose 模式
if (progressState.isEnabled()) {
  // 如果是第一条消息，建立进度条
  if (!progressState.getCurrentMessage().messageId) {
    const response = await client.sendMessage(roomId, "🔄 处理中 [░░░░░░░░░░] 0%");
    progressState.setCurrentMessage(roomId, response.event_id);
  } else {
    // 更新进度条
    const { roomId, messageId } = progressState.getCurrentMessage();
    const progressBar = formatProgressBar(operation);
    await client.editMessage(roomId, messageId, progressBar);
  }
}
```

#### 3.2 监听命令

在 `routes/commands.ts` 中添加：

```typescript
if (cmd === "verbose") {
  if (subCmd === "on") {
    progressState.enable();
    await matrixClient.sendMessage(roomId, "✅ 进度条模式已开启");
  } else if (subCmd === "off") {
    progressState.disable();
    await matrixClient.sendMessage(roomId, "⚪ 进度条模式已关闭");
  }
}
```

---

## API 接口

### 消息编辑 (Matrix)

```typescript
// 编辑消息
await client.sendEvent(
  roomId,
  "m.room.edit",
  {
    "m.new_content": {
      "msgtype": "m.text",
      "body": newContent,
    },
    "m.relates_to": {
      "event_id": originalEventId,
      "rel_type": "m.replace",
    },
  },
  txnId
);
```

---

## 数据流

```
用户发送消息
       │
       ▼
server.ts 接收
       │
       ▼
routes/commands.ts
       │
       ├─► /verbose on → progressState.enable()
       │
       └─► 其他消息 → 转发给 OpenClaw
                    │
                    ▼
              OpenClaw 处理
                    │
                    ▼
              返回响应 (via /sync)
                    │
                    ▼
              检查 progressState.isEnabled()
                    │
                    ├─► 是 → 格式化进度条 + 编辑消息
                    │
                    └─► 否 → 直接发送消息
```

---

## 测试用例

- [ ] `/verbose on` 开启进度条模式
- [ ] `/verbose off` 关闭进度条模式
- [ ] 进度条消息正确更新
- [ ] 最终回复替换进度条
- [ ] 关闭时只显示最终回复
- [ ] 重启后 verbose 状态保持（可选）

---

## 注意事项

1. **消息频率**: 不要每条日志都更新，合并相似操作
2. **超时处理**: 如果 OpenClaw 处理超时，进度条保持最后状态
3. **错误处理**: 如果编辑失败，降级为发送新消息

---

*文档版本: 1.0*
*最后更新: 2026-03-01*