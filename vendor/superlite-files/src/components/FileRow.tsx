import type { FileEntry } from "@/lib/native";
import { getFileIcon } from "@/lib/file-icons";
import { formatSize, formatDate, cn } from "@/lib/utils";

interface Props {
  entry: FileEntry;
  isSelected: boolean;
  onClick: () => void;
  onDoubleClick: () => void;
}

export function FileRow({ entry, isSelected, onClick, onDoubleClick }: Props) {
  const icon = getFileIcon(entry.name, entry.is_dir);

  return (
    <div
      className={cn(
        "flex items-center h-8 px-3 text-xs cursor-pointer select-none",
        "hover:bg-[var(--accent)]",
        isSelected && "bg-[var(--primary)]/20 text-[var(--primary)]"
      )}
      onClick={onClick}
      onDoubleClick={onDoubleClick}
    >
      <span className="w-6 text-center shrink-0">{icon}</span>
      <span className="flex-1 min-w-0 truncate px-2">
        {entry.name}
      </span>
      <span className="w-20 text-right shrink-0 text-[var(--muted-foreground)]">
        {entry.is_dir ? "—" : formatSize(entry.size)}
      </span>
      <span className="w-32 text-right shrink-0 text-[var(--muted-foreground)]">
        {formatDate(entry.modified)}
      </span>
      <span className="w-16 text-right shrink-0 text-[var(--muted-foreground)]">
        {entry.permissions}
      </span>
    </div>
  );
}
