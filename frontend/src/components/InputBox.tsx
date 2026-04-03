import { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { getRegisteredCommands } from '../commands/commandRegistry';

type Props = {
  onSend: (message: string) => void;
  disabled?: boolean;
  visible?: boolean;
};

export function InputBox({ onSend, disabled, visible }: Props) {
  const [value, setValue] = useState('');
  const [isFocused, setIsFocused] = useState(false);
  const [showCommands, setShowCommands] = useState(false);
  const [selectedCmd, setSelectedCmd] = useState(0);
  const inputRef = useRef<HTMLDivElement>(null);

  const commands = useMemo(() => getRegisteredCommands(), []);

  // 过滤匹配的命令
  const filteredCommands = useMemo(() => {
    if (!value.startsWith('/')) return [];
    const prefix = value.slice(1).toLowerCase().split(/\s/)[0];
    if (value.includes(' ')) return []; // 已经开始输入参数，不再提示
    return commands.filter((c) => c.name.startsWith(prefix));
  }, [value, commands]);

  // 可见时自动聚焦
  useEffect(() => {
    if (visible && inputRef.current) {
      inputRef.current.focus();
      setIsFocused(true);
    }
  }, [visible]);

  // 更新命令提示显示状态
  useEffect(() => {
    setShowCommands(filteredCommands.length > 0 && value.startsWith('/'));
    setSelectedCmd(0);
  }, [filteredCommands, value]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      // 命令提示导航
      if (showCommands) {
        if (e.key === 'ArrowDown') {
          e.preventDefault();
          setSelectedCmd((prev) => Math.min(prev + 1, filteredCommands.length - 1));
          return;
        }
        if (e.key === 'ArrowUp') {
          e.preventDefault();
          setSelectedCmd((prev) => Math.max(prev - 1, 0));
          return;
        }
        if (e.key === 'Tab') {
          e.preventDefault();
          const cmd = filteredCommands[selectedCmd];
          if (cmd && inputRef.current) {
            inputRef.current.innerText = `/${cmd.name} `;
            setValue(`/${cmd.name} `);
            // 将光标移到末尾
            const range = document.createRange();
            range.selectNodeContents(inputRef.current);
            range.collapse(false);
            const sel = window.getSelection();
            sel?.removeAllRanges();
            sel?.addRange(range);
          }
          return;
        }
      }

      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        const text = inputRef.current?.innerText?.trim() || '';
        if (text && !disabled) {
          onSend(text);
          if (inputRef.current) inputRef.current.innerText = '';
          setValue('');
          setShowCommands(false);
        }
      }
      if (e.key === 'Escape') {
        if (showCommands) {
          setShowCommands(false);
          return;
        }
        (window as any).nativeBridge?.receive?.('hotkeyDeactivate', {});
      }
    },
    [disabled, onSend, showCommands, filteredCommands, selectedCmd]
  );

  const handleInput = useCallback(() => {
    setValue(inputRef.current?.innerText || '');
  }, []);

  if (!visible) return null;

  return (
    <div className={`caption-input ${isFocused ? 'focused' : ''} ${disabled ? 'disabled' : ''}`}>
      {/* 命令提示下拉 */}
      {showCommands && (
        <div className="command-suggestions">
          {filteredCommands.map((cmd, i) => (
            <div
              key={cmd.name}
              className={`command-item ${i === selectedCmd ? 'selected' : ''}`}
              onMouseDown={(e) => {
                e.preventDefault();
                if (inputRef.current) {
                  inputRef.current.innerText = `/${cmd.name} `;
                  setValue(`/${cmd.name} `);
                  inputRef.current.focus();
                }
                setShowCommands(false);
              }}
            >
              <span className="command-item-name">/{cmd.name}</span>
              <span className="command-item-desc">{cmd.description}</span>
            </div>
          ))}
        </div>
      )}

      <div className="caption-glow" />
      <div className="caption-line" />
      <div
        ref={inputRef}
        className="caption-text"
        contentEditable={!disabled}
        onKeyDown={handleKeyDown}
        onInput={handleInput}
        onFocus={() => setIsFocused(true)}
        onBlur={() => setIsFocused(false)}
        data-placeholder="说点什么... (输入 / 查看命令)"
        suppressContentEditableWarning
      />
      <div className="caption-hint">
        {disabled ? '思考中...' : 'Enter 发送 · Tab 补全 · Esc 退出'}
      </div>
    </div>
  );
}
