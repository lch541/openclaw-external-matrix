import * as sdk from "matrix-js-sdk";

export interface MatrixConfig {
  homeserver: string;
  accessToken: string;
  userId: string;
  roomId: string;
}

export class MatrixClient {
  private client: sdk.MatrixClient | null = null;
  private startTime: number = Date.now();
  private isReady: boolean = false;

  constructor(private config: MatrixConfig) {}

  async start(onMessage: (sender: string, body: string) => void) {
    // 设置一个稍微靠后的启动时间，并标记为未就绪
    this.startTime = Date.now();
    this.isReady = false;
    
    this.client = sdk.createClient({
      baseUrl: this.config.homeserver,
      accessToken: this.config.accessToken,
      userId: this.config.userId,
    });

    // 监听同步状态，只有在首次同步完成后才开始处理消息
    this.client.on(sdk.ClientEvent.Sync, (state, prevState, res) => {
      if (state === "PREPARED") {
        console.log("[MatrixClient] Initial sync complete, ready to process new messages.");
        this.isReady = true;
        // 更新 startTime 为同步完成的时刻，彻底丢弃同步期间拉取到的历史消息
        this.startTime = Date.now();
      }
    });

    this.client.on(sdk.RoomEvent.Timeline, (event, room, toStartOfTimeline) => {
      // 如果是向后翻页拉取的历史记录，直接忽略
      if (toStartOfTimeline) return;
      
      // 如果客户端还没完成首次同步，忽略所有消息（这些都是历史消息）
      if (!this.isReady) return;
      
      if (event.getType() !== "m.room.message") return;
      if (event.getRoomId() !== this.config.roomId) return;
      if (event.getSender() === this.config.userId) return;

      // 终极防线：严格比较消息的服务器时间戳和插件的启动时间
      // 如果消息是在插件启动（或重连）之前发送的，坚决丢弃，防止浪费 API Token
      const eventTime = event.getTs();
      if (eventTime < this.startTime) {
        console.log(`[MatrixClient] Ignored old message from ${event.getSender()} (EventTime: ${eventTime}, StartTime: ${this.startTime})`);
        return;
      }

      const body = event.getContent().body;
      onMessage(event.getSender() || "unknown", body);
    });

    // initialSyncLimit 设为 0，告诉服务器我们不需要任何历史消息
    await this.client.startClient({ initialSyncLimit: 0 });
  }

  stop() {
    this.client?.stopClient();
  }

  async sendMessage(body: string, msgtype: string = "m.text", formattedBody?: string) {
    const content: any = {
      msgtype: msgtype as any,
      body,
    };
    if (formattedBody) {
      content.format = "org.matrix.custom.html";
      content.formatted_body = formattedBody;
    }
    return this.client?.sendMessage(this.config.roomId, content);
  }

  async sendTyping(isTyping: boolean) {
    return this.client?.sendTyping(this.config.roomId, isTyping, isTyping ? 30000 : 0);
  }

  async createPrivateRoom(userId: string) {
    if (!this.client) throw new Error("Matrix client not initialized");
    const response = await this.client.createRoom({
      invite: [userId],
      preset: "trusted_private_chat" as any,
      is_direct: true,
    });
    return response.room_id;
  }
}
