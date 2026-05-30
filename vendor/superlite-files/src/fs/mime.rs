use std::path::Path;

pub fn guess_mime(path: &Path) -> Option<String> {
    mime_guess::from_path(path)
        .first()
        .map(|m| m.to_string())
}

pub fn icon_for(entry: &crate::state::FileEntry) -> &'static str {
    if entry.is_dir {
        return "\u{1f4c1}";
    }
    match entry.mime_type.as_deref() {
        Some(t) if t.starts_with("image/") => "\u{1f5bc}",
        Some(t) if t.starts_with("video/") => "\u{1f3ac}",
        Some(t) if t.starts_with("audio/") => "\u{1f3b5}",
        Some("application/pdf") => "\u{1f4d5}",
        Some(t) if t.contains("zip") || t.contains("tar") || t.contains("gzip") => "\u{1f4e6}",
        Some(t) if t.starts_with("text/") => "\u{1f4c4}",
        _ => "\u{1f4c4}",
    }
}
