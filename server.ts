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

// 默认使用 3344 端口，避免与常用端口冲突
const PORT = parseInt(process.env.PROXY_PORT || "3344", 10);
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
const PROXY_START_TIME = Date.now();

client.on(sdk.ClientEvent.Sync, (state: string) => {
  if (state === "PREPARED") {
    console.log("[Proxy] Matrix 客户端同步完成，已准备就绪！");
  }
});

client.on(sdk.RoomEvent.Timeline, (event: any, room: any, toStartOfTimeline: boolean | undefined) => {
  if (toStartOfTimeline) return; 

  if (event.getType() === "m.room.message") {
    const sender = event.getSender();
    if (sender === USER_ID) return;

    // 过时消息过滤：忽略启动之前的历史消息
    if (event.getTs() < PROXY_START_TIME) {
      return;
    }

    console.log(`[Proxy] 收到新消息 [${room?.roomId}] ${sender}: ${event.getContent().body}`);

    const decryptedEvent = {
      ...event.event,
      type: "m.room.message",
      content: event.getContent(),
    };

    unreadEvents.push({ roomId: room?.roomId, event: decryptedEvent });
    syncEmitter.emit("new_event");
  }
});

async function startClient() {
  try {
    if ((client as any).initRustCrypto) {
      await (client as any).initRustCrypto({ useIndexedDB: false });
      console.log("[Proxy] Rust E2EE 加密模块初始化成功");
    } else if ((client as any).initCrypto) {
      await (client as any).initCrypto();
    }
    
    await client.startClient({ initialSyncLimit: 1 }); 
  } catch (err) {
    console.error("[Proxy] 启动客户端失败:", err);
  }
}
startClient();

// 4. 启动 Express 代理服务器
const app = express();
app.use(cors());
app.use(express.json());

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
      unreadEvents = []; 
    }

    res.json(response);
  };

  if (!since) {
    return res.json({
      next_batch: nextBatchToken.toString(),
      rooms: { join: {} },
    });
  }

  if (unreadEvents.length > 0 || timeout === 0) {
    respond();
  } else {
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

app.put(
  [
    "/_matrix/client/r0/rooms/:roomId/send/:eventType/:txnId",
    "/_matrix/client/v3/rooms/:roomId/send/:eventType/:txnId",
  ],
  async (req, res) => {
    const { roomId, eventType, txnId } = req.params;
    const content = req.body;

    try {
      const response = await client.sendEvent(roomId, eventType, content, txnId);
      res.json(response);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  }
);

app.get(["/_matrix/client/r0/joined_rooms", "/_matrix/client/v3/joined_rooms"], (req, res) => {
  const rooms = client.getRooms().map((r) => r.roomId);
  res.json({ joined_rooms: rooms });
});

app.get(["/_matrix/client/r0/account/whoami", "/_matrix/client/v3/account/whoami"], (req, res) => {
  res.json({ user_id: USER_ID });
});

app.post(
  [
    "/_matrix/client/r0/rooms/:roomId/receipt/:receiptType/:eventId",
    "/_matrix/client/v3/rooms/:roomId/receipt/:receiptType/:eventId",
  ],
  (req, res) => {
    res.json({});
  }
);

app.put(
  ["/_matrix/client/r0/rooms/:roomId/typing/:userId", "/_matrix/client/v3/rooms/:roomId/typing/:userId"],
  async (req, res) => {
    const { roomId } = req.params;
    const typing = req.body.typing;
    try {
      await client.sendTyping(roomId, typing, req.body.timeout || 30000);
      res.json({});
    } catch (err) {
      res.json({}); 
    }
  }
);

app.listen(PORT, "0.0.0.0", () => {
  console.log(`[Proxy] 本地 E2EE 代理服务器已启动，监听端口: ${PORT}`);
});
