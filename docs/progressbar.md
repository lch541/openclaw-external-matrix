# OpenClaw External Matrix - 进度条功能规格

## 概述

在 external-matrix 中实现进度条功能，通过 `/progress` 命令启用。启用后自动开启 verbose 模式并将操作日志格式化为进度条。

---

## 命令设计

### 命令表

| 命令 | 处理方式 | 功能 |
|------|----------|------|
| `/progress on` | 拦截 → 转为 `/verbose on` | 开启进度条模式 (自动开启 verbose) |
| `/progress off` | 拦截 → 转为 `/verbose off` | 关闭进度条模式 (自动关闭 verbose) |
| `/verbose on` | 不拦截，直接转发 | 只开启 verbose，原样显示日志 |
| `/verbose off` | 不拦截，直接转发 | 只关闭 verbose，原样显示日志 |

### 消息流程

```
用户: "/progress on"
      │
      ▼
external-matrix 拦截命令
      │
      ▼
转换为 "/verbose on" → 发送给 OpenClaw
      │
      ▼
OpenClaw 处理
      │
      ▼
返回: "✅ 进度条模式已开启"
      │
      ▼
external-matrix 检测到关键词
      │
      ▼
progressState.enable()
      │
      ▼
后续 verbose 输出 → 格式化成进度条 → editMessage

---

用户: "/verbose on"
      │
      ▼
不拦截，直接转发给 OpenClaw
      │
      ▼
OpenClaw 返回 verbose 日志
      │
      ▼
external-matrix 不拦截 → 直接发送给用户
```

---

## 核心设计

### 1. 命令拦截

在消息发往 OpenClaw 之前，检查是否是 `/progress` 命令：

```typescript
// 路由层检测
if (body.startsWith("/progress ")) {
  const subCmd = parts[1];  // on / off
  
  // 转换为 verbose 命令
  const convertedCmd = `/verbose ${subCmd}`;
  
  // 转发给 OpenClaw
  await sendToOpenClaw(convertedCmd);
  
  // 记录状态
  if (subCmd === "on") {
    progressState.enable();
  } else {
    progressState.disable();
  }
  return;
}
```

### 2. Verbose 状态检测（自动）

检测 OpenClaw 的响应关键词，自动同步状态：

| OpenClaw 响应关键词 | 状态变化 |
|---------------------|----------|
| `进度条模式已开启` / `verbose on` | → progressState.enable() |
| `进度条模式已关闭` / `verbose off` | → progressState.disable() |

### 3. 进度条格式化

将 OpenClaw 的操作日志转换为进度条格式：

```
🔄 处理中 [████████░░░] 80% - 读取文件...
```

**格式规范**:
- 前缀: `🔄 处理中`
- 进度条: `[████████░░░]` (10个字符)
- 百分比: `[██████░░░] 60%`
- 附加信息: 操作描述（截取前 50 字符）

### 4. 消息编辑

使用 Matrix API 编辑同一条消息：

- API: `PUT /_matrix/client/r0/rooms/{roomId}/send/m.room.edit/{eventId}`

### 5. 状态管理

```typescript
interface ProgressState {
  progressEnabled: boolean;   // progress 模式开关
  currentMessageId: string | null;  // 当前进度条消息的 eventId
  currentRoomId: string | null;
}
```

---

## 架构设计

```
用户发送消息
       │
       ▼
检测命令类型
       │
       ├─► /progress on  → 转换为 /verbose on → progressState.enable()
       ├─► /progress off → 转换为 /verbose off → progressState.disable()
       ├─► /verbose on   → 直接转发 → 不拦截
       ├─► /verbose off  → 直接转发 → 不拦截
       │
       ▼
转发给 OpenClaw
       │
       ▼
OpenClaw 返回响应
       │
       ▼
检测 verbose 状态变化 (关键词匹配)
       │
       ▼
检查 progressState.progressEnabled
       │
       ├─► 是 → 格式化进度条 + 编辑消息
       │
       └─► 否 → 直接发送原始消息
```

---

## 实现方案

### 1. 修改命令检测逻辑

在 `src/routes/commands.ts` 或 `src/routes/matrix.ts` 中：

```typescript
// 在消息发往 OpenClaw 之前
if (body.startsWith("/progress ")) {
  const subCmd = parts[1];  // on / off
  
  if (subCmd === "on") {
    // 转换为 verbose on
    await sendToOpenClaw("/verbose on");
    progressState.enable();
    await matrixClient.sendMessage(roomId, "✅ 进度条模式已开启");
  } else if (subCmd === "off") {
    // 转换为 verbose off
    await sendToOpenClaw("/verbose off");
    progressState.disable();
    await matrixClient.sendMessage(roomId, "⚪ 进度条模式已关闭");
  }
  return;
}

// /verbose 命令直接转发，不拦截
if (body.startsWith("/verbose ")) {
  await sendToOpenClaw(body);
  return;
}

// 其他消息直接转发
```

### 2. 关键词检测函数

在 `src/progress/state.ts` 中保持原有检测：

```typescript
const VERBOSE_ENABLE_KEYWORDS = [
  '进度条模式已开启',
  'verbose mode enabled',
  'verbose on',
];

const VERBOSE_DISABLE_KEYWORDS = [
  '进度条模式已关闭',
  'verbose mode disabled',
  'verbose off',
];
```

### 3. 集成到 routes/matrix.ts

在 `/send` 路由中：

```typescript
// 处理发送消息
if (progressState.progressEnabled && content.msgtype === "m.text") {
  const body = content.body || "";
  
  // 判断是否为中间过程日志
  const isLog = body.length < 200 && (
    body.includes("...") || 
    body.includes("读取") || 
    body.includes("分析") ||
    body.includes("Thinking") ||
    body.includes("🔄")
  );

  if (isLog) {
    const progressBar = formatProgressBar(body);
    // 发送或更新进度条
  } else if (currentMessageId) {
    // 最终回复：替换进度条
  }
}
```

---

## 测试用例

- [ ] `/progress on` 转换为 `/verbose on` 并启用进度条
- [ ] `/progress off` 转换为 `/verbose off` 并关闭进度条
- [ ] `/verbose on` 直接转发，不处理进度条
- [ ] `/verbose off` 直接转发，不处理进度条
- [ ] 进度条消息正确更新
- [ ] 最终回复替换进度条
- [ ] 关闭 progress 时同时关闭 verbose

---

## 注意事项

1. **命令拦截**：只拦截 `/progress` 命令，`/verbose` 命令直接转发
2. **状态同步**：当收到 `/progress on` 时，同时设置 progress 状态并转发 `/verbose on`
3. **消息频率**：不要每条日志都更新，合并相似操作
4. **错误处理**：如果编辑失败，降级为发送新消息

---

*文档版本: 1.2*
*更新: 2026-03-01 - 新增 /progress 命令设计*