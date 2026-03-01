import * as sdk from "matrix-js-sdk";
import { LocalStorage } from "node-localstorage";
import fs from "fs";
import { config } from "../config.js";
import { logger } from "../utils/logger.js";
import { EventEmitter } from "events";

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

    this.client.on(sdk.RoomEvent.Timeline, (event: any, room: any, toStartOfTimeline: boolean | undefined) => {
      if (toStartOfTimeline) return;

      if (event.getType() === "m.room.message") {
        const sender = event.getSender();
        if (sender === config.userId) return;

        // 过时消息过滤
        if (event.getTs() < this.proxyStartTime) {
          return;
        }

        logger.info(`收到新消息 [${room?.roomId}] ${sender}: ${event.getContent().body}`);

        const decryptedEvent = {
          ...event.event,
          type: "m.room.message",
          content: event.getContent(),
        };

        this.unreadEvents.push({ roomId: room?.roomId, event: decryptedEvent });
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

  public getNextBatchToken() {
    return this.nextBatchToken;
  }

  public incrementNextBatchToken() {
    this.nextBatchToken++;
  }

  public async sendMessage(roomId: string, message: string) {
    return await this.client.sendTextMessage(roomId, message);
  }

  public async editMessage(roomId: string, messageId: string, newContent: string) {
    return await (this.client as any).sendEvent(roomId, "m.room.message", {
      "m.new_content": {
        "msgtype": "m.text",
        "body": newContent,
      },
      "m.relates_to": {
        "event_id": messageId,
        "rel_type": "m.replace",
      },
      "msgtype": "m.text",
      "body": ` * ${newContent}`, // Fallback for clients that don't support edits
    });
  }

  public isReady() {
    return this.isInitialized;
  }
}

export const matrixClient = new MatrixClientWrapper();
