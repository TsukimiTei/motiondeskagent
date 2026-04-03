/**
 * 斜杠命令注册表
 */

import { bridge } from '../bridge';
import type { ChatMessage, ChatMessageRole } from '../types/streamEvents';

export interface CommandContext {
  addMessage: (role: ChatMessageRole, content: string) => void;
  clearHistory: () => void;
  sendToClaude: (content: string) => void;
}

export interface CommandDef {
  name: string;
  description: string;
  handler: (args: string, ctx: CommandContext) => void;
}

const commands: CommandDef[] = [
  {
    name: 'remember',
    description: '保存记忆',
    handler: (args, ctx) => {
      if (!args) {
        ctx.addMessage('system', '用法：/remember <要记住的内容>');
        return;
      }
      bridge.send('addMemory', { content: args, type: 'user' });
      ctx.addMessage('system', `✓ 已记住：${args}`);
    },
  },
  {
    name: 'forget',
    description: '删除记忆',
    handler: (args, ctx) => {
      if (!args) {
        ctx.addMessage('system', '用法：/forget <记忆ID 或关键词>');
        return;
      }
      // 如果是 ID 格式（mem_xxx），直接删除
      if (args.startsWith('mem_')) {
        bridge.send('deleteMemory', { id: args });
        ctx.addMessage('system', `✓ 已删除记忆：${args}`);
      } else {
        // 搜索并删除匹配的记忆
        bridge.send('searchMemories', { query: args });
        ctx.addMessage('system', `🔍 正在搜索包含 "${args}" 的记忆...`);
      }
    },
  },
  {
    name: 'memories',
    description: '查看所有记忆',
    handler: (_args, ctx) => {
      bridge.send('listMemories');
      ctx.addMessage('system', '📋 正在加载记忆列表...');
    },
  },
  {
    name: 'clear',
    description: '清除对话历史',
    handler: (_args, ctx) => {
      ctx.clearHistory();
      ctx.addMessage('system', '✓ 对话已清除');
    },
  },
  {
    name: 'help',
    description: '显示可用命令',
    handler: (_args, ctx) => {
      const lines = commands.map((cmd) => `/${cmd.name} — ${cmd.description}`);
      ctx.addMessage('system', '可用命令：\n' + lines.join('\n'));
    },
  },
  {
    name: 'model',
    description: '显示当前模型信息',
    handler: (_args, ctx) => {
      ctx.addMessage('system', '模型信息将在下次对话时显示');
    },
  },
];

/** 获取所有已注册的命令 */
export function getRegisteredCommands(): CommandDef[] {
  return commands;
}

/** 获取所有命令名 */
export function getCommandNames(): string[] {
  return commands.map((c) => c.name);
}

/** 执行命令，返回是否找到匹配命令 */
export function executeCommand(name: string, args: string, ctx: CommandContext): boolean {
  const cmd = commands.find((c) => c.name === name);
  if (!cmd) {
    ctx.addMessage('system', `未知命令：/${name}\n输入 /help 查看可用命令`);
    return false;
  }
  cmd.handler(args, ctx);
  return true;
}
