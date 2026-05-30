use std::path::Path;
use walkdir::WalkDir;
use crate::state::FileEntry;

pub fn search(root: &Path, query: &str, recursive: bool) -> Vec<FileEntry> {
    let query_lower = query.to_lowercase();
    let walker = if recursive {
        WalkDir::new(root).max_depth(10)
    } else {
        WalkDir::new(root).max_depth(1)
    };
    walker.into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name().to_string_lossy().to_lowercase();
            name.contains(&query_lower)
        })
        .filter_map(|e| {
            let meta = e.metadata().ok()?;
            let name = e.file_name().to_string_lossy().to_string();
            let modified = meta.modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let mime_type = super::mime::guess_mime(e.path());
            #[cfg(unix)]
            let permissions = {
                use std::os::unix::fs::PermissionsExt;
                let mode = meta.permissions().mode();
                let u = if mode & 0o400 != 0 { "r" } else { "-" };
                let w = if mode & 0o200 != 0 { "w" } else { "-" };
                let x = if mode & 0o100 != 0 { "x" } else { "-" };
                format!("{}{}{}---", u, w, x)
            };
            #[cfg(not(unix))]
            let permissions = String::from("rw-r--r--");
            Some(FileEntry {
                name,
                path: e.path().to_path_buf(),
                is_dir: e.file_type().is_dir(),
                size: meta.len(),
                modified,
                permissions,
                mime_type,
            })
        })
        .collect()
}
