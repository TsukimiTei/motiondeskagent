import { useMemo, useState } from 'react';
import { marked } from 'marked';
import hljs from 'highlight.js';

type Props = {
  content: string;
  role: 'user' | 'assistant';
  isStreaming?: boolean;
};

// 配置 marked：使用 highlight.js 做代码高亮
const renderer = new marked.Renderer();
renderer.code = ({ text, lang }: { text: string; lang?: string }) => {
  const language = lang && hljs.getLanguage(lang) ? lang : undefined;
  const highlighted = language
    ? hljs.highlight(text, { language }).value
    : hljs.highlightAuto(text).value;
  return `<pre><code class="hljs language-${lang || ''}">${highlighted}</code></pre>`;
};

marked.use({ renderer, breaks: true });

export function ChatBubble({ content, role, isStreaming }: Props) {
  const [expanded, setExpanded] = useState(false);

  const html = useMemo(() => {
    try {
      return marked.parse(content) as string;
    } catch {
      return content;
    }
  }, [content]);

  const isLong = content.length > 500;

  return (
    <div className={`chat-bubble ${role} ${isStreaming ? 'streaming' : ''}`}>
      <div
        className={`bubble-content ${isLong && !expanded ? 'collapsed' : ''}`}
        dangerouslySetInnerHTML={{ __html: html }}
      />
      {isLong && (
        <button
          className="expand-toggle"
          onClick={() => setExpanded(!expanded)}
        >
          {expanded ? '收起' : '展开全部'}
        </button>
      )}
      {isStreaming && <span className="cursor-blink">▋</span>}
    </div>
  );
}
