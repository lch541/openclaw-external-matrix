import * as sdk from "matrix-js-sdk";
import { matrixClient } from "../matrix/client.js";
import { reviveCommand } from "../commands/revive.js";
import { tokenCommand } from "../commands/token.js";
import { logger } from "../utils/logger.js";

export function setupCommandListener() {
  const client = matrixClient.getClient();

  client.on(sdk.RoomEvent.Timeline, async (event: any, room: any, toStartOfTimeline: boolean | undefined) => {
    if (toStartOfTimeline) return;
    if (event.getType() !== "m.room.message") return;
    
    const content = event.getContent();
    if (content.msgtype !== "m.text") return;
    
    const body = content.body?.trim();
    if (!body || !body.startsWith("openclaw ")) return;

    const roomId = room.roomId;
    const parts = body.split(/\s+/);
    const cmd = parts[1];
    const subCmd = parts[2];

    logger.info(`解析命令: ${body}`);

    try {
      if (cmd === "revive") {
        const subCmd = parts[2];
        
        if (subCmd === "token") {
          const action = parts[3];
          if (action === "set") {
            const token = parts[4];
            if (!token) {
              await matrixClient.sendMessage(roomId, "❌ 请提供 Token: openclaw revive token set <TOKEN>");
            } else {
              await tokenCommand.set(roomId, token);
            }
          } else if (action === "show") {
            await tokenCommand.show(roomId);
          } else if (action === "remove") {
            await tokenCommand.remove(roomId);
          } else {
            await matrixClient.sendMessage(roomId, "❓ 未知 token 命令。可用: set, show, remove");
          }
        } else {
          // 这里的 subCmd 实际上就是 token
          const token = subCmd;
          if (!token) {
            await matrixClient.sendMessage(roomId, "❌ 请提供 Token: openclaw revive <TOKEN>");
            return;
          }
          await reviveCommand.execute(roomId, token);
        }
      }
    } catch (err: any) {
      logger.error(`执行命令失败: ${err.message}`);
      await matrixClient.sendMessage(roomId, `❌ 执行失败: ${err.message}`);
    }
  });
}
