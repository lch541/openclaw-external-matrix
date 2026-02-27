# OpenClaw Matrix Plugin

This plugin allows **OpenClaw** to communicate over the Matrix protocol. It features end-to-end encryption (handled by the client), real-time typing indicators, and operation stream updates.

## 🚀 一键安装 (One-Click Installation)

You can install the plugin directly into your OpenClaw instance using a single command. 
**Please run this command in your OpenClaw root directory:**

```bash
curl -sSL https://raw.githubusercontent.com/lch541/matrix_plugin/main/install.sh | bash
```

The script will automatically:
1. Backup your OpenClaw `config.json`.
2. Download the plugin into `extensions/matrix-plugin`.
3. Install dependencies.
4. Prompt you for your Matrix credentials (Homeserver, User ID, Access Token, Room ID).
5. Restart OpenClaw to apply the changes.

## 🗑️ 一键卸载 (One-Click Uninstallation)

If you need to remove the plugin and restore your OpenClaw configuration to its previous state, run:

```bash
curl -sSL https://raw.githubusercontent.com/lch541/matrix_plugin/main/uninstall.sh | bash
```

## 🛠 Features

- **E2EE Support**: Uses `matrix-js-sdk` for secure communication.
- **Typing Status**: Automatically sends "typing..." status to Matrix while OpenClaw is processing.
- **Operation Updates**: Sends real-time "notices" to the Matrix room describing what OpenClaw is doing (e.g., "Analyzing context...", "Consulting knowledge base...").
- **Fresh Start**: Automatically discards any messages sent before the plugin was initialized to prevent processing old backlog.
- **Command System**: Supports Telegram-like bot commands (e.g., `/help`, `/status`, `/ping`, `/about`) for easy interaction and management directly from Matrix.
- **Persistent Config**: Stores configuration in `matrix_config.md`. The plugin will automatically reconnect using these credentials on startup, making it easy to recover from reboots or reinstalls.
- **WebSocket Bridge**: Uses Socket.io to bridge Matrix events to the OpenClaw frontend.

## 🔑 Requirements

- A Matrix account (bot account recommended).
- A Matrix Access Token (can be obtained from Element settings or via API).
- Node.js 18+ environment.
