import { useState, useCallback, useEffect } from 'react';
import { bridge } from '../bridge';
import type { MemoryEntry, MemoryType } from '../types/streamEvents';

export function useMemory() {
  const [memories, setMemories] = useState<MemoryEntry[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    // 监听记忆列表响应
    const unsubList = bridge.on('memoryList', (payload: MemoryEntry[]) => {
      setMemories(payload);
      setIsLoading(false);
    });

    // 监听搜索结果
    const unsubSearch = bridge.on('memorySearchResults', (payload: MemoryEntry[]) => {
      setMemories(payload);
      setIsLoading(false);
    });

    // 监听记忆添加
    const unsubAdded = bridge.on('memoryAdded', (payload: MemoryEntry) => {
      setMemories((prev) => [payload, ...prev]);
    });

    // 监听记忆删除
    const unsubDeleted = bridge.on('memoryDeleted', (payload: { id: string; success: boolean }) => {
      if (payload.success) {
        setMemories((prev) => prev.filter((m) => m.id !== payload.id));
      }
    });

    return () => {
      unsubList();
      unsubSearch();
      unsubAdded();
      unsubDeleted();
    };
  }, []);

  const addMemory = useCallback((content: string, type: MemoryType = 'user') => {
    bridge.send('addMemory', { content, type });
  }, []);

  const deleteMemory = useCallback((id: string) => {
    bridge.send('deleteMemory', { id });
  }, []);

  const listMemories = useCallback(() => {
    setIsLoading(true);
    bridge.send('listMemories');
  }, []);

  const searchMemories = useCallback((query: string) => {
    setIsLoading(true);
    bridge.send('searchMemories', { query });
  }, []);

  return {
    memories,
    isLoading,
    addMemory,
    deleteMemory,
    listMemories,
    searchMemories,
  };
}
