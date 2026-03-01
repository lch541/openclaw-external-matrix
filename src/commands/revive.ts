import { exec } from "child_process";
import { promisify } from "util";
import { config } from "../config.js";
import { logger } from "../utils/logger.js";
import { matrixClient } from "../matrix/client.js";
import path from "path";
import os from "os";

const execAsync = promisify(exec);

export const reviveCommand = {
  execute: async (roomId: string, token: string) => {
    const storedToken = config.getReviveToken();
    
    if (!storedToken) {
      await matrixClient.sendMessage(roomId, "⚠️ Revoke 功能未启用，请先设置 Token: openclaw token set <你的密码>");
      return;
    }
    
    if (token !== storedToken) {
      await matrixClient.sendMessage(roomId, "❌ Token 验证失败");
      return;
    }
    
    await matrixClient.sendMessage(roomId, "✅ 验证通过，正在触发回滚...");
    await matrixClient.sendMessage(roomId, "🔄 正在执行回滚...");
    
    const scriptPath = path.join(os.homedir(), ".openclaw/gardian", "openclaw-revive.sh");
    
    try {
      const { stdout, stderr } = await execAsync(`bash ${scriptPath}`);
      
      if (stderr) {
        logger.warn(`revive.sh 输出错误: ${stderr}`);
      }
      
      logger.info(`revive.sh 执行成功: ${stdout}`);
      await matrixClient.sendMessage(roomId, `✅ 回滚成功！\n${stdout}`);
    } catch (error: any) {
      logger.error(`执行 revive.sh 失败: ${error.message}`);
      await matrixClient.sendMessage(roomId, `❌ 回滚失败: ${error.message}`);
    }
  }
};
