import type { ChatMessage } from '../hooks/useChat';

/** 工具名称到图标的映射 */
const toolIcons: Record<string, string> = {
  Bash: '⌨',
  FileRead: '📄',
  Read: '📄',
  FileWrite: '✏️',
  Write: '✏️',
  FileEdit: '✏️',
  Edit: '✏️',
  Grep: '🔍',
  Glob: '📁',
  WebSearch: '🌐',
  WebFetch: '🌐',
  Agent: '🤖',
};

/** 获取工具友好显示名 */
function getToolDisplayName(name: string): string {
  const displayNames: Record<string, string> = {
    Bash: '执行命令',
    FileRead: '读取文件',
    Read: '读取文件',
    FileWrite: '写入文件',
    Write: '写入文件',
    FileEdit: '编辑文件',
    Edit: '编辑文件',
    Grep: '搜索内容',
    Glob: '查找文件',
    WebSearch: '网络搜索',
    WebFetch: '获取网页',
    Agent: '子任务',
  };
  return displayNames[name] || name;
}

type Props = {
  message: ChatMessage;
};

export function ToolActivity({ message }: Props) {
  const icon = toolIcons[message.toolName || ''] || '⚙';
  const displayName = getToolDisplayName(message.toolName || '');
  const isActive = message.toolActive;

  return (
    <div className={`tool-activity ${isActive ? 'active' : 'completed'}`}>
      <span className="tool-activity-icon">{icon}</span>
      <span className="tool-activity-name">{displayName}</span>
      {message.toolElapsed != null && message.toolElapsed > 0 && (
        <span className="tool-activity-elapsed">
          {message.toolElapsed.toFixed(1)}s
        </span>
      )}
      {!isActive && message.toolSummary && (
        <span className="tool-activity-summary">{message.toolSummary}</span>
      )}
      {isActive && <span className="tool-activity-spinner" />}
    </div>
  );
}
