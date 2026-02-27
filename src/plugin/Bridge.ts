import { EventEmitter } from "events";
import { MatrixClient, MatrixConfig } from "./MatrixClient";

export class Bridge extends EventEmitter {
  private matrix: MatrixClient | null = null;

  constructor() {
    super();
  }

  async connectMatrix(config: MatrixConfig) {
    if (this.matrix) this.matrix.stop();
    
    this.matrix = new MatrixClient(config);
    await this.matrix.start((sender, body) => {
      // Forward all messages (including commands) to OpenClaw without filtering
      this.emit("matrix_message", { sender, body });
    });
  }

  isMatrixConnected() {
    return !!this.matrix;
  }

  async createPrivateChat(userId: string) {
    if (!this.matrix) throw new Error("Matrix not connected");
    return await this.matrix.createPrivateRoom(userId);
  }

  sendToMatrix(text: string) {
    this.matrix?.sendMessage(text);
    this.matrix?.sendTyping(false);
  }

  sendNotice(text: string) {
    this.matrix?.sendMessage(`[OpenClaw Operation]: ${text}`, "m.notice");
  }

  setTyping(isTyping: boolean) {
    this.matrix?.sendTyping(isTyping);
  }

  stop() {
    this.matrix?.stop();
  }
}
