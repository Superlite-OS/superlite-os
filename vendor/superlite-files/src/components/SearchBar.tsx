import { useState, useRef, useEffect } from "react";
import { native, type SearchResult } from "@/lib/native";
import { getFileIcon } from "@/lib/file-icons";
import { formatSize, cn } from "@/lib/utils";

interface Props {
  path: string;
  onSelect: (path: string, isDir: boolean) => void;
  onClose: () => void;
}

export function SearchBar({ path, onSelect, onClose }: Props) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    if (!query.trim()) {
      setResults([]);
      return;
    }
    const timer = setTimeout(async () => {
      setLoading(true);
      try {
        const res = await native.search(path, query, false);
        setResults(res.slice(0, 50));
      } catch {
        setResults([]);
      }
      setLoading(false);
    }, 300);
    return () => clearTimeout(timer);
  }, [query, path]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  return (
    <div className="absolute inset-x-0 top-0 z-50 bg-[var(--card)] border-b border-[var(--border)] shadow-lg">
      <div className="flex items-center gap-2 px-3 h-9">
        <span className="text-sm">🔍</span>
        <input
          ref={inputRef}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search files..."
          className="flex-1 bg-transparent text-xs text-[var(--foreground)] outline-none placeholder:text-[var(--muted-foreground)]"
        />
        {loading && (
          <span className="text-xs text-[var(--muted-foreground)]">...</span>
        )}
        <button
          onClick={onClose}
          className="text-xs text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
        >
          ×
        </button>
      </div>
      {results.length > 0 && (
        <div className="max-h-60 overflow-auto border-t border-[var(--border)]">
          {results.map((r) => (
            <button
              key={r.path}
              onClick={() => onSelect(r.path, r.is_dir)}
              className="flex items-center gap-2 w-full px-3 py-1.5 text-xs hover:bg-[var(--accent)] text-left"
            >
              <span>{getFileIcon(r.name, r.is_dir)}</span>
              <span className="flex-1 truncate">{r.path}</span>
              {!r.is_dir && (
                <span className="text-[var(--muted-foreground)]">
                  {formatSize(r.size)}
                </span>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
