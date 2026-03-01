import * as sdk from "matrix-js-sdk";
import { LocalStorage } from "node-localstorage";
import fs from "fs";
import { config } from "../config.js";
import { logger } from "../utils/logger.js";
import { EventEmitter } from "events";
import { progressState } from "../progress/state.js";
import { reviveCommand } from "../commands/revive.js";
import { tokenCommand } from "../commands/token.js";

export class MatrixClientWrapper {
  private client: sdk.MatrixClient;
  private syncEmitter = new EventEmitter();
  private nextBatchToken = Date.now();
  private unreadEvents: any[] = [];
  private proxyStartTime = Date.now();
  private isInitialized = false;

  constructor() {
    if (!fs.existsSync(config.storagePath)) {
      fs.mkdirSync(config.storagePath, { recursive: true });
    }
    const localStorage = new LocalStorage(config.storagePath);
    const cryptoStore = new sdk.LocalStorageCryptoStore(localStorage);

    this.client = sdk.createClient({
      baseUrl: config.homeserver,
      accessToken: config.accessToken,
      userId: config.userId,
      deviceId: config.deviceId,
      cryptoStore: cryptoStore,
      store: new sdk.MemoryStore(),
    });

    this.setupListeners();
  }

  private setupListeners() {
    this.client.on(sdk.ClientEvent.Sync, (state: string) => {
      if (state === "PREPARED") {
        logger.info("Matrix 客户端同步完成，已准备就绪！");
        this.isInitialized = true;
      }
    });

    this.client.on(sdk.RoomEvent.Timeline, async (event: any, room: any, toStartOfTimeline: boolean | undefined) => {
      if (toStartOfTimeline) return;

      if (event.getType() === "m.room.message") {
        const sender = event.getSender();
        if (sender === config.userId) return;

        // 过时消息过滤
        if (event.getTs() < this.proxyStartTime) {
          return;
        }

        const content = event.getContent();
        if (content.msgtype !== "m.text") return;

        const body = content.body?.trim();
        if (!body) return;

        const roomId = room?.roomId;
        logger.info(`收到新消息 [${roomId}] ${sender}: ${body}`);

        // --- 命令拦截逻辑 ---
        const parts = body.split(/\s+/);

        // 1. 拦截 /progress 命令
        if (body.startsWith("/progress ")) {
          const subCmd = parts[1]; // on / off
          if (subCmd === "on") {
            // 转换为 /verbose on 并发送给 OpenClaw
            this.injectUserMessage(roomId, "/verbose on", sender);
            progressState.enable();
            await this.sendMessage(roomId, "✅ 进度条模式已开启");
          } else if (subCmd === "off") {
            // 转换为 /verbose off 并发送给 OpenClaw
            this.injectUserMessage(roomId, "/verbose off", sender);
            progressState.disable();
            await this.sendMessage(roomId, "⚪ 进度条模式已关闭");
          }
          return; // 拦截，不转发原始消息
        }

        // 2. /verbose 命令不拦截，直接转发
        if (body.startsWith("/verbose ")) {
          // 直接进入转发逻辑
        } else if (body.startsWith("openclaw ")) {
          // 3. 拦截插件原生命令
          const cmd = parts[1];
          try {
            if (cmd === "revive") {
              const subCmd = parts[2];
              if (subCmd === "token") {
                const action = parts[3];
                if (action === "set") {
                  const token = parts[4];
                  if (!token) {
                    await this.sendMessage(roomId, "❌ 请提供 Token: openclaw revive token set <TOKEN>");
                  } else {
                    await tokenCommand.set(roomId, token, this.sendMessage.bind(this));
                  }
                } else if (action === "show") {
                  await tokenCommand.show(roomId, this.sendMessage.bind(this));
                } else if (action === "remove") {
                  await tokenCommand.remove(roomId, this.sendMessage.bind(this));
                } else {
                  await this.sendMessage(roomId, "❓ 未知 token 命令。可用: set, show, remove");
                }
              } else {
                const token = subCmd;
                if (!token) {
                  await this.sendMessage(roomId, "❌ 请提供 Token: openclaw revive <TOKEN>");
                } else {
                  await reviveCommand.execute(roomId, token, this.sendMessage.bind(this));
                }
              }
              return; // 拦截，不转发给 OpenClaw
            }
          } catch (err: any) {
            logger.error(`执行插件命令失败: ${err.message}`);
            await this.sendMessage(roomId, `❌ 执行失败: ${err.message}`);
            return;
          }
        }

        // --- 转发逻辑 ---
        const decryptedEvent = {
          ...event.event,
          type: "m.room.message",
          content: event.getContent(),
        };

        this.unreadEvents.push({ roomId, event: decryptedEvent });
        this.syncEmitter.emit("new_event");
      }
    });
  }

  public async start() {
    try {
      if ((this.client as any).initRustCrypto) {
        await (this.client as any).initRustCrypto({ useIndexedDB: false });
        logger.info("Rust E2EE 加密模块初始化成功");
      } else if ((this.client as any).initCrypto) {
        await (this.client as any).initCrypto();
      }
      await this.client.startClient({ initialSyncLimit: 1 });
    } catch (err) {
      logger.error("启动客户端失败:", err);
    }
  }

  public getClient() {
    return this.client;
  }

  public getSyncEmitter() {
    return this.syncEmitter;
  }

  public getUnreadEvents() {
    return this.unreadEvents;
  }

  public clearUnreadEvents() {
    this.unreadEvents = [];
  }

  public injectUserMessage(roomId: string, body: string, sender: string) {
    const event = {
      type: "m.room.message",
      room_id: roomId,
      sender: sender,
      content: {
        msgtype: "m.text",
        body: body,
      },
      origin_server_ts: Date.now(),
      event_id: `$injected_${Date.now()}`,
    };
    this.unreadEvents.push({ roomId, event });
    this.syncEmitter.emit("new_event");
  }

  public getNextBatchToken() {
    return this.nextBatchToken;
  }

  public incrementNextBatchToken() {
    this.nextBatchToken++;
  }

  public async sendMessage(roomId: string, message: string) {
    return await this.client.sendTextMessage(roomId, message);
  }

  public async editMessage(roomId: string, eventId: string, newContent: string) {
    return await (this.client as any).sendEvent(
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

  public isReady() {
    return this.isInitialized;
  }
}

export const matrixClient = new MatrixClientWrapper();
