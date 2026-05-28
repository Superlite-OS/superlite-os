import { create } from "zustand";
import { native, type FileEntry } from "@/lib/native";

interface TabState {
  id: string;
  path: string;
  entries: FileEntry[];
  selected: Set<string>;
  loading: boolean;
  error: string | null;
  history: string[];
  historyIndex: number;
}

interface FileStore {
  tabs: Record<string, TabState>;
  activeTabId: Record<string, string>; // paneId -> tabId

  initTab: (tabId: string, path: string) => Promise<void>;
  navigate: (tabId: string, path: string) => Promise<void>;
  goUp: (tabId: string) => Promise<void>;
  goBack: (tabId: string) => Promise<void>;
  goForward: (tabId: string) => Promise<void>;
  refresh: (tabId: string) => Promise<void>;
  toggleSelect: (tabId: string, name: string) => void;
  selectAll: (tabId: string) => void;
  clearSelection: (tabId: string) => void;

  doRename: (oldPath: string, newPath: string) => Promise<void>;
  doDelete: (paths: string[]) => Promise<void>;
  doMkdir: (parentPath: string, name: string) => Promise<void>;
  doCopy: (srcs: string[], dstDir: string) => Promise<void>;
  doMove: (srcs: string[], dstDir: string) => Promise<void>;
}

let tabCounter = 0;
export function newTabId(): string {
  return `tab-${++tabCounter}`;
}

async function loadDir(tabId: string, path: string, set: any): Promise<void> {
  set((s: any) => ({
    tabs: {
      ...s.tabs,
      [tabId]: { ...s.tabs[tabId], loading: true, error: null },
    },
  }));
  try {
    const entries = await native.readDir(path);
    // Sort: dirs first, then by name
    entries.sort((a, b) => {
      if (a.is_dir !== b.is_dir) return a.is_dir ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
    set((s: any) => ({
      tabs: {
        ...s.tabs,
        [tabId]: {
          ...s.tabs[tabId],
          path,
          entries,
          selected: new Set<string>(),
          loading: false,
          history: [
            ...s.tabs[tabId].history.slice(0, s.tabs[tabId].historyIndex + 1),
            path,
          ],
          historyIndex: s.tabs[tabId].historyIndex + 1,
        },
      },
    }));
  } catch (e: any) {
    set((s: any) => ({
      tabs: {
        ...s.tabs,
        [tabId]: { ...s.tabs[tabId], loading: false, error: String(e) },
      },
    }));
  }
}

export const useFileStore = create<FileStore>((set, get) => ({
  tabs: {},
  activeTabId: {},

  initTab: async (tabId, path) => {
    set((s) => ({
      tabs: {
        ...s.tabs,
        [tabId]: {
          id: tabId,
          path,
          entries: [],
          selected: new Set(),
          loading: true,
          error: null,
          history: [path],
          historyIndex: 0,
        },
      },
    }));
    await loadDir(tabId, path, set);
  },

  navigate: async (tabId, path) => {
    await loadDir(tabId, path, set);
  },

  goUp: async (tabId) => {
    const tab = get().tabs[tabId];
    if (!tab) return;
    const parts = tab.path.replace(/\/$/, "").split("/");
    parts.pop();
    const parent = parts.join("/") || "/";
    await loadDir(tabId, parent, set);
  },

  goBack: async (tabId) => {
    const tab = get().tabs[tabId];
    if (!tab || tab.historyIndex <= 0) return;
    const newIndex = tab.historyIndex - 1;
    const path = tab.history[newIndex];
    set((s) => ({
      tabs: {
        ...s.tabs,
        [tabId]: { ...s.tabs[tabId], historyIndex: newIndex },
      },
    }));
    await loadDir(tabId, path, set);
  },

  goForward: async (tabId) => {
    const tab = get().tabs[tabId];
    if (!tab || tab.historyIndex >= tab.history.length - 1) return;
    const newIndex = tab.historyIndex + 1;
    const path = tab.history[newIndex];
    set((s) => ({
      tabs: {
        ...s.tabs,
        [tabId]: { ...s.tabs[tabId], historyIndex: newIndex },
      },
    }));
    await loadDir(tabId, path, set);
  },

  refresh: async (tabId) => {
    const tab = get().tabs[tabId];
    if (!tab) return;
    await loadDir(tabId, tab.path, set);
  },

  toggleSelect: (tabId, name) => {
    set((s) => {
      const tab = s.tabs[tabId];
      if (!tab) return s;
      const sel = new Set(tab.selected);
      sel.has(name) ? sel.delete(name) : sel.add(name);
      return { tabs: { ...s.tabs, [tabId]: { ...tab, selected: sel } } };
    });
  },

  selectAll: (tabId) => {
    set((s) => {
      const tab = s.tabs[tabId];
      if (!tab) return s;
      const sel = new Set(tab.entries.map((e) => e.name));
      return { tabs: { ...s.tabs, [tabId]: { ...tab, selected: sel } } };
    });
  },

  clearSelection: (tabId) => {
    set((s) => {
      const tab = s.tabs[tabId];
      if (!tab) return s;
      return {
        tabs: { ...s.tabs, [tabId]: { ...tab, selected: new Set() } },
      };
    });
  },

  doRename: async (oldPath, newPath) => {
    await native.rename(oldPath, newPath);
    // Refresh all tabs showing the parent directory
    const parentOld = oldPath.replace(/\/[^/]+$/, "");
    const parentNew = newPath.replace(/\/[^/]+$/, "");
    for (const [id, tab] of Object.entries(get().tabs)) {
      if (tab.path === parentOld || tab.path === parentNew) {
        await get().refresh(id);
      }
    }
  },

  doDelete: async (paths) => {
    for (const p of paths) {
      await native.remove(p);
    }
    // Refresh all tabs
    for (const id of Object.keys(get().tabs)) {
      await get().refresh(id);
    }
  },

  doMkdir: async (parentPath, name) => {
    const { joinPath } = await import("@/lib/utils");
    await native.mkdir(joinPath(parentPath, name));
    for (const [id, tab] of Object.entries(get().tabs)) {
      if (tab.path === parentPath) await get().refresh(id);
    }
  },

  doCopy: async (srcs, dstDir) => {
    for (const src of srcs) {
      const name = src.split("/").pop() || "";
      const dst = `${dstDir}/${name}`;
      await native.copy(src, dst, false);
    }
    for (const [id, tab] of Object.entries(get().tabs)) {
      if (tab.path === dstDir) await get().refresh(id);
    }
  },

  doMove: async (srcs, dstDir) => {
    for (const src of srcs) {
      const name = src.split("/").pop() || "";
      const dst = `${dstDir}/${name}`;
      await native.move(src, dst, false);
    }
    for (const id of Object.keys(get().tabs)) {
      await get().refresh(id);
    }
  },
}));
