# OpenClaw Matrix Plugin

This plugin allows **OpenClaw** to communicate over the Matrix protocol. It features real-time typing indicators, a clean chat interface, and robust API token protection.

## 🚀 一键安装 (One-Click Installation)

You can install the plugin directly into your OpenClaw instance using a single command. 
**Please run this command in your OpenClaw root directory:**

```bash
curl -sSL https://raw.githubusercontent.com/lch541/matrix_plugin/main/install.sh | bash
```

The script will automatically:
1. Safely backup your `~/.openclaw/openclaw.json` configuration.
2. Download the plugin into `extensions/matrix-plugin`.
3. Install dependencies.
4. Prompt you for your Matrix credentials (Homeserver, User ID, Access Token, Room ID).
5. Safely register the plugin into your OpenClaw configuration without breaking JSON5 formatting.
6. Run `openclaw doctor --fix` and restart the gateway.

## 🗑️ 一键卸载与清理 (One-Click Uninstallation & Cleanup)

If you need to remove the plugin and restore your OpenClaw configuration to its previous state, run:

```bash
curl -sSL https://raw.githubusercontent.com/lch541/matrix_plugin/main/uninstall.sh | bash
```

The uninstallation script is highly robust:
1. **Perfect Restoration**: Restores the exact `openclaw.json` backup created during installation.
2. **Deep Cleanup**: Completely removes the plugin directory and any residual temporary files.
3. **Session Reset**: Clears OpenClaw's `sessions` cache to ensure no stuck or pending conversations remain, providing a completely clean slate for the next installation.

## 🛠 Features

- **Clean Chat Interface**: By default, the plugin only sends the "typing..." indicator and the final response. It strictly blocks internal OpenClaw status logs (e.g., "Thinking...", "Analyzing...") from cluttering your Matrix chat.
- **Verbose Mode**: If you want to see detailed operation statuses for long-running tasks, simply send `/verbose on` in the Matrix chat. Send `/verbose off` to return to the clean interface.
- **API Token Protection**: When OpenClaw reconnects to Matrix, the plugin strictly ignores all historical/offline messages. It only processes messages sent *after* the connection is fully established, preventing massive API token waste from processing old backlogs.
- **Typing Status**: Automatically sends "typing..." status to Matrix while OpenClaw is processing.
- **Persistent Config**: Stores configuration in `config/matrix_config.md`. The plugin will automatically reconnect using these credentials on startup.

## 🔑 Requirements

- A Matrix account (bot account recommended).
- A Matrix Access Token (can be obtained from Element settings or via API).
- Node.js 18+ environment.
