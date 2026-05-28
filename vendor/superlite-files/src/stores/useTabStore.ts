import { create } from "zustand";
import { newTabId, useFileStore } from "./useFileStore";
import type { PaneId } from "./usePaneStore";

interface Tab {
  id: string;
  title: string;
}

interface TabStore {
  tabs: Record<PaneId, Tab[]>;
  activeTab: Record<PaneId, string>;

  initPane: (pane: PaneId, homePath: string) => Promise<void>;
  addTab: (pane: PaneId, path: string) => Promise<void>;
  closeTab: (pane: PaneId, tabId: string) => Promise<void>;
  setActive: (pane: PaneId, tabId: string) => void;
  updateTitle: (pane: PaneId, tabId: string, path: string) => void;
}

export const useTabStore = create<TabStore>((set, get) => ({
  tabs: { left: [], right: [] },
  activeTab: { left: "", right: "" },

  initPane: async (pane, homePath) => {
    const tabId = newTabId();
    const title = homePath.split("/").pop() || homePath;
    set((s) => ({
      tabs: { ...s.tabs, [pane]: [{ id: tabId, title }] },
      activeTab: { ...s.activeTab, [pane]: tabId },
    }));
    const paneStore = usePaneStore();
    const fileStore = useFileStore.getState();
    await fileStore.initTab(tabId, homePath);
  },

  addTab: async (pane, path) => {
    const tabId = newTabId();
    const title = path.split("/").pop() || path;
    set((s) => ({
      tabs: { ...s.tabs, [pane]: [...s.tabs[pane], { id: tabId, title }] },
      activeTab: { ...s.activeTab, [pane]: tabId },
    }));
    await useFileStore.getState().initTab(tabId, path);
  },

  closeTab: async (pane, tabId) => {
    const s = get();
    const paneTabs = s.tabs[pane];
    if (paneTabs.length <= 1) return; // Don't close last tab
    const idx = paneTabs.findIndex((t) => t.id === tabId);
    const newTabs = paneTabs.filter((t) => t.id !== tabId);
    const newActive =
      s.activeTab[pane] === tabId
        ? newTabs[Math.min(idx, newTabs.length - 1)].id
        : s.activeTab[pane];
    set({
      tabs: { ...s.tabs, [pane]: newTabs },
      activeTab: { ...s.activeTab, [pane]: newActive },
    });
  },

  setActive: (pane, tabId) => {
    set((s) => ({ activeTab: { ...s.activeTab, [pane]: tabId } }));
  },

  updateTitle: (pane, tabId, path) => {
    const title = path.split("/").pop() || path;
    set((s) => ({
      tabs: {
        ...s.tabs,
        [pane]: s.tabs[pane].map((t) =>
          t.id === tabId ? { ...t, title } : t
        ),
      },
    }));
  },
}));

// Import here to avoid circular dependency
import { usePaneStore } from "./usePaneStore";
