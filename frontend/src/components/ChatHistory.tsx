import { useRef, useEffect, useState } from 'react';
import { ChatBubble } from './ChatBubble';
import { ToolActivity } from './ToolActivity';
import type { ChatMessage } from '../hooks/useChat';

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

  // 默认只显示最后一轮对话（最后一条用户消息 + 后续所有回复/工具）
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
        {displayMessages.map((msg) => {
          // 工具消息用 ToolActivity 渲染
          if (msg.role === 'tool') {
            return <ToolActivity key={msg.id} message={msg} />;
          }
          // 系统消息（斜杠命令输出等）
          if (msg.role === 'system') {
            return (
              <div key={msg.id} className="chat-bubble system">
                <div className="bubble-content">{msg.content}</div>
              </div>
            );
          }
          // 普通聊天消息
          return (
            <ChatBubble
              key={msg.id}
              content={msg.content}
              role={msg.role as 'user' | 'assistant'}
              isStreaming={isStreaming && msg.id === '__streaming__'}
            />
          );
        })}
      </div>
    </div>
  );
}

function getLastRound(messages: ChatMessage[]): ChatMessage[] {
  if (messages.length === 0) return [];
  const result: ChatMessage[] = [];

  // 从后往前找最后一条 user 消息
  let lastUserIdx = -1;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'user') {
      lastUserIdx = i;
      break;
    }
  }

  if (lastUserIdx >= 0) {
    // 返回该 user 消息及其后的所有消息（assistant + tool + system）
    return messages.slice(lastUserIdx);
  }

  // 如果没有 user 消息，返回最后几条
  return messages.slice(-3);
}
