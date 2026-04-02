import { useRef, useEffect, useState } from 'react';
import { ChatBubble } from './ChatBubble';
import { ChatMessage } from '../hooks/useChat';

type Props = {
  messages: ChatMessage[];
  isStreaming: boolean;
  visible: boolean;
  onClear: () => void;
};

export function ChatHistory({ messages, isStreaming, visible, onClear }: Props) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [showFull, setShowFull] = useState(false);

  // 自动滚动到底部
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  if (!visible) return null;

  // 默认只显示最后一轮对话（最后一条用户消息 + 最后一条回复）
  const displayMessages = showFull
    ? messages
    : getLastRound(messages);

  return (
    <div className="chat-history">
      {messages.length > 2 && (
        <div className="chat-history-controls">
          <button
            className="history-toggle"
            onClick={() => setShowFull(!showFull)}
          >
            {showFull ? '只看最近' : `查看历史 (${messages.length} 条)`}
          </button>
          <button className="history-clear" onClick={onClear}>
            新对话
          </button>
        </div>
      )}
      <div className="chat-messages" ref={scrollRef}>
        {displayMessages.map((msg) => (
          <ChatBubble
            key={msg.id}
            content={msg.content}
            role={msg.role}
            isStreaming={isStreaming && msg.id === '__streaming__'}
          />
        ))}
      </div>
    </div>
  );
}

function getLastRound(messages: ChatMessage[]): ChatMessage[] {
  if (messages.length === 0) return [];
  const result: ChatMessage[] = [];

  // 从后往前找最后一条 assistant 消息
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'assistant') {
      result.unshift(messages[i]);
      // 往前找对应的 user 消息
      for (let j = i - 1; j >= 0; j--) {
        if (messages[j].role === 'user') {
          result.unshift(messages[j]);
          break;
        }
      }
      break;
    }
  }

  // 如果最后一条是 user（还没收到回复），也要显示
  if (result.length === 0 && messages.length > 0) {
    result.push(messages[messages.length - 1]);
  }

  return result;
}
