import { useEffect, useCallback } from "react";
import { usePaneStore, type PaneId } from "@/stores/usePaneStore";
import { useTabStore } from "@/stores/useTabStore";
import { useFileStore } from "@/stores/useFileStore";
import { TabBar } from "./TabBar";
import { Toolbar } from "./Toolbar";
import { FileList } from "./FileList";
import { StatusBar } from "./StatusBar";
import { SearchBar } from "./SearchBar";
import { cn } from "@/lib/utils";

interface Props {
  paneId: PaneId;
  isActive: boolean;
}

export function FilePane({ paneId, isActive }: Props) {
  const { setActivePane } = usePaneStore();
  const { activeTab } = useTabStore();
  const tabId = activeTab[paneId];
  const tab = useFileStore((s) => s.tabs[tabId]);

  const handleClick = useCallback(() => {
    setActivePane(paneId);
  }, [paneId, setActivePane]);

  // Keyboard shortcuts for this pane
  useEffect(() => {
    if (!isActive || !tab) return;

    const handler = async (e: KeyboardEvent) => {
      const store = useFileStore.getState();
      const selected = Array.from(tab.selected);

      if (e.key === "F5") {
        e.preventDefault();
        // Copy selected to other pane
        const otherPane = paneId === "left" ? "right" : "left";
        const otherTabId = useTabStore.getState().activeTab[otherPane];
        const otherTab = store.tabs[otherTabId];
        if (selected.length > 0 && otherTab) {
          const srcs = selected.map((n) => `${tab.path}/${n}`);
          await store.doCopy(srcs, otherTab.path);
        }
      } else if (e.key === "F6") {
        e.preventDefault();
        const otherPane = paneId === "left" ? "right" : "left";
        const otherTabId = useTabStore.getState().activeTab[otherPane];
        const otherTab = store.tabs[otherTabId];
        if (selected.length > 0 && otherTab) {
          const srcs = selected.map((n) => `${tab.path}/${n}`);
          await store.doMove(srcs, otherTab.path);
        }
      } else if (e.key === "F7") {
        e.preventDefault();
        const name = prompt("New directory name:");
        if (name) await store.doMkdir(tab.path, name);
      } else if (e.key === "F8" || e.key === "Delete") {
        e.preventDefault();
        if (selected.length > 0) {
          const paths = selected.map((n) => `${tab.path}/${n}`);
          if (confirm(`Delete ${paths.length} item(s)?`)) {
            await store.doDelete(paths);
          }
        }
      } else if (e.key === "F2") {
        e.preventDefault();
        if (selected.length === 1) {
          const oldPath = `${tab.path}/${selected[0]}`;
          const newName = prompt("New name:", selected[0]);
          if (newName && newName !== selected[0]) {
            await store.doRename(oldPath, `${tab.path}/${newName}`);
          }
        }
      } else if (e.key === "Backspace") {
        e.preventDefault();
        await store.goUp(tabId);
      } else if (e.key === "Enter") {
        e.preventDefault();
        if (selected.length === 1) {
          const entry = tab.entries.find((e) => e.name === selected[0]);
          if (entry?.is_dir) {
            await store.navigate(tabId, entry.path);
            useTabStore.getState().updateTitle(paneId, tabId, entry.path);
          }
        }
      } else if (e.key === "a" && e.ctrlKey) {
        e.preventDefault();
        store.selectAll(tabId);
      }
    };

    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [isActive, tab, tabId, paneId]);

  return (
    <div
      className={cn(
        "flex flex-col flex-1 min-w-0",
        isActive
          ? "bg-[var(--background)]"
          : "bg-[var(--card)] opacity-80"
      )}
      onClick={handleClick}
    >
      <TabBar paneId={paneId} />
      <Toolbar paneId={paneId} />
      <FileList paneId={paneId} />
      <StatusBar paneId={paneId} />
    </div>
  );
}
