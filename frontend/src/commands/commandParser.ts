/**
 * 斜杠命令解析器
 */

export interface SlashCommand {
  name: string;
  args: string;
}

/** 解析输入文本，如果是斜杠命令返回命令对象，否则返回 null */
export function parseSlashCommand(input: string): SlashCommand | null {
  const trimmed = input.trim();
  const match = trimmed.match(/^\/(\w+)\s*(.*)/s);
  if (!match) return null;
  return { name: match[1].toLowerCase(), args: match[2].trim() };
}

/** 获取所有以前缀开头的命令名 */
export function getCommandCompletions(prefix: string, commands: string[]): string[] {
  const lower = prefix.toLowerCase();
  return commands.filter((c) => c.startsWith(lower));
}
