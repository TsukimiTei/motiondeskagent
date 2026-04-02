import { useState, useRef, useEffect, useCallback } from 'react';

type Props = {
  onSend: (message: string) => void;
  disabled?: boolean;
  visible?: boolean;
};

export function InputBox({ onSend, disabled, visible }: Props) {
  const [value, setValue] = useState('');
  const [isFocused, setIsFocused] = useState(false);
  const inputRef = useRef<HTMLDivElement>(null);

  // 可见时自动聚焦
  useEffect(() => {
    if (visible && inputRef.current) {
      inputRef.current.focus();
      setIsFocused(true);
    }
  }, [visible]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        const text = inputRef.current?.innerText?.trim() || '';
        if (text && !disabled) {
          onSend(text);
          if (inputRef.current) inputRef.current.innerText = '';
          setValue('');
        }
      }
      if (e.key === 'Escape') {
        (window as any).nativeBridge?.receive?.('hotkeyDeactivate', {});
      }
    },
    [disabled, onSend]
  );

  const handleInput = useCallback(() => {
    setValue(inputRef.current?.innerText || '');
  }, []);

  if (!visible) return null;

  return (
    <div className={`caption-input ${isFocused ? 'focused' : ''} ${disabled ? 'disabled' : ''}`}>
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
        data-placeholder="说点什么..."
        suppressContentEditableWarning
      />
      <div className="caption-hint">
        {disabled ? '思考中...' : 'Enter 发送 · Esc 退出'}
      </div>
    </div>
  );
}
