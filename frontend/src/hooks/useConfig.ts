import { useState, useEffect, useCallback } from 'react';
import { bridge } from '../bridge';

export type ClipConfig = {
  path: string;
  loopMode: 'loop' | 'pingpong';
};

export type StateConfig = {
  label: string;
  loop: boolean;
  clips: (string | ClipConfig)[];
};

export type AppConfig = {
  states: Record<string, StateConfig>;
  transitions: Record<string, string[]>;
  chromakeyThreshold: number;
  chromakeySmoothness: number;
  hotkey: string;
};

const defaultConfig: AppConfig = {
  states: {
    idle: { label: '待机', loop: true, clips: [] },
    'transition-in': { label: '唤起过渡', loop: false, clips: [] },
    listening: { label: '等待输入', loop: true, clips: [] },
    thinking: { label: '思考中', loop: true, clips: [] },
    speaking: { label: '回复中', loop: true, clips: [] },
    'transition-out': { label: '收起过渡', loop: false, clips: [] },
  },
  transitions: {
    idle: ['transition-in'],
    'transition-in': ['listening'],
    listening: ['thinking', 'transition-out'],
    thinking: ['speaking'],
    speaking: ['listening'],
    'transition-out': ['idle'],
  },
  chromakeyThreshold: 0.3,
  chromakeySmoothness: 0.1,
  hotkey: 'double-cmd',
};

export function useConfig() {
  const [config, setConfig] = useState<AppConfig>(defaultConfig);

  useEffect(() => {
    // 从 Swift 请求配置
    bridge.send('getConfig');
    const unsub = bridge.on('config', (payload: AppConfig) => {
      setConfig(payload);
    });
    return unsub;
  }, []);

  const updateConfig = useCallback((updates: Partial<AppConfig>) => {
    setConfig((prev) => {
      const next = { ...prev, ...updates };
      bridge.send('saveConfig', next);
      return next;
    });
  }, []);

  const updateState = useCallback(
    (stateName: string, stateConfig: StateConfig) => {
      setConfig((prev) => {
        const next = {
          ...prev,
          states: { ...prev.states, [stateName]: stateConfig },
        };
        bridge.send('saveConfig', next);
        return next;
      });
    },
    []
  );

  const addState = useCallback((name: string, config: StateConfig) => {
    updateState(name, config);
  }, [updateState]);

  const removeState = useCallback((name: string) => {
    setConfig((prev) => {
      const nextStates = { ...prev.states };
      delete nextStates[name];
      const nextTransitions = { ...prev.transitions };
      delete nextTransitions[name];
      // 同时清理其他状态中的引用
      for (const key of Object.keys(nextTransitions)) {
        nextTransitions[key] = nextTransitions[key].filter((t) => t !== name);
      }
      const next = { ...prev, states: nextStates, transitions: nextTransitions };
      bridge.send('saveConfig', next);
      return next;
    });
  }, []);

  return { config, updateConfig, updateState, addState, removeState };
}
