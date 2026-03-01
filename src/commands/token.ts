import { config } from "../config.js";
import { logger } from "../utils/logger.js";

export const tokenCommand = {
  set: async (roomId: string, token: string, sendMessage: (roomId: string, msg: string) => Promise<any>) => {
    config.setReviveToken(token);
    logger.info(`Token 已设置: ${token.slice(0, 2)}...`);
    await sendMessage(roomId, "✅ Token 设置成功！");
  },
  
  show: async (roomId: string, sendMessage: (roomId: string, msg: string) => Promise<any>) => {
    const token = config.getReviveToken();
    if (token) {
      const masked = `${token.slice(0, 2)}****${token.slice(-2)}`;
      await sendMessage(roomId, `🔑 当前 Token: ${masked}`);
    } else {
      await sendMessage(roomId, "⚠️ 未设置 Token。");
    }
  },
  
  remove: async (roomId: string, sendMessage: (roomId: string, msg: string) => Promise<any>) => {
    config.removeReviveToken();
    logger.info("Token 已删除");
    await sendMessage(roomId, "✅ Token 已删除。");
  }
};
