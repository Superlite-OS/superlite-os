import { invoke } from "@tauri-apps/api/core";

export interface FileEntry {
  name: string;
  path: string;
  is_dir: boolean;
  size: number;
  modified: number;
  permissions: string;
  mime_type: string | null;
}

export interface SearchResult {
  path: string;
  name: string;
  is_dir: boolean;
  size: number;
  match_line?: string;
}

export const native = {
  readDir: (path: string) => invoke<FileEntry[]>("fs_read_dir", { path }),
  stat: (path: string) => invoke<FileEntry>("fs_stat", { path }),
  rename: (oldPath: string, newPath: string) =>
    invoke<void>("fs_rename", { oldPath, newPath }),
  remove: (path: string) => invoke<void>("fs_delete", { path }),
  mkdir: (path: string) => invoke<void>("fs_mkdir", { path }),
  copy: (src: string, dst: string, overwrite: boolean) =>
    invoke<void>("fs_copy", { src, dst, overwrite }),
  move: (src: string, dst: string, overwrite: boolean) =>
    invoke<void>("fs_move", { src, dst, overwrite }),
  search: (path: string, pattern: string, recursive: boolean) =>
    invoke<SearchResult[]>("fs_search", { path, pattern, recursive }),
  getMime: (path: string) => invoke<string>("fs_get_mime", { path }),
  getHome: () => invoke<string>("fs_get_home"),
};
