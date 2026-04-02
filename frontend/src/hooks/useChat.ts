import { useState, useCallback, useEffect, useRef } from 'react';
import { bridge } from '../bridge';
import { stateMachine } from '../stateMachine';

export type ChatMessage = {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
};

export function useChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const gotFirstToken = useRef(false);

  useEffect(() => {
    bridge.send('loadChatHistory');

    const unsubHistory = bridge.on('chatHistory', (payload: ChatMessage[]) => {
      setMessages(payload);
    });

    // stream-json 的 assistant 事件包含完整文本（非增量），用 replace 模式
    const unsubReplace = bridge.on('claudeReplace', (payload: { text: string }) => {
      if (!gotFirstToken.current) {
        gotFirstToken.current = true;
        stateMachine.dispatch('FIRST_TOKEN');
      }
      setIsStreaming(true);
      setMessages((prev) => {
        const last = prev[prev.length - 1];
        if (last && last.role === 'assistant' && last.id === '__streaming__') {
          return [
            ...prev.slice(0, -1),
            { ...last, content: payload.text },
          ];
        }
        return [
          ...prev,
          {
            id: '__streaming__',
            role: 'assistant',
            content: payload.text,
            timestamp: Date.now(),
          },
        ];
      });
    });

    const unsubDone = bridge.on('claudeDone', () => {
      setIsStreaming(false);
      gotFirstToken.current = false;
      setMessages((prev) => {
        const last = prev[prev.length - 1];
        if (last && last.id === '__streaming__') {
          return [
            ...prev.slice(0, -1),
            { ...last, id: `msg-${Date.now()}` },
          ];
        }
        return prev;
      });
      stateMachine.dispatch('REPLY_DONE');
    });

    const unsubError = bridge.on('claudeError', (payload: { error: string }) => {
      setIsStreaming(false);
      gotFirstToken.current = false;
      setMessages((prev) => [
        ...prev.filter((m) => m.id !== '__streaming__'),
        {
          id: `err-${Date.now()}`,
          role: 'assistant',
          content: `⚠️ 错误: ${payload.error}`,
          timestamp: Date.now(),
        },
      ]);
      stateMachine.dispatch('REPLY_DONE');
    });

    return () => {
      unsubHistory();
      unsubReplace();
      unsubDone();
      unsubError();
    };
  }, []);

  const sendMessage = useCallback((content: string) => {
    const userMsg: ChatMessage = {
      id: `msg-${Date.now()}`,
      role: 'user',
      content,
      timestamp: Date.now(),
    };
    setMessages((prev) => [...prev, userMsg]);
    gotFirstToken.current = false;

    stateMachine.dispatch('USER_SEND');
    bridge.send('sendMessage', { content });
  }, []);

  const clearHistory = useCallback(() => {
    setMessages([]);
    bridge.send('clearChatHistory');
    bridge.send('resetClaudeSession');
  }, []);

  return { messages, isStreaming, sendMessage, clearHistory };
}
