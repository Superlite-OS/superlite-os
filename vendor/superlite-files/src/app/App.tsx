import { useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { native } from "@/lib/native";
import { usePaneStore } from "@/stores/usePaneStore";
import { useTabStore } from "@/stores/useTabStore";
import { FilePane } from "@/components/FilePane";
import { Toaster } from "sonner";

export default function App() {
  const [ready, setReady] = useState(false);
  const [homePath, setHomePath] = useState("/root");
  const { activePane, togglePane } = usePaneStore();
  const { initPane } = useTabStore();

  useEffect(() => {
    (async () => {
      try {
        const home = await native.getHome();
        setHomePath(home);
      } catch {
        // fallback to /root
      }
      await initPane("left", homePath);
      await initPane("right", homePath);
      setReady(true);
      try {
        await getCurrentWindow().show();
      } catch {}
    })();
  }, []);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Tab") {
        e.preventDefault();
        togglePane();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [togglePane]);

  if (!ready) return null;

  return (
    <div className="flex flex-col h-screen">
      {/* Title bar drag area */}
      <div
        data-tauri-drag-region
        className="h-8 flex items-center px-3 text-xs text-[var(--muted-foreground)] shrink-0"
      >
        SuperLite Files
      </div>

      {/* Dual pane */}
      <div className="flex flex-1 min-h-0">
        <FilePane paneId="left" isActive={activePane === "left"} />
        <div className="w-px bg-[var(--border)] shrink-0" />
        <FilePane paneId="right" isActive={activePane === "right"} />
      </div>

      <Toaster
        position="bottom-center"
        theme="dark"
        richColors
        closeButton
      />
    </div>
  );
}
