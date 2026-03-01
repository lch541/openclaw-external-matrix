import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import * as sdk from "matrix-js-sdk";
import { LocalStorage } from "node-localstorage";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";
import { EventEmitter } from "events";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = parseInt(process.env.PROXY_PORT || "3000", 10);
const REAL_HOMESERVER = process.env.REAL_HOMESERVER;
const USER_ID = process.env.USER_ID;
const ACCESS_TOKEN = process.env.ACCESS_TOKEN;
const DEVICE_ID = process.env.DEVICE_ID || "OPENCLAW_PROXY";

if (!REAL_HOMESERVER || !USER_ID || !ACCESS_TOKEN) {
  console.error("[Proxy] 错误: 缺少必要的环境变量 (REAL_HOMESERVER, USER_ID, ACCESS_TOKEN)");
  process.exit(1);
}

console.log(`[Proxy] 正在初始化本地 E2EE 代理...`);
console.log(`[Proxy] 目标 Homeserver: ${REAL_HOMESERVER}`);
console.log(`[Proxy] 登录用户: ${USER_ID}`);
console.log(`[Proxy] 设备 ID: ${DEVICE_ID}`);

// 1. 初始化持久化存储 (用于保存 E2EE 密钥)
const storagePath = path.join(__dirname, ".matrix_storage");
if (!fs.existsSync(storagePath)) {
  fs.mkdirSync(storagePath, { recursive: true });
}
const localStorage = new LocalStorage(storagePath);
const cryptoStore = new sdk.LocalStorageCryptoStore(localStorage);

// 2. 初始化 Matrix 客户端
const client = sdk.createClient({
  baseUrl: REAL_HOMESERVER,
  accessToken: ACCESS_TOKEN,
  userId: USER_ID,
  deviceId: DEVICE_ID,
  cryptoStore: cryptoStore,
  store: new sdk.MemoryStore(),
});

// 3. 设置事件监听与同步队列
const syncEmitter = new EventEmitter();
let nextBatchToken = Date.now();
let unreadEvents: any[] = [];

client.on(sdk.ClientEvent.Sync, (state) => {
  if (state === "PREPARED") {
    console.log("[Proxy] Matrix 客户端同步完成，已准备就绪！");
  }
});

client.on(sdk.RoomEvent.Timeline, (event, room, toStartOfTimeline) => {
  if (toStartOfTimeline) return; // 忽略历史分页加载的事件

  // 只关心消息事件
  if (event.getType() === "m.room.message") {
    const sender = event.getSender();
    // 忽略自己发送的消息，防止回音
    if (sender === USER_ID) return;

    console.log(`[Proxy] 收到新消息 [${room?.roomId}] ${sender}: ${event.getContent().body}`);

    // 构造明文事件，伪装成未加密的普通消息
    const decryptedEvent = {
      ...event.event,
      type: "m.room.message",
      content: event.getContent(), // 这里已经是解密后的明文内容了
    };

    unreadEvents.push({ roomId: room?.roomId, event: decryptedEvent });
    syncEmitter.emit("new_event");
  }
});

// 启动客户端
async function startClient() {
  try {
    // 在新版 matrix-js-sdk 中，使用 initRustCrypto
    // 由于在 Node 环境下没有 IndexedDB，我们需要禁用它
    if ((client as any).initRustCrypto) {
      await (client as any).initRustCrypto({ useIndexedDB: false });
      console.log("[Proxy] Rust E2EE 加密模块初始化成功");
    } else {
      console.warn("[Proxy] 未找到 initRustCrypto，尝试使用旧版加密初始化...");
      if ((client as any).initCrypto) {
        await (client as any).initCrypto();
      }
    }
    
    await client.startClient({ initialSyncLimit: 10 });
  } catch (err) {
    console.error("[Proxy] 启动客户端失败:", err);
  }
}
startClient();

// 4. 启动 Express 代理服务器
const app = express();
app.use(cors());
app.use(express.json());

