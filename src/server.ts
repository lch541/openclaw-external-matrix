import express from "express";
import cors from "cors";
import { config } from "./config.js";
import { logger } from "./utils/logger.js";
import { matrixClient } from "./matrix/client.js";
import matrixRoutes from "./routes/matrix.js";
import notifyRoutes from "./routes/notify.js";

const app = express();

app.use(cors());
app.use(express.json());

// 记录所有请求
app.use((req, res, next) => {
  logger.debug(`${req.method} ${req.originalUrl}`);
  next();
});

// 注册路由
// Matrix 代理路由 (支持 r0 和 v3)
app.use(["/_matrix/client/r0", "/_matrix/client/v3"], matrixRoutes);

// 新增功能路由
app.use("/api", notifyRoutes);

// 启动 Matrix 客户端
matrixClient.start().then(() => {
  logger.info("Matrix 客户端启动流程已发起");
});

// 兜底路由
app.use((req, res) => {
  logger.warn(`未处理的请求: ${req.method} ${req.originalUrl}`);
  res.status(404).json({ errcode: "M_UNRECOGNIZED", error: "Unrecognized request" });
});

app.listen(config.proxyPort, "0.0.0.0", () => {
  logger.info(`OpenClaw External Matrix 代理服务器已启动`);
  logger.info(`监听端口: ${config.proxyPort}`);
  logger.info(`通知接口: http://localhost:${config.proxyPort}/api/notify`);
});
