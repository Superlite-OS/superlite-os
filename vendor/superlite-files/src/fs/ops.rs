use std::fs;
use std::path::Path;
use crate::state::FileEntry;

fn format_permissions(mode: u32) -> String {
    let u_r = if mode & 0o400 != 0 { "r" } else { "-" };
    let u_w = if mode & 0o200 != 0 { "w" } else { "-" };
    let u_x = if mode & 0o100 != 0 { "x" } else { "-" };
    let g_r = if mode & 0o040 != 0 { "r" } else { "-" };
    let g_w = if mode & 0o020 != 0 { "w" } else { "-" };
    let g_x = if mode & 0o010 != 0 { "x" } else { "-" };
    let o_r = if mode & 0o004 != 0 { "r" } else { "-" };
    let o_w = if mode & 0o002 != 0 { "w" } else { "-" };
    let o_x = if mode & 0o001 != 0 { "x" } else { "-" };
    format!("{}{}{}{}{}{}{}{}{}", u_r, u_w, u_x, g_r, g_w, g_x, o_r, o_w, o_x)
}

fn entry_from_path(path: &Path) -> Result<FileEntry, String> {
    let meta = fs::metadata(path).map_err(|e| format!("stat {}: {}", path.display(), e))?;
    let name = path.file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let modified = meta.modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let permissions = {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            format_permissions(meta.permissions().mode())
        }
        #[cfg(not(unix))]
        {
            if meta.permissions().readonly() { "r--r--r--" } else { "rw-rw-rw-" }.to_string()
        }
    };
    let mime_type = super::mime::guess_mime(path);
    Ok(FileEntry {
        name,
        path: path.to_path_buf(),
        is_dir: meta.is_dir(),
        size: meta.len(),
        modified,
        permissions,
        mime_type,
    })
}

pub fn read_dir(path: &Path) -> Result<Vec<FileEntry>, String> {
    if !path.is_dir() {
        return Err(format!("{} is not a directory", path.display()));
    }
    let mut entries = Vec::new();
    entries.push(FileEntry::parent_entry(&path.to_path_buf()));
    let read = fs::read_dir(path).map_err(|e| format!("readdir {}: {}", path.display(), e))?;
    for entry in read.flatten() {
        let entry_path = entry.path();
        let name = entry_path.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        if name.starts_with('.') {
            continue;
        }
        if let Ok(e) = entry_from_path(&entry_path) {
            entries.push(e);
        }
    }
    entries.sort_by(|a, b| {
        if a.name == ".." { return std::cmp::Ordering::Less; }
        if b.name == ".." { return std::cmp::Ordering::Greater; }
        if a.is_dir != b.is_dir {
            return if a.is_dir { std::cmp::Ordering::Less } else { std::cmp::Ordering::Greater };
        }
        a.name.to_lowercase().cmp(&b.name.to_lowercase())
    });
    Ok(entries)
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<(), String> {
    fs::create_dir_all(dst).map_err(|e| format!("mkdir {}: {}", dst.display(), e))?;
    for entry in fs::read_dir(src).map_err(|e| format!("readdir: {}", e))?.flatten() {
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path).map_err(|e| format!("copy {}: {}", src_path.display(), e))?;
        }
    }
    Ok(())
}

pub fn copy(src: &Path, dst: &Path) -> Result<(), String> {
    if src.is_dir() {
        copy_dir_recursive(src, dst)
    } else {
        fs::copy(src, dst).map_err(|e| format!("copy {}: {}", src.display(), e))?;
        Ok(())
    }
}

pub fn move_item(src: &Path, dst: &Path) -> Result<(), String> {
    fs::rename(src, dst).or_else(|_| {
        copy(src, dst)?;
        remove(src)
    })
}

pub fn remove(path: &Path) -> Result<(), String> {
    if path.is_dir() {
        fs::remove_dir_all(path).map_err(|e| format!("rmdir {}: {}", path.display(), e))
    } else {
        fs::remove_file(path).map_err(|e| format!("rm {}: {}", path.display(), e))
    }
}

pub fn rename(src: &Path, dst: &Path) -> Result<(), String> {
    fs::rename(src, dst).map_err(|e| format!("rename {}: {}", src.display(), e))
}

pub fn mkdir(path: &Path) -> Result<(), String> {
    fs::create_dir(path).map_err(|e| format!("mkdir {}: {}", path.display(), e))
}