// 拦截 OpenClaw 的 /sync 请求
app.get(["/_matrix/client/r0/sync", "/_matrix/client/v3/sync"], (req, res) => {
  const since = req.query.since as string;
  const timeout = parseInt(req.query.timeout as string) || 30000;

  const respond = () => {
    const response: any = {
      next_batch: nextBatchToken.toString(),
      rooms: { join: {} },
    };

    if (unreadEvents.length > 0) {
      for (const { roomId, event } of unreadEvents) {
        if (!response.rooms.join[roomId]) {
          response.rooms.join[roomId] = { timeline: { events: [] } };
        }
        response.rooms.join[roomId].timeline.events.push(event);
      }
      nextBatchToken++;
      unreadEvents = []; // 发送后清空队列
    }

    res.json(response);
  };

  // 如果没有 since，说明是 OpenClaw 刚启动，返回最近的历史记录
  if (!since) {
    const response: any = {
      next_batch: nextBatchToken.toString(),
      rooms: { join: {} },
    };

    const rooms = client.getRooms();
    for (const room of rooms) {
      const events = room.timeline
        .filter((e) => e.getType() === "m.room.message")
        .slice(-10) // 只返回最近 10 条
        .map((e) => ({
          ...e.event,
          type: "m.room.message",
          content: e.getContent(),
        }));

      if (events.length > 0) {
        response.rooms.join[room.roomId] = {
          timeline: { events },
        };
      }
    }
    return res.json(response);
  }

  // 如果有新事件，或者 timeout 为 0，立即返回
  if (unreadEvents.length > 0 || timeout === 0) {
    respond();
  } else {
    // 否则长轮询等待新事件
    const timer = setTimeout(() => {
      syncEmitter.removeListener("new_event", onNewEvent);
      respond();
    }, timeout);

    const onNewEvent = () => {
      clearTimeout(timer);
      respond();
    };

    syncEmitter.once("new_event", onNewEvent);
  }
});

// 拦截 OpenClaw 的发送消息请求
app.put(
  [
    "/_matrix/client/r0/rooms/:roomId/send/:eventType/:txnId",
    "/_matrix/client/v3/rooms/:roomId/send/:eventType/:txnId",
  ],
  async (req, res) => {
    const { roomId, eventType, txnId } = req.params;
    const content = req.body;

    console.log(`[Proxy] OpenClaw 请求发送消息到 ${roomId}:`, content.body);

    try {
      // client.sendEvent 会自动处理加密（如果房间开启了 E2EE）
      const response = await client.sendEvent(roomId, eventType, content, txnId);
      res.json(response);
    } catch (err: any) {
      console.error("[Proxy] 发送消息失败:", err);
      res.status(500).json({ error: err.message });
    }
  }
);

// 拦截获取已加入房间的请求
app.get(["/_matrix/client/r0/joined_rooms", "/_matrix/client/v3/joined_rooms"], (req, res) => {
  const rooms = client.getRooms().map((r) => r.roomId);
  res.json({ joined_rooms: rooms });
});

// 拦截 whoami 请求
app.get(["/_matrix/client/r0/account/whoami", "/_matrix/client/v3/account/whoami"], (req, res) => {
  res.json({ user_id: USER_ID });
});

// 拦截已读回执请求 (忽略)
app.post(
  [
    "/_matrix/client/r0/rooms/:roomId/receipt/:receiptType/:eventId",
    "/_matrix/client/v3/rooms/:roomId/receipt/:receiptType/:eventId",
  ],
  (req, res) => {
    res.json({});
  }
);

// 拦截正在输入状态请求
app.put(
  ["/_matrix/client/r0/rooms/:roomId/typing/:userId", "/_matrix/client/v3/rooms/:roomId/typing/:userId"],
  async (req, res) => {
    const { roomId } = req.params;
    const typing = req.body.typing;
    try {
      await client.sendTyping(roomId, typing, req.body.timeout || 30000);
      res.json({});
    } catch (err) {
      res.json({}); // 忽略错误
    }
  }
);

// 兜底路由：打印未处理的请求，方便调试
app.use((req, res) => {
  console.log(`[Proxy] 未处理的请求: ${req.method} ${req.originalUrl}`);
  res.status(404).json({ errcode: "M_UNRECOGNIZED", error: "Unrecognized request" });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`[Proxy] 本地 E2EE 代理服务器已启动，监听端口: ${PORT}`);
});
