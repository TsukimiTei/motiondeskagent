import { useState, useCallback, useEffect, useMemo } from 'react';
import { VideoPlayer } from './components/VideoPlayer';
import { ChatHistory } from './components/ChatHistory';
import { InputBox } from './components/InputBox';
import { useStateMachine } from './hooks/useStateMachine';
import { useConfig } from './hooks/useConfig';
import { useChat } from './hooks/useChat';
import { bridge } from './bridge';
import { stateMachine } from './stateMachine';

export function App() {
  const { state, dispatch, isInteractive } = useStateMachine();
  const { config, updateConfig } = useConfig();
  const { messages, isStreaming, sendMessage, clearHistory } = useChat();

  // 角色位置和大小（可通过设置窗口实时调整）
  const [layout, setLayout] = useState({
    characterX: 50,   // 百分比
    characterY: 8,    // 百分比
    characterWidth: 400,
    characterHeight: 400,
  });

  // 从 config 初始化 layout
  useEffect(() => {
    setLayout({
      characterX: (config as any).characterX ?? 50,
      characterY: (config as any).characterY ?? 8,
      characterWidth: (config as any).characterWidth ?? 400,
      characterHeight: (config as any).characterHeight ?? 400,
    });
  }, [config]);

  // 从 config 提取每个状态的视频路径（新格式：单个 clip 对象）
  const clips = useMemo(() => {
    const map: Record<string, string[]> = {};
    for (const [name, stateConfig] of Object.entries(config.states)) {
      const clip = (stateConfig as any).clip;
      if (clip && clip.path) {
        map[name] = [clip.path];
      } else if (stateConfig.clips && stateConfig.clips.length > 0) {
        // 兼容旧格式
        map[name] = stateConfig.clips.map((c) =>
          typeof c === 'string' ? c : c.path
        );
      } else {
        map[name] = [];
      }
    }
    return map;
  }, [config.states]);

  const loopStates = useMemo(() => {
    const set = new Set<string>();
    for (const [name, stateConfig] of Object.entries(config.states)) {
      if (stateConfig.loop) set.add(name);
    }
    return set;
  }, [config.states]);

  const handleClipEnd = useCallback(() => {
    dispatch('TRANSITION_DONE');
  }, [dispatch]);

  // 监听来自 Swift 的事件
  useEffect(() => {
    const unsubActivate = bridge.on('hotkeyActivate', () => {
      const current = stateMachine.getState();
      if (current === 'idle') {
        dispatch('HOTKEY_ACTIVATE');
        // transition-in 视频正常播放，输入框同时出现
      } else if (current === 'transition-in' || stateMachine.isInteractive()) {
        dispatch('HOTKEY_DEACTIVATE');
      }
    });

    const unsubDeactivate = bridge.on('hotkeyDeactivate', () => {
      dispatch('HOTKEY_DEACTIVATE');
    });

    const unsubLayout = bridge.on('updateLayout', (payload: any) => {
      setLayout((prev) => ({ ...prev, ...payload }));
    });

    const unsubDisplay = bridge.on('updateDisplay', (payload: any) => {
      if (payload.chromakeyThreshold !== undefined || payload.chromakeySmoothness !== undefined) {
        updateConfig(payload);
      }
    });

    // 交互模式切换背景透明度
    const unsubTransparent = bridge.on('setTransparent', (payload: { transparent: boolean }) => {
      document.body.style.background = payload.transparent ? 'transparent' : '#000';
      document.documentElement.style.background = payload.transparent ? 'transparent' : '#000';
    });

    return () => {
      unsubActivate();
      unsubDeactivate();
      unsubTransparent();
      unsubLayout();
      unsubDisplay();
    };
  }, [dispatch, updateConfig]);

  // 只有没有视频的 transition 才跳过（有视频的等 onClipEnd 自然触发）
  useEffect(() => {
    if (state === 'transition-in' && (!clips[state] || clips[state].length === 0)) {
      const timer = setTimeout(() => dispatch('TRANSITION_DONE'), 300);
      return () => clearTimeout(timer);
    }
    if (state === 'transition-out' && (!clips[state] || clips[state].length === 0)) {
      const timer = setTimeout(() => dispatch('TRANSITION_DONE'), 4000);
      return () => clearTimeout(timer);
    }
  }, [state, clips, dispatch]);

  // 角色层动态样式
  const characterStyle: React.CSSProperties = {
    position: 'absolute',
    left: `${layout.characterX}%`,
    top: `${layout.characterY}%`,
    transform: 'translateX(-50%)',
    zIndex: 1,
  };

  const canvasStyle = {
    width: layout.characterWidth,
    height: layout.characterHeight,
  };

  return (
    <div className="app">
      <div className="character-layer" style={characterStyle}>
        <VideoPlayer
          state={state}
          clips={clips}
          loopStates={loopStates}
          chromakeyThreshold={config.chromakeyThreshold}
          chromakeySmoothness={config.chromakeySmoothness}
          onClipEnd={handleClipEnd}
          canvasWidth={layout.characterWidth}
          canvasHeight={layout.characterHeight}
        />
      </div>

      <div className="state-indicator">{state}</div>

      <div className={`interaction-layer ${isInteractive || state === 'transition-in' ? 'visible' : ''}`}>
        <ChatHistory
          messages={messages}
          isStreaming={isStreaming}
          visible={isInteractive}
          onClear={clearHistory}
        />
        <InputBox
          onSend={sendMessage}
          disabled={state === 'thinking' || isStreaming || state === 'transition-in'}
          visible={isInteractive || state === 'transition-in'}
        />
      </div>
    </div>
  );
}
