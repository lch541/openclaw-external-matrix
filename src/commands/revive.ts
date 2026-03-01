import { exec } from "child_process";
import { promisify } from "util";
import { config } from "../config.js";
import { logger } from "../utils/logger.js";
import path from "path";
import os from "os";

const execAsync = promisify(exec);

export const reviveCommand = {
  execute: async (roomId: string, token: string, sendMessage: (roomId: string, msg: string) => Promise<any>) => {
    const storedToken = config.getReviveToken();
    
    if (!storedToken) {
      await sendMessage(roomId, "⚠️ Revoke 功能未启用，请先设置 Token: openclaw revive token set <你的密码>");
      return;
    }
    
    if (token !== storedToken) {
      await sendMessage(roomId, "❌ Token 验证失败");
      return;
    }
    
    await sendMessage(roomId, "✅ 验证通过，正在触发回滚...");
    await sendMessage(roomId, "🔄 正在执行回滚...");
    
    const scriptPath = path.join(os.homedir(), ".openclaw/gardian", "openclaw-revive.sh");
    
    try {
      const { stdout, stderr } = await execAsync(`bash ${scriptPath}`);
      
      if (stderr) {
        logger.warn(`revive.sh 输出错误: ${stderr}`);
      }
      
      logger.info(`revive.sh 执行成功: ${stdout}`);
      await sendMessage(roomId, `✅ 回滚成功！\n${stdout}`);
    } catch (error: any) {
      logger.error(`执行 revive.sh 失败: ${error.message}`);
      await sendMessage(roomId, `❌ 回滚失败: ${error.message}`);
    }
  }
};
