import { useTabStore } from "@/stores/useTabStore";
import { useFileStore } from "@/stores/useFileStore";
import type { PaneId } from "@/stores/usePaneStore";
import { cn } from "@/lib/utils";

interface Props {
  paneId: PaneId;
}

export function TabBar({ paneId }: Props) {
  const { tabs, activeTab, setActive, addTab, closeTab } = useTabStore();
  const paneTabs = tabs[paneId];
  const initTab = useFileStore((s) => s.initTab);

  return (
    <div className="flex items-center h-8 bg-[var(--card)] border-b border-[var(--border)] shrink-0 overflow-x-auto">
      {paneTabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => setActive(paneId, tab.id)}
          className={cn(
            "flex items-center gap-1 px-3 h-full text-xs border-r border-[var(--border)] shrink-0",
            "hover:bg-[var(--accent)]",
            activeTab[paneId] === tab.id
              ? "bg-[var(--background)] text-[var(--foreground)]"
              : "text-[var(--muted-foreground)]"
          )}
        >
          <span className="max-w-[120px] truncate">{tab.title}</span>
          {paneTabs.length > 1 && (
            <span
              className="ml-1 hover:text-[var(--destructive)] cursor-pointer"
              onClick={(e) => {
                e.stopPropagation();
                closeTab(paneId, tab.id);
              }}
            >
              ×
            </span>
          )}
        </button>
      ))}
      <button
        onClick={() => addTab(paneId, "/root")}
        className="px-2 h-full text-xs text-[var(--muted-foreground)] hover:bg-[var(--accent)]"
        title="New tab"
      >
        +
      </button>
    </div>
  );
}
