import { useState, useCallback, useRef } from 'react';
import { AppConfig, StateConfig } from '../hooks/useConfig';
import { bridge } from '../bridge';

type Props = {
  visible: boolean;
  onClose: () => void;
  config: AppConfig;
  onUpdateConfig: (updates: Partial<AppConfig>) => void;
  onUpdateState: (name: string, state: StateConfig) => void;
  onAddState: (name: string, state: StateConfig) => void;
  onRemoveState: (name: string) => void;
};

type Tab = 'states' | 'hotkey' | 'display';

export function SettingsPanel({
  visible,
  onClose,
  config,
  onUpdateConfig,
  onUpdateState,
  onAddState,
  onRemoveState,
}: Props) {
  const [tab, setTab] = useState<Tab>('states');
  const [newStateName, setNewStateName] = useState('');
  const [newStateLabel, setNewStateLabel] = useState('');
  const [recordingHotkey, setRecordingHotkey] = useState(false);
  const [previewingState, setPreviewingState] = useState<string | null>(null);
  const previewVideoRef = useRef<HTMLVideoElement>(null);

  if (!visible) return null;

  const handleAddState = () => {
    if (!newStateName.trim()) return;
    onAddState(newStateName.trim(), {
      label: newStateLabel.trim() || newStateName.trim(),
      loop: true,
      clips: [],
    });
    setNewStateName('');
    setNewStateLabel('');
  };

  const handleAddClip = (stateName: string) => {
    bridge.send('pickVideoFile', { stateName });
  };

  const handleRemoveClip = (stateName: string, clipIndex: number) => {
    const state = config.states[stateName];
    const newClips = state.clips.filter((_, i) => i !== clipIndex);
    onUpdateState(stateName, { ...state, clips: newClips });
  };

  const handlePreview = (clipPath: string) => {
    setPreviewingState(clipPath);
    setTimeout(() => {
      if (previewVideoRef.current) {
        previewVideoRef.current.src = clipPath;
        previewVideoRef.current.play().catch(() => {});
      }
    }, 0);
  };

  const handleHotkeyRecord = () => {
    setRecordingHotkey(true);
    bridge.send('startHotkeyRecording');
  };

  // 核心状态不可删除
  const coreStates = new Set([
    'idle', 'transition-in', 'listening',
    'thinking', 'speaking', 'transition-out',
  ]);

  return (
    <div className="settings-overlay" onClick={onClose}>
      <div className="settings-panel" onClick={(e) => e.stopPropagation()}>
        <div className="settings-header">
          <h2>设置</h2>
          <button className="settings-close" onClick={onClose}>✕</button>
        </div>

        <div className="settings-tabs">
          <button
            className={`tab ${tab === 'states' ? 'active' : ''}`}
            onClick={() => setTab('states')}
          >
            状态 & 视频
          </button>
          <button
            className={`tab ${tab === 'hotkey' ? 'active' : ''}`}
            onClick={() => setTab('hotkey')}
          >
            快捷键
          </button>
          <button
            className={`tab ${tab === 'display' ? 'active' : ''}`}
            onClick={() => setTab('display')}
          >
            显示
          </button>
        </div>

        <div className="settings-body">
          {tab === 'states' && (
            <div className="settings-states">
              {Object.entries(config.states).map(([name, state]) => (
                <div key={name} className="state-item">
                  <div className="state-header">
                    <span className="state-name">{name}</span>
                    <span className="state-label">{state.label}</span>
                    <label className="state-loop">
                      <input
                        type="checkbox"
                        checked={state.loop}
                        onChange={(e) =>
                          onUpdateState(name, { ...state, loop: e.target.checked })
                        }
                      />
                      循环
                    </label>
                    {!coreStates.has(name) && (
                      <button
                        className="state-delete"
                        onClick={() => onRemoveState(name)}
                      >
                        删除
                      </button>
                    )}
                  </div>
                  <div className="state-clips">
                    {state.clips.length === 0 && (
                      <span className="no-clips">暂无视频</span>
                    )}
                    {state.clips.map((clip, i) => {
                      const clipPath = typeof clip === 'string' ? clip : clip.path;
                      return (
                      <div key={i} className="clip-item">
                        <span className="clip-path" title={clipPath}>
                          {clipPath.split('/').pop()}
                        </span>
                        <button
                          className="clip-preview"
                          onClick={() => handlePreview(clipPath)}
                        >
                          ▶
                        </button>
                        <button
                          className="clip-remove"
                          onClick={() => handleRemoveClip(name, i)}
                        >
                          ✕
                        </button>
                      </div>
                      );
                    })}
                    <button
                      className="clip-add"
                      onClick={() => handleAddClip(name)}
                    >
                      + 添加视频
                    </button>
                  </div>
                </div>
              ))}

              <div className="add-state">
                <input
                  placeholder="状态名称 (英文)"
                  value={newStateName}
                  onChange={(e) => setNewStateName(e.target.value)}
                />
                <input
                  placeholder="显示标签"
                  value={newStateLabel}
                  onChange={(e) => setNewStateLabel(e.target.value)}
                />
                <button onClick={handleAddState}>+ 添加状态</button>
              </div>
            </div>
          )}

          {tab === 'hotkey' && (
            <div className="settings-hotkey">
              <div className="hotkey-current">
                <span>当前快捷键：</span>
                <span className="hotkey-display">
                  {config.hotkey === 'double-cmd' ? '双击 ⌘' : config.hotkey}
                </span>
              </div>
              <button
                className={`hotkey-record ${recordingHotkey ? 'recording' : ''}`}
                onClick={handleHotkeyRecord}
              >
                {recordingHotkey ? '按下新的快捷键...' : '修改快捷键'}
              </button>
              <p className="hotkey-hint">
                点击「修改快捷键」后按下你想要的组合键。支持双击 ⌘ 或任意组合键。
              </p>
            </div>
          )}

          {tab === 'display' && (
            <div className="settings-display">
              <div className="slider-group">
                <label>
                  Chromakey 阈值
                  <span className="slider-value">
                    {config.chromakeyThreshold.toFixed(2)}
                  </span>
                </label>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.01"
                  value={config.chromakeyThreshold}
                  onChange={(e) =>
                    onUpdateConfig({
                      chromakeyThreshold: parseFloat(e.target.value),
                    })
                  }
                />
              </div>
              <div className="slider-group">
                <label>
                  边缘平滑度
                  <span className="slider-value">
                    {config.chromakeySmoothness.toFixed(2)}
                  </span>
                </label>
                <input
                  type="range"
                  min="0"
                  max="0.5"
                  step="0.01"
                  value={config.chromakeySmoothness}
                  onChange={(e) =>
                    onUpdateConfig({
                      chromakeySmoothness: parseFloat(e.target.value),
                    })
                  }
                />
              </div>
            </div>
          )}
        </div>

        {/* 视频预览弹窗 */}
        {previewingState && (
          <div
            className="preview-overlay"
            onClick={() => setPreviewingState(null)}
          >
            <video
              ref={previewVideoRef}
              className="preview-video"
              controls
              onClick={(e) => e.stopPropagation()}
            />
          </div>
        )}
      </div>
    </div>
  );
}
