use serde::Serialize;
use std::fs;
use std::path::Path;

#[derive(Serialize, Clone)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified: u64,
    pub permissions: String,
    pub mime_type: Option<String>,
}

#[derive(Serialize)]
pub struct SearchResult {
    pub path: String,
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub match_line: Option<String>,
}

fn format_permissions(meta: &fs::Metadata) -> String {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = meta.permissions().mode();
        let user = if mode & 0o400 != 0 { "r" } else { "-" };
        let user_w = if mode & 0o200 != 0 { "w" } else { "-" };
        let user_x = if mode & 0o100 != 0 { "x" } else { "-" };
        let group = if mode & 0o040 != 0 { "r" } else { "-" };
        let group_w = if mode & 0o020 != 0 { "w" } else { "-" };
        let group_x = if mode & 0o010 != 0 { "x" } else { "-" };
        let other = if mode & 0o004 != 0 { "r" } else { "-" };
        let other_w = if mode & 0o002 != 0 { "w" } else { "-" };
        let other_x = if mode & 0o001 != 0 { "x" } else { "-" };
        format!(
            "{}{}{}{}{}{}{}{}{}",
            user, user_w, user_x, group, group_w, group_x, other, other_w, other_x
        )
    }
    #[cfg(not(unix))]
    {
        if meta.permissions().readonly() { "r--r--r--" } else { "rw-rw-rw-" }.to_string()
    }
}

fn entry_from_path(path: &Path) -> Result<FileEntry, String> {
    let meta = fs::metadata(path).map_err(|e| format!("stat {}: {}", path.display(), e))?;
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let modified = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let mime = mime_guess::from_path(path)
        .first()
        .map(|m| m.to_string());

    Ok(FileEntry {
        name,
        path: path.to_string_lossy().to_string(),
        is_dir: meta.is_dir(),
        size: meta.len(),
        modified,
        permissions: format_permissions(&meta),
        mime_type: mime,
    })
}

#[tauri::command]
pub fn fs_read_dir(path: String) -> Result<Vec<FileEntry>, String> {
    let dir = Path::new(&path);
    if !dir.is_dir() {
        return Err(format!("{} is not a directory", path));
    }
    let mut entries = Vec::new();

    // Add parent directory entry
    if let Some(parent) = dir.parent() {
        entries.push(FileEntry {
            name: "..".to_string(),
            path: parent.to_string_lossy().to_string(),
            is_dir: true,
            size: 0,
            modified: 0,
            permissions: String::new(),
            mime_type: None,
        });
    }

    let read = fs::read_dir(dir).map_err(|e| format!("readdir {}: {}", path, e))?;
    for entry in read {
        let entry = entry.map_err(|e| format!("entry: {}", e))?;
        let path = entry.path();
        // Skip hidden files starting with .
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        if name.starts_with('.') {
            continue;
        }
        match entry_from_path(&path) {
            Ok(e) => entries.push(e),
            Err(_) => continue, // Skip files we can't stat
        }
    }

    Ok(entries)
}

#[tauri::command]
pub fn fs_stat(path: String) -> Result<FileEntry, String> {
    entry_from_path(Path::new(&path))
}

#[tauri::command]
pub fn fs_rename(old_path: String, new_path: String) -> Result<(), String> {
    fs::rename(&old_path, &new_path).map_err(|e| format!("rename: {}", e))
}

#[tauri::command]
pub fn fs_delete(path: String) -> Result<(), String> {
    let p = Path::new(&path);
    if p.is_dir() {
        fs::remove_dir_all(p).map_err(|e| format!("rmdir: {}", e))
    } else {
        fs::remove_file(p).map_err(|e| format!("rm: {}", e))
    }
}

#[tauri::command]
pub fn fs_mkdir(path: String) -> Result<(), String> {
    fs::create_dir_all(&path).map_err(|e| format!("mkdir: {}", e))
}

#[tauri::command]
pub fn fs_copy(src: String, dst: String, _overwrite: bool) -> Result<(), String> {
    let src_path = Path::new(&src);
    if src_path.is_dir() {
        copy_dir_recursive(src_path, Path::new(&dst))
            .map_err(|e| format!("copy dir: {}", e))
    } else {
        fs::copy(&src, &dst).map_err(|e| format!("copy: {}", e))?;
        Ok(())
    }
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<(), String> {
    fs::create_dir_all(dst).map_err(|e| format!("mkdir {}: {}", dst.display(), e))?;
    for entry in fs::read_dir(src).map_err(|e| format!("readdir: {}", e))? {
        let entry = entry.map_err(|e| format!("entry: {}", e))?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path).map_err(|e| format!("copy: {}", e))?;
        }
    }
    Ok(())
}

#[tauri::command]
pub fn fs_move(src: String, dst: String, _overwrite: bool) -> Result<(), String> {
    match fs::rename(&src, &dst) {
        Ok(()) => Ok(()),
        Err(e) => {
            // Cross-filesystem move: copy + delete
            if e.raw_os_error() == Some(18) {
                let src_path = Path::new(&src);
                if src_path.is_dir() {
                    copy_dir_recursive(src_path, Path::new(&dst))?;
                    fs::remove_dir_all(src_path).map_err(|e| format!("rm: {}", e))?;
                } else {
                    fs::copy(&src, &dst).map_err(|e| format!("copy: {}", e))?;
                    fs::remove_file(src_path).map_err(|e| format!("rm: {}", e))?;
                }
                Ok(())
            } else {
                Err(format!("move: {}", e))
            }
        }
    }
}

#[tauri::command]
pub fn fs_search(
    path: String,
    pattern: String,
    recursive: bool,
) -> Result<Vec<SearchResult>, String> {
    let mut results = Vec::new();
    let pattern_lower = pattern.to_lowercase();
    let max_results = 100;

    if recursive {
        for entry in walkdir::WalkDir::new(&path)
            .max_depth(10)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            if results.len() >= max_results {
                break;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            if name.to_lowercase().contains(&pattern_lower) {
                let meta = entry.metadata().ok();
                results.push(SearchResult {
                    path: entry.path().to_string_lossy().to_string(),
                    name,
                    is_dir: entry.file_type().is_dir(),
                    size: meta.map(|m| m.len()).unwrap_or(0),
                    match_line: None,
                });
            }
        }
    } else {
        for entry in fs::read_dir(&path).map_err(|e| format!("readdir: {}", e))? {
            if results.len() >= max_results {
                break;
            }
            let entry = entry.map_err(|e| format!("entry: {}", e))?;
            let name = entry.file_name().to_string_lossy().to_string();
            if name.to_lowercase().contains(&pattern_lower) {
                let meta = entry.metadata().ok();
                results.push(SearchResult {
                    path: entry.path().to_string_lossy().to_string(),
                    name,
                    is_dir: meta.as_ref().map(|m| m.is_dir()).unwrap_or(false),
                    size: meta.as_ref().map(|m| m.len()).unwrap_or(0),
                    match_line: None,
                });
            }
        }
    }

    Ok(results)
}

#[tauri::command]
pub fn fs_get_mime(path: String) -> Result<String, String> {
    Ok(mime_guess::from_path(&path)
        .first()
        .map(|m| m.to_string())
        .unwrap_or_else(|| "application/octet-stream".to_string()))
}

#[tauri::command]
pub fn fs_get_home() -> Result<String, String> {
    Ok(dirs::home_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "/root".to_string()))
}
