import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import { Server } from "socket.io";
import { createServer } from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { Bridge } from "./src/plugin/Bridge";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = 3000;
const CONFIG_DIR = path.join(__dirname, "config");
const CONFIG_FILE = path.join(CONFIG_DIR, "matrix_config.md");

// Ensure config directory exists
if (!fs.existsSync(CONFIG_DIR)) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true });
}

// --- Config Helpers ---
function saveConfig(config: any) {
  const content = `# Matrix Configuration\n\n\`\`\`json\n${JSON.stringify(config, null, 2)}\n\`\`\``;
  fs.writeFileSync(CONFIG_FILE, content, "utf8");
}

function loadConfig() {
  if (!fs.existsSync(CONFIG_FILE)) return null;
  const match = fs.readFileSync(CONFIG_FILE, "utf8").match(/```json\n([\s\S]*?)\n```/);
  return match ? JSON.parse(match[1]) : null;
}

// Detect if running as standalone server or imported as a plugin
// This prevents port collisions and missing dependency errors when OpenClaw loads the plugin
const isMainModule = import.meta.url.startsWith('file:') && process.argv[1] === __filename;

let bridgeInstance: Bridge | null = null;

if (isMainModule) {
  const app = express();
  const httpServer = createServer(app);
  const io = new Server(httpServer, { cors: { origin: "*" } });
  bridgeInstance = new Bridge();

  // Wire Bridge events to Socket.io for standalone frontend
  bridgeInstance.on("matrix_message", (data) => {
    io.emit("matrix_message", data);
  });

  io.on("connection", (socket) => {
    console.log("Bridge: Standalone frontend connected");
    socket.on("openclaw_update", (data: { update: string }) => bridgeInstance?.sendNotice(data.update));
    socket.on("openclaw_typing", (data: { isTyping: boolean }) => bridgeInstance?.setTyping(data.isTyping));
    socket.on("openclaw_response", (data: { response: string }) => bridgeInstance?.sendToMatrix(data.response));
  });

  app.use(cors());
  app.use(express.json());

  // --- API ---
  app.get("/api/matrix/config", (req, res) => res.json(loadConfig() || {}));
  app.get("/api/matrix/status", (req, res) => res.json({ connected: bridgeInstance?.isMatrixConnected() }));
  app.post("/api/matrix/connect", async (req, res) => {
    try {
      await bridgeInstance?.connectMatrix(req.body);
      saveConfig(req.body);
      res.json({ status: "connected" });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  app.post("/api/matrix/create-room", async (req, res) => {
    const { userId } = req.body;
    try {
      const roomId = await bridgeInstance?.createPrivateChat(userId);
      res.json({ roomId });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // --- Vite & Standalone Server ---
  async function setupVite() {
    if (process.env.NODE_ENV !== "production") {
      const { createServer: createViteServer } = await import("vite");
      const vite = await createViteServer({ server: { middlewareMode: true }, appType: "spa" });
      app.use(vite.middlewares);
    } else {
      app.use(express.static("dist"));
    }

    httpServer.listen(PORT, "0.0.0.0", async () => {
      console.log(`Server running on http://localhost:${PORT}`);
      const config = loadConfig();
      if (config?.accessToken) {
        console.log("Auto-connecting Matrix...");
        try { await bridgeInstance?.connectMatrix(config); } catch (e) { console.error(e); }
      }
    });
  }

  setupVite();
}

// Export for OpenClaw plugin system
export default class OpenClawMatrixPlugin {
  private bridge: Bridge;
  
  constructor(private openclawContext: any) {
    this.bridge = new Bridge();
    
    // 1. Matrix -> OpenClaw (Receive all messages including / commands)
    this.bridge.on("matrix_message", async ({ sender, body }) => {
      console.log(`[Matrix -> OpenClaw] ${sender}: ${body}`);
      // Try standard OpenClaw plugin API patterns to inject the message
      if (this.openclawContext?.emit) {
        this.openclawContext.emit("message", { platform: "matrix", sender, text: body });
      } else if (this.openclawContext?.onMessage) {
        this.openclawContext.onMessage(body, sender, "matrix");
      } else {
        console.warn("[Matrix Plugin] openclawContext does not have a recognized message receiver.");
      }
    });

    // 2. OpenClaw -> Matrix (Send messages, typing, updates)
    if (this.openclawContext?.on) {
      // Listen for text responses
      this.openclawContext.on("send_message", (data: any) => {
        const text = typeof data === "string" ? data : data.text || data.response;
        if (text) this.bridge.sendToMatrix(text);
      });

      // Listen for typing status
      this.openclawContext.on("typing", (data: any) => {
        const isTyping = typeof data === "boolean" ? data : data.isTyping;
        this.bridge.setTyping(!!isTyping);
      });

      // Listen for system updates/notices
      this.openclawContext.on("system_update", (data: any) => {
        const text = typeof data === "string" ? data : data.update || data.text;
        if (text) this.bridge.sendNotice(text);
      });
    }
  }

  async start() {
    console.log("Matrix Plugin started by OpenClaw");
    const config = loadConfig();
    if (config?.accessToken) {
      console.log("Matrix config found, connecting...");
      try {
        await this.bridge.connectMatrix(config);
        console.log("Matrix connected successfully in OpenClaw.");
      } catch (e) {
        console.error("Matrix connection failed:", e);
      }
    } else {
      console.log("Matrix config not found. Please configure via UI.");
    }
  }

  async stop() {
    console.log("Matrix Plugin stopped by OpenClaw");
    this.bridge.stop();
  }
}
