import { useTabStore } from "@/stores/useTabStore";
import { useFileStore } from "@/stores/useFileStore";
import type { PaneId } from "@/stores/usePaneStore";
import { formatSize } from "@/lib/utils";

interface Props {
  paneId: PaneId;
}

export function StatusBar({ paneId }: Props) {
  const { activeTab } = useTabStore();
  const tabId = activeTab[paneId];
  const tab = useFileStore((s) => s.tabs[tabId]);

  if (!tab) return null;

  const selectedSize = tab.entries
    .filter((e) => tab.selected.has(e.name))
    .reduce((sum, e) => sum + e.size, 0);

  const dirCount = tab.entries.filter((e) => e.is_dir).length;
  const fileCount = tab.entries.length - dirCount;

  return (
    <div className="flex items-center justify-between px-3 h-6 bg-[var(--card)] border-t border-[var(--border)] text-[10px] text-[var(--muted-foreground)] shrink-0">
      <span>
        {tab.selected.size > 0
          ? `${tab.selected.size} selected (${formatSize(selectedSize)})`
          : `${dirCount} dirs, ${fileCount} files`}
      </span>
      <span>
        F5 Copy &middot; F6 Move &middot; F7 Mkdir &middot; F8 Delete &middot; Tab Switch
      </span>
    </div>
  );
}
