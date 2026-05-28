import { useTabStore } from "@/stores/useTabStore";
import { useFileStore } from "@/stores/useFileStore";
import type { PaneId } from "@/stores/usePaneStore";
import { cn } from "@/lib/utils";

interface Props {
  paneId: PaneId;
}

export function Toolbar({ paneId }: Props) {
  const { activeTab } = useTabStore();
  const tabId = activeTab[paneId];
  const tab = useFileStore((s) => s.tabs[tabId]);
  const { goBack, goForward, goUp, refresh } = useFileStore.getState();

  if (!tab) return null;

  const canBack = tab.historyIndex > 0;
  const canForward = tab.historyIndex < tab.history.length - 1;
  const canUp = tab.path !== "/";

  return (
    <div className="flex items-center gap-1 px-2 h-9 bg-[var(--card)] border-b border-[var(--border)] shrink-0">
      <button
        onClick={() => goBack(tabId)}
        disabled={!canBack}
        className={cn(
          "px-1.5 py-0.5 rounded text-sm",
          canBack
            ? "hover:bg-[var(--accent)] text-[var(--foreground)]"
            : "text-[var(--muted-foreground)] opacity-50"
        )}
        title="Back"
      >
        ←
      </button>
      <button
        onClick={() => goForward(tabId)}
        disabled={!canForward}
        className={cn(
          "px-1.5 py-0.5 rounded text-sm",
          canForward
            ? "hover:bg-[var(--accent)] text-[var(--foreground)]"
            : "text-[var(--muted-foreground)] opacity-50"
        )}
        title="Forward"
      >
        →
      </button>
      <button
        onClick={() => goUp(tabId)}
        disabled={!canUp}
        className={cn(
          "px-1.5 py-0.5 rounded text-sm",
          canUp
            ? "hover:bg-[var(--accent)] text-[var(--foreground)]"
            : "text-[var(--muted-foreground)] opacity-50"
        )}
        title="Up"
      >
        ↑
      </button>
      <button
        onClick={() => refresh(tabId)}
        className="px-1.5 py-0.5 rounded text-sm hover:bg-[var(--accent)] text-[var(--foreground)]"
        title="Refresh"
      >
        ↻
      </button>

      {/* Path bar */}
      <div className="flex-1 mx-2 px-2 py-1 bg-[var(--background)] rounded text-xs text-[var(--foreground)] truncate border border-[var(--border)]">
        {tab.path}
      </div>
    </div>
  );
}
