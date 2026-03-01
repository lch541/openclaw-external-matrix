interface ProgressState {
  enabled: boolean;
  currentMessageId: string | null;
  currentRoomId: string | null;
}

class ProgressStateManager {
  private state: ProgressState = {
    enabled: false,
    currentMessageId: null,
    currentRoomId: null,
  };

  enable() { this.state.enabled = true; }
  disable() { this.state.enabled = false; }
  isEnabled() { return this.state.enabled; }

  setCurrentMessage(roomId: string, messageId: string) {
    this.state.currentRoomId = roomId;
    this.state.currentMessageId = messageId;
  }

  clearCurrentMessage() {
    this.state.currentRoomId = null;
    this.state.currentMessageId = null;
  }

  getCurrentMessage() {
    return {
      roomId: this.state.currentRoomId,
      messageId: this.state.currentMessageId,
    };
  }
}

export const progressState = new ProgressStateManager();
