import { useState, useCallback, useEffect, useRef } from 'react';
import { bridge } from '../bridge';
import { stateMachine } from '../stateMachine';
import { parseSlashCommand } from '../commands/commandParser';
import { executeCommand } from '../commands/commandRegistry';
import type {
  ChatMessage,
  SessionInfo,
  ToolStartPayload,
  ToolProgressPayload,
  ToolResultPayload,
  SessionInitPayload,
  DonePayload,
  ErrorPayload,
} from '../types/streamEvents';

export type { ChatMessage };

export function useChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [sessionInfo, setSessionInfo] = useState<SessionInfo | null>(null);
  const gotFirstToken = useRef(false);

  useEffect(() => {
    bridge.send('loadChatHistory');

    // ── 聊天历史加载 ──
    const unsubHistory = bridge.on('chatHistory', (payload: ChatMessage[]) => {
      setMessages(payload);
    });

    // ── 完整文本替换（来自 assistant 事件）──
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

    // ── 增量文本（来自 stream_event content_block_delta）──
    const unsubDelta = bridge.on('claudeTextDelta', (payload: { text: string }) => {
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
            { ...last, content: last.content + payload.text },
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

    // ── 工具开始 ──
    const unsubToolStart = bridge.on('claudeToolStart', (payload: ToolStartPayload) => {
      stateMachine.dispatch('TOOL_START');
      setMessages((prev) => [
        ...prev,
        {
          id: `tool-${payload.id || Date.now()}`,
          role: 'tool',
          content: `使用 ${payload.name}...`,
          timestamp: Date.now(),
          toolName: payload.name,
          toolId: payload.id,
          toolActive: true,
          toolElapsed: 0,
        },
      ]);
    });

    // ── 工具进度 ──
    const unsubToolProgress = bridge.on('claudeToolProgress', (payload: ToolProgressPayload) => {
      setMessages((prev) => {
        // 找到最后一个匹配的活跃工具消息
        const idx = findLastToolIndex(prev, payload.name);
        if (idx < 0) return prev;
        const updated = [...prev];
        updated[idx] = {
          ...updated[idx],
          toolElapsed: payload.elapsed,
          content: `使用 ${payload.name}... (${payload.elapsed.toFixed(1)}s)`,
        };
        return updated;
      });
    });

    // ── 工具完成 ──
    const unsubToolResult = bridge.on('claudeToolResult', (payload: ToolResultPayload) => {
      stateMachine.dispatch('TOOL_DONE');
      setMessages((prev) => {
        const idx = findLastToolIndex(prev, payload.name);
        if (idx < 0) return prev;
        const updated = [...prev];
        updated[idx] = {
          ...updated[idx],
          toolActive: false,
          toolSummary: payload.summary,
          content: payload.summary || `${payload.name} 完成`,
        };
        return updated;
      });
    });

    // ── 思考过程 ──
    const unsubThinking = bridge.on('claudeThinking', () => {
      // 思考事件不直接显示，只确保状态正确
    });

    // ── 会话初始化 ──
    const unsubInit = bridge.on('claudeInit', (payload: SessionInitPayload) => {
      setSessionInfo({ model: payload.model, tools: payload.tools });
    });

    // ── 完成 ──
    const unsubDone = bridge.on('claudeDone', (payload: DonePayload) => {
      setIsStreaming(false);
      gotFirstToken.current = false;
      setMessages((prev) => {
        const updated = prev.map((m) => {
          // 将流式消息固化
          if (m.id === '__streaming__') {
            return {
              ...m,
              id: `msg-${Date.now()}`,
              metadata: {
                cost: payload?.cost,
                duration: payload?.duration,
              },
            };
          }
          // 将所有活跃工具标记为完成
          if (m.toolActive) {
            return { ...m, toolActive: false };
          }
          return m;
        });
        return updated;
      });
      stateMachine.dispatch('REPLY_DONE');
    });

    // ── 错误 ──
    const unsubError = bridge.on('claudeError', (payload: ErrorPayload) => {
      // 如果是可重试的错误，只更新提示，不添加错误消息
      if (payload.retryable) return;

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
      unsubDelta();
      unsubToolStart();
      unsubToolProgress();
      unsubToolResult();
      unsubThinking();
      unsubInit();
      unsubDone();
      unsubError();
    };
  }, []);

  // 添加消息到列表的辅助函数（供命令系统使用）
  const addMessage = useCallback((role: ChatMessage['role'], content: string) => {
    setMessages((prev) => [
      ...prev,
      {
        id: `${role}-${Date.now()}`,
        role,
        content,
        timestamp: Date.now(),
      },
    ]);
  }, []);

  const sendMessage = useCallback((content: string) => {
    // 检查是否是斜杠命令
    const command = parseSlashCommand(content);
    if (command) {
      // 显示用户输入
      addMessage('user', content);
      // 执行命令
      executeCommand(command.name, command.args, {
        addMessage,
        clearHistory: () => {
          setMessages([]);
          bridge.send('clearChatHistory');
          bridge.send('resetClaudeSession');
        },
        sendToClaude: (msg: string) => {
          gotFirstToken.current = false;
          stateMachine.dispatch('USER_SEND');
          bridge.send('sendMessage', { content: msg });
        },
      });
      return;
    }

    // 普通消息
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
  }, [addMessage]);

  const clearHistory = useCallback(() => {
    setMessages([]);
    bridge.send('clearChatHistory');
    bridge.send('resetClaudeSession');
  }, []);

  return { messages, isStreaming, sessionInfo, sendMessage, clearHistory };
}

// ── 辅助函数 ──

/** 从后往前找最后一个匹配工具名称的活跃工具消息 */
function findLastToolIndex(messages: ChatMessage[], toolName: string): number {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'tool' && messages[i].toolName === toolName && messages[i].toolActive) {
      return i;
    }
  }
  // 如果找不到精确匹配，找最后一个活跃的工具
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'tool' && messages[i].toolActive) {
      return i;
    }
  }
  return -1;
}
