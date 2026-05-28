import { create } from "zustand";

export type PaneId = "left" | "right";

interface PaneState {
  activePane: PaneId;
  setActivePane: (id: PaneId) => void;
  togglePane: () => void;
}

export const usePaneStore = create<PaneState>((set) => ({
  activePane: "left",
  setActivePane: (id) => set({ activePane: id }),
  togglePane: () =>
    set((s) => ({ activePane: s.activePane === "left" ? "right" : "left" })),
}));
