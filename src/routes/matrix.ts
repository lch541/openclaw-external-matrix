import { Router } from "express";
import { matrixClient } from "../matrix/client.js";
import { config } from "../config.js";
import { logger } from "../utils/logger.js";
import { progressState } from "../progress/state.js";
import { formatProgressBar } from "../progress/bar.js";

const router = Router();

router.get(["/sync", "/v3/sync"], (req, res) => {
  const since = req.query.since as string;
  const timeout = parseInt(req.query.timeout as string) || 30000;
  const syncEmitter = matrixClient.getSyncEmitter();
  const unreadEvents = matrixClient.getUnreadEvents();

  const respond = () => {
    const response: any = {
      next_batch: matrixClient.getNextBatchToken().toString(),
      rooms: { join: {} },
    };

    if (unreadEvents.length > 0) {
      for (const { roomId, event } of unreadEvents) {
        if (!response.rooms.join[roomId]) {
          response.rooms.join[roomId] = { timeline: { events: [] } };
        }
        response.rooms.join[roomId].timeline.events.push(event);
      }
      matrixClient.incrementNextBatchToken();
      matrixClient.clearUnreadEvents();
    }

    res.json(response);
  };

  if (!since) {
    logger.info("OpenClaw 初始同步，仅返回 next_batch 以过滤历史消息。");
    return res.json({
      next_batch: matrixClient.getNextBatchToken().toString(),
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

router.put(["/rooms/:roomId/send/:eventType/:txnId", "/v3/rooms/:roomId/send/:eventType/:txnId"], async (req, res) => {
  const { roomId, eventType, txnId } = req.params;
  const content = req.body;
  const client = matrixClient.getClient();

  // 进度条逻辑
  if (progressState.isEnabled() && eventType === "m.room.message" && content.msgtype === "m.text") {
    const body = content.body || "";
    const { messageId: currentMessageId } = progressState.getCurrentMessage();

    // 启发式判断是否为中间过程日志
    const isLog = body.length < 200 && (
      body.includes("...") || 
      body.includes("读取") || 
      body.includes("分析") || 
      body.includes("搜索") || 
      body.includes("生成") ||
      body.includes("Reading") ||
      body.includes("Analyzing") ||
      body.includes("Searching") ||
      body.includes("Generating")
    );

    if (isLog) {
      const progressBar = formatProgressBar(body);
      if (!currentMessageId) {
        try {
          const response = await matrixClient.sendMessage(roomId, progressBar);
          progressState.setCurrentMessage(roomId, response.event_id);
          return res.json(response);
        } catch (err: any) {
          logger.error("发送进度条初始消息失败:", err);
        }
      } else {
        try {
          const response = await matrixClient.editMessage(roomId, currentMessageId, progressBar);
          return res.json(response);
        } catch (err: any) {
          logger.error("更新进度条失败:", err);
          // 如果编辑失败（例如消息被删），清除状态并回退到普通发送
          progressState.clearCurrentMessage();
        }
      }
    } else if (currentMessageId) {
      // 最终回复：替换进度条并清除状态
      try {
        const response = await matrixClient.editMessage(roomId, currentMessageId, body);
        progressState.clearCurrentMessage();
        return res.json(response);
      } catch (err: any) {
        logger.error("用最终回复替换进度条失败:", err);
        progressState.clearCurrentMessage();
      }
    }
  }

  try {
    const response = await client.sendEvent(roomId, eventType, content, txnId);
    res.json(response);
  } catch (err: any) {
    logger.error(`发送消息失败 [${roomId}]: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

router.get(["/joined_rooms", "/v3/joined_rooms"], (req, res) => {
  const client = matrixClient.getClient();
  const rooms = client.getRooms().map((r) => r.roomId);
  res.json({ joined_rooms: rooms });
});

router.get(["/account/whoami", "/v3/account/whoami"], (req, res) => {
  res.json({ user_id: config.userId });
});

router.post(["/rooms/:roomId/receipt/:receiptType/:eventId", "/v3/rooms/:roomId/receipt/:receiptType/:eventId"], (req, res) => {
  res.json({});
});

router.put(["/rooms/:roomId/typing/:userId", "/v3/rooms/:roomId/typing/:userId"], async (req, res) => {
  const { roomId } = req.params;
  const typing = req.body.typing;
  const client = matrixClient.getClient();
  try {
    await client.sendTyping(roomId, typing, req.body.timeout || 30000);
    res.json({});
  } catch (err) {
    res.json({});
  }
});

export default router;
