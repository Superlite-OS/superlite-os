import { useRef, useCallback } from "react";
import { useVirtualizer } from "@tanstack/react-virtual";
import { useTabStore } from "@/stores/useTabStore";
import { useFileStore } from "@/stores/useFileStore";
import type { PaneId } from "@/stores/usePaneStore";
import { FileRow } from "./FileRow";
import { cn } from "@/lib/utils";

interface Props {
  paneId: PaneId;
}

export function FileList({ paneId }: Props) {
  const { activeTab } = useTabStore();
  const tabId = activeTab[paneId];
  const tab = useFileStore((s) => s.tabs[tabId]);
  const { navigate, toggleSelect } = useFileStore.getState();
  const { updateTitle } = useTabStore.getState();
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: tab?.entries.length || 0,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 32,
    overscan: 10,
  });

  const handleDoubleClick = useCallback(
    async (name: string) => {
      if (!tab) return;
      const entry = tab.entries.find((e) => e.name === name);
      if (entry?.is_dir) {
        await navigate(tabId, entry.path);
        updateTitle(paneId, tabId, entry.path);
      }
    },
    [tab, tabId, paneId, navigate, updateTitle]
  );

  const handleClick = useCallback(
    (name: string) => {
      toggleSelect(tabId, name);
    },
    [tabId, toggleSelect]
  );

  if (!tab) return null;

  if (tab.loading) {
    return (
      <div className="flex-1 flex items-center justify-center text-[var(--muted-foreground)] text-sm">
        Loading...
      </div>
    );
  }

  if (tab.error) {
    return (
      <div className="flex-1 flex items-center justify-center text-[var(--destructive)] text-sm">
        {tab.error}
      </div>
    );
  }

  return (
    <div
      ref={parentRef}
      className="flex-1 overflow-auto"
    >
      <div
        style={{ height: `${virtualizer.getTotalSize()}px`, position: "relative" }}
      >
        {virtualizer.getVirtualItems().map((virtualRow) => {
          const entry = tab.entries[virtualRow.index];
          const isSelected = tab.selected.has(entry.name);
          return (
            <div
              key={entry.name}
              style={{
                position: "absolute",
                top: 0,
                left: 0,
                width: "100%",
                height: `${virtualRow.size}px`,
                transform: `translateY(${virtualRow.start}px)`,
              }}
            >
              <FileRow
                entry={entry}
                isSelected={isSelected}
                onClick={() => handleClick(entry.name)}
                onDoubleClick={() => handleDoubleClick(entry.name)}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}
