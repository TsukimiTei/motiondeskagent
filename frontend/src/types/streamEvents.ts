/**
 * Claude CLI stream-json 事件的前端类型定义
 * 对应 Swift 端 ClaudeStreamEvent 枚举
 */

// ── Bridge 事件载荷 ──

export interface ToolStartPayload {
  id: string;
  name: string;
  input?: string;
}

export interface ToolProgressPayload {
  name: string;
  elapsed: number;
}

export interface ToolResultPayload {
  name: string;
  summary: string;
}

export interface SessionInitPayload {
  model: string;
  tools: string[];
}

export interface DonePayload {
  cost?: number;
  duration?: number;
}

export interface ThinkingPayload {
  text: string;
}

export interface ErrorPayload {
  error: string;
  retryable?: boolean;
}

// ── 消息类型 ──

export type ChatMessageRole = 'user' | 'assistant' | 'tool' | 'system';

export interface ChatMessage {
  id: string;
  role: ChatMessageRole;
  content: string;
  timestamp: number;
  /** 工具消息专用 */
  toolName?: string;
  toolId?: string;
  toolElapsed?: number;
  toolSummary?: string;
  toolActive?: boolean;
  /** 元数据 */
  metadata?: {
    cost?: number;
    duration?: number;
    model?: string;
  };
}

// ── 会话信息 ──

export interface SessionInfo {
  model: string;
  tools: string[];
}

// ── 记忆类型 ──

export type MemoryType = 'user' | 'feedback' | 'context' | 'reference';

export interface MemoryEntry {
  id: string;
  type: MemoryType;
  content: string;
  created: string;
  updated: string;
}
