const iconMap: Record<string, string> = {
  // Folders
  folder: "📁",
  // Documents
  txt: "📄", md: "📝", pdf: "📕", doc: "📘", docx: "📘",
  xls: "📊", xlsx: "📊", csv: "📊",
  ppt: "📙", pptx: "📙",
  // Images
  jpg: "🖼", jpeg: "🖼", png: "🖼", gif: "🖼", svg: "🖼",
  webp: "🖼", bmp: "🖼", ico: "🖼",
  // Video
  mp4: "🎬", mkv: "🎬", avi: "🎬", mov: "🎬", webm: "🎬",
  // Audio
  mp3: "🎵", wav: "🎵", flac: "🎵", ogg: "🎵", aac: "🎵",
  // Code
  js: "📜", ts: "📜", jsx: "📜", tsx: "📜",
  py: "🐍", rs: "🦀", go: "🔵", c: "📜", cpp: "📜", h: "📜",
  html: "🌐", css: "🎨", json: "📋", xml: "📋", yaml: "📋", yml: "📋",
  sh: "⚙", bash: "⚙", zsh: "⚙",
  // Archives
  zip: "📦", tar: "📦", gz: "📦", bz2: "📦", xz: "📦",
  "7z": "📦", rar: "📦",
  // Executables
  exe: "⚡", bin: "⚡", AppImage: "⚡", deb: "📦", rpm: "📦",
};

export function getFileIcon(name: string, isDir: boolean): string {
  if (isDir) return "📁";
  const ext = name.split(".").pop()?.toLowerCase() || "";
  return iconMap[ext] || "📄";
}

export function getMimeCategory(mimeType: string | null): string {
  if (!mimeType) return "unknown";
  if (mimeType.startsWith("image/")) return "image";
  if (mimeType.startsWith("video/")) return "video";
  if (mimeType.startsWith("audio/")) return "audio";
  if (mimeType.startsWith("text/")) return "text";
  if (mimeType.includes("pdf")) return "pdf";
  return "other";
}
