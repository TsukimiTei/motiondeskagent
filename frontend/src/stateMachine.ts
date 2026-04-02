/**
 * 角色状态机
 *
 * 状态流转：
 * idle → transition-in → listening ⇄ thinking → speaking → listening
 *                         listening → transition-out → idle
 */

export type CharacterState =
  | 'idle'
  | 'transition-in'
  | 'listening'
  | 'thinking'
  | 'speaking'
  | 'transition-out';

export type StateTransitionEvent =
  | 'HOTKEY_ACTIVATE'    // 用户按快捷键唤起
  | 'TRANSITION_DONE'    // 过渡视频播完
  | 'USER_SEND'          // 用户发送消息
  | 'FIRST_TOKEN'        // 收到 Claude 首个 token
  | 'REPLY_DONE'         // 回复完毕
  | 'HOTKEY_DEACTIVATE'  // 用户按快捷键收起 / Esc
  | 'RESET';             // 重置到 idle

const transitions: Record<CharacterState, Partial<Record<StateTransitionEvent, CharacterState>>> = {
  'idle': {
    'HOTKEY_ACTIVATE': 'transition-in',
  },
  'transition-in': {
    'TRANSITION_DONE': 'listening',
  },
  'listening': {
    'USER_SEND': 'thinking',
    'HOTKEY_DEACTIVATE': 'transition-out',
  },
  'thinking': {
    'FIRST_TOKEN': 'speaking',
    'HOTKEY_DEACTIVATE': 'transition-out',
  },
  'speaking': {
    'REPLY_DONE': 'listening',
    'HOTKEY_DEACTIVATE': 'transition-out',
  },
  'transition-out': {
    'TRANSITION_DONE': 'idle',
  },
};

export type StateChangeListener = (newState: CharacterState, oldState: CharacterState) => void;

export class StateMachine {
  private state: CharacterState = 'idle';
  private listeners: StateChangeListener[] = [];

  getState(): CharacterState {
    return this.state;
  }

  dispatch(event: StateTransitionEvent): boolean {
    const possibleTransitions = transitions[this.state];
    const nextState = possibleTransitions?.[event];

    if (nextState) {
      const oldState = this.state;
      this.state = nextState;
      this.listeners.forEach((l) => l(nextState, oldState));
      return true;
    }

    if (event === 'RESET') {
      const oldState = this.state;
      this.state = 'idle';
      this.listeners.forEach((l) => l('idle', oldState));
      return true;
    }

    console.warn(`[StateMachine] Invalid transition: ${this.state} + ${event}`);
    return false;
  }

  onStateChange(listener: StateChangeListener): () => void {
    this.listeners.push(listener);
    return () => {
      const idx = this.listeners.indexOf(listener);
      if (idx >= 0) this.listeners.splice(idx, 1);
    };
  }

  /** 判断当前是否处于交互模式 */
  isInteractive(): boolean {
    return ['listening', 'thinking', 'speaking'].includes(this.state);
  }
}

export const stateMachine = new StateMachine();
