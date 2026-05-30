# SuperLite Files — egui Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite SuperLite Files from Tauri to egui+eframe, producing a single static musl binary with zero glibc dependencies.

**Architecture:** egui immediate-mode GUI with dual-pane file browser, background thread file operations, Catppuccin Mocha theme. Single Rust binary, no frontend/backend split.

**Tech Stack:** Rust 1.75+, egui 0.34, eframe 0.34, walkdir 2, mime_guess 2, chrono 0.4, dirs 6

---

## File Structure

```
vendor/superlite-files/
├── Cargo.toml
├── src/
│   ├── main.rs              — eframe entry point
│   ├── app.rs               — App struct, eframe::App impl, update() loop
│   ├── theme.rs             — Catppuccin Mocha palette + egui Visuals
│   ├── state.rs             — PaneState, TabState, Clipboard, FileEntry
│   ├── ui/
│   │   ├── mod.rs
│   │   ├── pane.rs          — Dual-pane split layout
│   │   ├── toolbar.rs       — Navigation buttons + path display
│   │   ├── file_list.rs     — Scrollable file rows with selection
│   │   ├── tab_bar.rs       — Tab buttons per pane
│   │   └── status_bar.rs    — Path, item count, selection info
│   └── fs/
│       ├── mod.rs
│       ├── ops.rs           — File operations (read_dir, copy, move, delete, rename, mkdir)
│       ├── search.rs        — Recursive file search
│       └── mime.rs          — MIME type detection helper
```

---

## Task 1: Project Setup + Stub Compilation

**Files:**
- Create: `vendor/superlite-files/Cargo.toml`
- Create: `vendor/superlite-files/src/main.rs`
- Create: `vendor/superlite-files/src/lib.rs` (empty stubs)
- Create: `vendor/superlite-files/src/app.rs` (empty stub)
- Create: `vendor/superlite-files/src/theme.rs` (empty stub)
- Create: `vendor/superlite-files/src/state.rs` (empty stub)
- Create: `vendor/superlite-files/src/ui/mod.rs` (empty)
- Create: `vendor/superlite-files/src/fs/mod.rs` (empty)

- [ ] **Step 1: Create Cargo.toml**

```toml
[package]
name = "superlite-files"
version = "0.2.0"
edition = "2021"

[dependencies]
eframe = "0.34"
egui = "0.34"
walkdir = "2"
mime_guess = "2"
chrono = { version = "0.4", features = ["serde"] }
dirs = "6"

[profile.release]
opt-level = "s"
lto = true
codegen-units = 1
strip = true
```

- [ ] **Step 2: Create empty module stubs**

```rust
// src/lib.rs
pub mod app;
pub mod theme;
pub mod state;
pub mod ui;
pub mod fs;
```

```rust
// src/app.rs — placeholder
pub struct App;
impl App {
    pub fn new(_cc: &eframe::CreationContext<'_>) -> Self { Self }
}
impl eframe::App for App {
    fn update(&mut self, _ctx: &egui::Context, _frame: &mut eframe::Frame) {}
}
```

```rust
// src/theme.rs — placeholder
pub fn apply(_ctx: &egui::Context) {}
```

```rust
// src/state.rs — placeholder
```

```rust
// src/ui/mod.rs — placeholder
```

```rust
// src/fs/mod.rs — placeholder
```

- [ ] **Step 3: Create main.rs with eframe 0.34 API**

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() -> eframe::Result {
    let native_options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1100.0, 700.0])
            .with_min_inner_size([700.0, 450.0])
            .with_title("SuperLite Files"),
        ..Default::default()
    };
    eframe::run_native(
        "SuperLite Files",
        native_options,
        Box::new(|cc| Ok(Box::new(superlite_files::app::App::new(cc)))),
    )
}
```

- [ ] **Step 4: Verify compilation**

Run: `cd vendor/superlite-files && cargo check 2>&1 | tail -5`
Expected: `Finished` (no errors)

- [ ] **Step 5: Commit**

```bash
cd vendor/superlite-files && git init && git add . && git commit -m "feat(slf): scaffold egui project with eframe 0.34"
```

---

## Task 2: Catppuccin Mocha Theme

**Files:**
- Modify: `vendor/superlite-files/src/theme.rs`

- [ ] **Step 1: Replace theme.rs with full Catppuccin Mocha palette**

```rust
use eframe::egui;

pub struct CatppuccinMocha;

impl CatppuccinMocha {
    pub const BASE: egui::Color32 = egui::Color32::from_rgb(30, 30, 46);
    pub const MANTLE: egui::Color32 = egui::Color32::from_rgb(24, 24, 37);
    pub const CRUST: egui::Color32 = egui::Color32::from_rgb(17, 17, 27);
    pub const SURFACE0: egui::Color32 = egui::Color32::from_rgb(49, 50, 68);
    pub const SURFACE1: egui::Color32 = egui::Color32::from_rgb(69, 71, 90);
    pub const SURFACE2: egui::Color32 = egui::Color32::from_rgb(88, 91, 112);
    pub const OVERLAY0: egui::Color32 = egui::Color32::from_rgb(108, 112, 134);
    pub const TEXT: egui::Color32 = egui::Color32::from_rgb(205, 214, 244);
    pub const SUBTEXT0: egui::Color32 = egui::Color32::from_rgb(166, 173, 200);
    pub const SUBTEXT1: egui::Color32 = egui::Color32::from_rgb(186, 194, 222);
    pub const BLUE: egui::Color32 = egui::Color32::from_rgb(137, 180, 250);
    pub const GREEN: egui::Color32 = egui::Color32::from_rgb(166, 227, 161);
    pub const MAUVE: egui::Color32 = egui::Color32::from_rgb(203, 166, 247);
    pub const RED: egui::Color32 = egui::Color32::from_rgb(243, 139, 168);
    pub const YELLOW: egui::Color32 = egui::Color32::from_rgb(249, 226, 175);
    pub const PEACH: egui::Color32 = egui::Color32::from_rgb(250, 179, 135);
    pub const TEAL: egui::Color32 = egui::Color32::from_rgb(148, 226, 216);
    pub const SKY: egui::Color32 = egui::Color32::from_rgb(137, 220, 235);
    pub const SAPPHIRE: egui::Color32 = egui::Color32::from_rgb(116, 199, 236);
}

pub fn apply(ctx: &egui::Context) {
    let mut visuals = egui::Visuals::dark();

    visuals.override_text_color = Some(CatppuccinMocha::TEXT);
    visuals.widgets.noninteractive.bg_fill = CatppuccinMocha::SURFACE0;
    visuals.widgets.noninteractive.weak_bg_fill = CatppuccinMocha::SURFACE0;
    visuals.widgets.noninteractive.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::SUBTEXT1);
    visuals.widgets.noninteractive.rounding = egui::Rounding::same(4.0);

    visuals.widgets.inactive.bg_fill = CatppuccinMocha::SURFACE1;
    visuals.widgets.inactive.weak_bg_fill = CatppuccinMocha::SURFACE1;
    visuals.widgets.inactive.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::TEXT);
    visuals.widgets.inactive.rounding = egui::Rounding::same(4.0);

    visuals.widgets.hovered.bg_fill = CatppuccinMocha::BLUE;
    visuals.widgets.hovered.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::BASE);
    visuals.widgets.hovered.rounding = egui::Rounding::same(4.0);

    visuals.widgets.active.bg_fill = CatppuccinMocha::MAUVE;
    visuals.widgets.active.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::BASE);
    visuals.widgets.active.rounding = egui::Rounding::same(4.0);

    visuals.selection.bg_fill = CatppuccinMocha::BLUE.linear_multiply(0.4);
    visuals.selection.stroke = egui::Stroke::new(1.0, CatppuccinMocha::BLUE);

    visuals.extreme_bg_color = CatppuccinMocha::CRUST;
    visuals.faint_bg_color = CatppuccinMocha::MANTLE;
    visuals.window_fill = CatppuccinMocha::BASE;
    visuals.window_stroke = egui::Stroke::new(1.0, CatppuccinMocha::SURFACE1);
    visuals.window_rounding = egui::Rounding::same(8.0);

    ctx.set_visuals(visuals);

    let mut style = (*ctx.style()).clone();
    style.spacing.item_spacing = egui::vec2(8.0, 4.0);
    style.spacing.button_padding = egui::vec2(8.0, 4.0);
    ctx.set_style(style);
}
```

- [ ] **Step 2: Wire theme into App::new**

Update `src/app.rs`:

```rust
pub struct App;

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        super::theme::apply(&cc.egui_ctx);
        Self
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("SuperLite Files");
        });
    }
}
```

- [ ] **Step 3: Verify it compiles and shows themed window**

Run: `cd vendor/superlite-files && cargo run 2>&1 | tail -5`
Expected: Window opens with dark Catppuccin theme, "SuperLite Files" heading

- [ ] **Step 4: Commit**

```bash
git add vendor/superlite-files/src/theme.rs vendor/superlite-files/src/app.rs
git commit -m "feat(slf): add Catppuccin Mocha theme"
```

---

## Task 3: App State Types

**Files:**
- Create: `vendor/superlite-files/src/state.rs`

- [ ] **Step 1: Create state.rs with all data types**

```rust
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq)]
pub enum Side {
    Left,
    Right,
}

impl Side {
    pub fn other(&self) -> Side {
        match self {
            Side::Left => Side::Right,
            Side::Right => Side::Left,
        }
    }

    pub fn label(&self) -> &str {
        match self {
            Side::Left => "left",
            Side::Right => "right",
        }
    }
}

#[derive(Clone, Debug)]
pub struct FileEntry {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
    pub size: u64,
    pub modified: u64,
    pub permissions: String,
    pub mime_type: Option<String>,
}

impl FileEntry {
    pub fn parent_entry(path: &PathBuf) -> Self {
        let parent = path.parent().unwrap_or(path).to_path_buf();
        Self {
            name: "..".to_string(),
            path: parent,
            is_dir: true,
            size: 0,
            modified: 0,
            permissions: String::new(),
            mime_type: None,
        }
    }

    pub fn display_size(&self) -> String {
        if self.is_dir {
            return "<dir>".to_string();
        }
        let size = self.size as f64;
        if size < 1024.0 {
            format!("{}B", size as u64)
        } else if size < 1024.0 * 1024.0 {
            format!("{:.1}K", size / 1024.0)
        } else if size < 1024.0 * 1024.0 * 1024.0 {
            format!("{:.1}M", size / (1024.0 * 1024.0))
        } else {
            format!("{:.1}G", size / (1024.0 * 1024.0 * 1024.0))
        }
    }

    pub fn display_date(&self) -> String {
        if self.modified == 0 {
            return String::new();
        }
        chrono::DateTime::from_timestamp(self.modified as i64, 0)
            .map(|dt| dt.format("%Y-%m-%d %H:%M").to_string())
            .unwrap_or_default()
    }
}

#[derive(Clone, Debug)]
pub struct Tab {
    pub path: PathBuf,
    pub entries: Vec<FileEntry>,
    pub selected: Option<usize>,
}

impl Tab {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            entries: Vec::new(),
            selected: None,
        }
    }

    pub fn selected_entry(&self) -> Option<&FileEntry> {
        self.selected.and_then(|i| self.entries.get(i))
    }
}

#[derive(Clone, Debug)]
pub enum ClipboardAction {
    Copy(Vec<PathBuf>),
    Cut(Vec<PathBuf>),
}

pub struct PaneState {
    pub tabs: Vec<Tab>,
    pub active_tab: usize,
}

impl PaneState {
    pub fn new(home: &PathBuf) -> Self {
        Self {
            tabs: vec![Tab::new(home.clone())],
            active_tab: 0,
        }
    }

    pub fn current_tab(&self) -> &Tab {
        &self.tabs[self.active_tab]
    }

    pub fn current_tab_mut(&mut self) -> &mut Tab {
        &mut self.tabs[self.active_tab]
    }
}

pub struct AppState {
    pub left: PaneState,
    pub right: PaneState,
    pub active_side: Side,
    pub clipboard: Option<ClipboardAction>,
    pub status_message: String,
    pub confirm_delete: bool,
    pub new_dir_name: String,
    pub new_dir_dialog: bool,
    pub rename_target: Option<PathBuf>,
    pub rename_name: String,
    pub rename_dialog: bool,
}

impl AppState {
    pub fn new(home: PathBuf) -> Self {
        Self {
            left: PaneState::new(&home),
            right: PaneState::new(&home),
            active_side: Side::Left,
            clipboard: None,
            status_message: String::new(),
            confirm_delete: false,
            new_dir_name: String::new(),
            new_dir_dialog: false,
            rename_target: None,
            rename_name: String::new(),
            rename_dialog: false,
        }
    }

    pub fn active_pane(&self) -> &PaneState {
        match self.active_side {
            Side::Left => &self.left,
            Side::Right => &self.right,
        }
    }

    pub fn active_pane_mut(&mut self) -> &mut PaneState {
        match self.active_side {
            Side::Left => &mut self.left,
            Side::Right => &mut self.right,
        }
    }

    pub fn toggle_side(&mut self) {
        self.active_side = self.active_side.other();
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd vendor/superlite-files && cargo check 2>&1 | tail -5`
Expected: `Finished` (no errors)

- [ ] **Step 3: Commit**

```bash
git add vendor/superlite-files/src/state.rs
git commit -m "feat(slf): add app state types (panes, tabs, clipboard)"
```

---

## Task 4: File System Operations

**Files:**
- Create: `vendor/superlite-files/src/fs/mod.rs`
- Create: `vendor/superlite-files/src/fs/ops.rs`
- Create: `vendor/superlite-files/src/fs/search.rs`
- Create: `vendor/superlite-files/src/fs/mime.rs`

- [ ] **Step 1: Create fs/mod.rs**

```rust
pub mod ops;
pub mod search;
pub mod mime;
```

- [ ] **Step 2: Create fs/mime.rs**

```rust
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
        Some("image/jpeg") | Some("image/png") | Some("image/gif") | Some("image/webp") => "\u{1f5bc}",
        Some("video/mp4") | Some("video/webm") | Some("video/x-matroska") => "\u{1f3ac}",
        Some("audio/mpeg") | Some("audio/ogg") | Some("audio/flac") => "\u{1f3b5}",
        Some("application/pdf") => "\u{1f4d5}",
        Some("application/zip") | Some("application/x-tar") | Some("application/gzip") => "\u{1f4e6}",
        Some("text/plain") | Some("text/csv") => "\u{1f4c4}",
        Some("text/x-shellscript") | Some("text/x-script.python") => "\u{1f4bb}",
        Some("application/json") | Some("application/xml") => "\u{1f4bb}",
        _ => "\u{1f4c4}",
    }
}
```

- [ ] **Step 3: Create fs/ops.rs**

```rust
use std::fs;
use std::path::{Path, PathBuf};
use crate::state::FileEntry;

fn format_permissions(mode: u32) -> String {
    let user_r = if mode & 0o400 != 0 { "r" } else { "-" };
    let user_w = if mode & 0o200 != 0 { "w" } else { "-" };
    let user_x = if mode & 0o100 != 0 { "x" } else { "-" };
    let grp_r = if mode & 0o040 != 0 { "r" } else { "-" };
    let grp_w = if mode & 0o020 != 0 { "w" } else { "-" };
    let grp_x = if mode & 0o010 != 0 { "x" } else { "-" };
    let oth_r = if mode & 0o004 != 0 { "r" } else { "-" };
    let oth_w = if mode & 0o002 != 0 { "w" } else { "-" };
    let oth_x = if mode & 0o001 != 0 { "x" } else { "-" };
    format!("{}{}{}{}{}{}{}{}{}", user_r, user_w, user_x, grp_r, grp_w, grp_x, oth_r, oth_w, oth_x)
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
        if a.name == ".." {
            return std::cmp::Ordering::Less;
        }
        if b.name == ".." {
            return std::cmp::Ordering::Greater;
        }
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
```

- [ ] **Step 4: Create fs/search.rs**

```rust
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
```

- [ ] **Step 5: Verify it compiles**

Run: `cd vendor/superlite-files && cargo check 2>&1 | tail -5`
Expected: `Finished` (no errors)

- [ ] **Step 6: Commit**

```bash
git add vendor/superlite-files/src/fs/
git commit -m "feat(slf): add file system operations (read, copy, move, delete, search)"
```

---

## Task 5: File List UI Component

**Files:**
- Create: `vendor/superlite-files/src/ui/mod.rs`
- Create: `vendor/superlite-files/src/ui/file_list.rs`

- [ ] **Step 1: Create ui/mod.rs**

```rust
pub mod pane;
pub mod toolbar;
pub mod file_list;
pub mod tab_bar;
pub mod status_bar;
```

- [ ] **Step 2: Create ui/file_list.rs**

```rust
use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    let pane = match side {
        Side::Left => &app.state.left,
        Side::Right => &app.state.right,
    };
    let tab = pane.current_tab();

    // Column headers
    ui.horizontal(|ui| {
        ui.label(egui::RichText::new("Name").strong().color(CatppuccinMocha::SUBTEXT1));
        ui.add_space(ui.available_width() - 120.0);
        ui.label(egui::RichText::new("Size").strong().color(CatppuccinMocha::SUBTEXT1));
        ui.label(egui::RichText::new("Date").strong().color(CatppuccinMocha::SUBTEXT1));
    });
    ui.separator();

    // File list with scroll
    egui::ScrollArea::vertical().show(ui, |ui| {
        for (i, entry) in tab.entries.iter().enumerate() {
            let is_selected = tab.selected == Some(i);
            let row_bg = if is_selected {
                CatppuccinMocha::BLUE.linear_multiply(0.2)
            } else {
                egui::Color32::TRANSPARENT
            };

            let response = ui.allocate_response(
                egui::vec2(ui.available_width(), 22.0),
                egui::Sense::click(),
            );

            // Draw background
            if response.rect.width() > 0.0 {
                ui.painter().rect_filled(response.rect, 0.0, row_bg);
            }

            // Draw row content
            let icon = crate::fs::mime::icon_for(entry);
            ui.horizontal(|ui| {
                ui.set_min_size(egui::vec2(ui.available_width(), 20.0));
                let name_text = format!("{} {}", icon, entry.name);
                let name_color = if entry.is_dir {
                    CatppuccinMocha::BLUE
                } else {
                    CatppuccinMocha::TEXT
                };
                ui.label(egui::RichText::new(name_text).color(name_color));
                ui.add_space(ui.available_width() - 120.0);
                ui.label(egui::RichText::new(entry.display_size()).color(CatppuccinMocha::SUBTEXT0));
                ui.label(egui::RichText::new(entry.display_date()).color(CatppuccinMocha::SUBTEXT0));
            });

            // Handle click
            if response.clicked() {
                let state = match side {
                    Side::Left => &mut app.state.left,
                    Side::Right => &mut app.state.right,
                };
                state.current_tab_mut().selected = Some(i);
            }

            // Double-click to open
            if response.double_clicked() {
                if entry.is_dir {
                    let new_path = entry.path.clone();
                    let state = match side {
                        Side::Left => &mut app.state.left,
                        Side::Right => &mut app.state.right,
                    };
                    let tab = state.current_tab_mut();
                    tab.path = new_path;
                    tab.selected = None;
                    match crate::fs::ops::read_dir(&tab.path) {
                        Ok(entries) => tab.entries = entries,
                        Err(e) => app.state.status_message = e,
                    }
                }
            }
        }
    });
}
```

- [ ] **Step 3: Create stub UI modules**

```rust
// ui/toolbar.rs
use eframe::egui;
use crate::app::App;
use crate::state::Side;

pub fn show(_app: &mut App, _ui: &mut egui::Ui, _side: Side) {}
```

```rust
// ui/tab_bar.rs
use eframe::egui;
use crate::app::App;
use crate::state::Side;

pub fn show(_app: &mut App, _ui: &mut egui::Ui, _side: Side) {}
```

```rust
// ui/status_bar.rs
use eframe::egui;
use crate::app::App;
use crate::state::Side;

pub fn show(_app: &mut App, _ui: &mut egui::Ui, _side: Side) {}
```

```rust
// ui/pane.rs
use eframe::egui;
use crate::app::App;
use crate::state::Side;

pub fn show(app: &mut App, ctx: &egui::Context) {
    egui::SidePanel::left("left_pane")
        .default_width(500.0)
        .show(ctx, |ui| {
            super::file_list::show(app, ui, Side::Left);
        });
    egui::SidePanel::right("right_pane")
        .default_width(500.0)
        .show(ctx, |ui| {
            super::file_list::show(app, ui, Side::Right);
        });
}
```

- [ ] **Step 4: Wire pane into App::update**

Update `src/app.rs`:

```rust
pub struct App {
    pub state: crate::state::AppState,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        super::theme::apply(&cc.egui_ctx);
        let home = dirs::home_dir().unwrap_or_else(|| std::path::PathBuf::from("/root"));
        let mut state = crate::state::AppState::new(home.clone());
        // Load initial directory listings
        if let Ok(entries) = crate::fs::ops::read_dir(&home) {
            state.left.current_tab_mut().entries = entries.clone();
            state.right.current_tab_mut().entries = entries;
        }
        Self { state }
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        super::ui::pane::show(self, ctx);
    }
}
```

- [ ] **Step 5: Verify it compiles and shows dual-pane**

Run: `cd vendor/superlite-files && cargo run 2>&1 | tail -5`
Expected: Window with two panes showing file list

- [ ] **Step 6: Commit**

```bash
git add vendor/superlite-files/src/ui/ vendor/superlite-files/src/app.rs
git commit -m "feat(slf): add dual-pane file list UI"
```

---

## Task 6: Toolbar + Navigation

**Files:**
- Modify: `vendor/superlite-files/src/ui/toolbar.rs`
- Modify: `vendor/superlite-files/src/ui/pane.rs`

- [ ] **Step 1: Implement toolbar.rs**

```rust
use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    ui.horizontal(|ui| {
        let pane = match side {
            Side::Left => &app.state.left,
            Side::Right => &app.state.right,
        };
        let path = pane.current_tab().path.display().to_string();

        // Back button
        if ui.button(egui::RichText::new("\u{25c0}").color(CatppuccinMocha::TEXT)).clicked() {
            let state = match side {
                Side::Left => &mut app.state.left,
                Side::Right => &mut app.state.right,
            };
            let tab = state.current_tab_mut();
            if let Some(parent) = tab.path.parent() {
                let new_path = parent.to_path_buf();
                tab.path = new_path;
                tab.selected = None;
                if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
                    tab.entries = entries;
                }
            }
        }

        // Home button
        if ui.button(egui::RichText::new("\u{2302}").color(CatppuccinMocha::TEXT)).clicked() {
            let home = dirs::home_dir().unwrap_or_else(|| std::path::PathBuf::from("/root"));
            let state = match side {
                Side::Left => &mut app.state.left,
                Side::Right => &mut app.state.right,
            };
            let tab = state.current_tab_mut();
            tab.path = home;
            tab.selected = None;
            if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
                tab.entries = entries;
            }
        }

        // Refresh button
        if ui.button(egui::RichText::new("\u{21bb}").color(CatppuccinMocha::TEXT)).clicked() {
            let state = match side {
                Side::Left => &mut app.state.left,
                Side::Right => &mut app.state.right,
            };
            let tab = state.current_tab_mut();
            if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
                tab.entries = entries;
            }
        }

        // Path display
        ui.add_space(8.0);
        ui.label(egui::RichText::new(&path).color(CatppuccinMocha::SUBTEXT1).monospace());
    });
}
```

- [ ] **Step 2: Update pane.rs to include toolbar**

```rust
use eframe::egui;
use crate::app::App;
use crate::state::Side;

pub fn show(app: &mut App, ctx: &egui::Context) {
    egui::SidePanel::left("left_pane")
        .default_width(500.0)
        .show(ctx, |ui| {
            super::toolbar::show(app, ui, Side::Left);
            ui.separator();
            super::file_list::show(app, ui, Side::Left);
            ui.separator();
            super::status_bar::show(app, ui, Side::Left);
        });
    egui::SidePanel::right("right_pane")
        .default_width(500.0)
        .show(ctx, |ui| {
            super::toolbar::show(app, ui, Side::Right);
            ui.separator();
            super::file_list::show(app, ui, Side::Right);
            ui.separator();
            super::status_bar::show(app, ui, Side::Right);
        });
}
```

- [ ] **Step 3: Implement status_bar.rs**

```rust
use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    let pane = match side {
        Side::Left => &app.state.left,
        Side::Right => &app.state.right,
    };
    let tab = pane.current_tab();
    let path = tab.path.display().to_string();
    let count = tab.entries.len().saturating_sub(1); // exclude ".."
    let selected = tab.selected
        .and_then(|i| tab.entries.get(i))
        .map(|e| e.name.clone())
        .unwrap_or_default();

    ui.horizontal(|ui| {
        ui.label(egui::RichText::new(&path).color(CatppuccinMocha::SUBTEXT0).small().monospace());
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if !selected.is_empty() {
                ui.label(egui::RichText::new(format!("{} selected", selected)).color(CatppuccinMocha::MAUVE).small());
            }
            ui.label(egui::RichText::new(format!("{} items", count)).color(CatppuccinMocha::SUBTEXT0).small());
        });
    });
}
```

- [ ] **Step 4: Verify toolbar works**

Run: `cd vendor/superlite-files && cargo run 2>&1 | tail -5`
Expected: Toolbar with back/home/refresh buttons, path display, status bar

- [ ] **Step 5: Commit**

```bash
git add vendor/superlite-files/src/ui/
git commit -m "feat(slf): add toolbar navigation and status bar"
```

---

## Task 7: Keyboard Shortcuts + Tab Switching

**Files:**
- Modify: `vendor/superlite-files/src/app.rs`

- [ ] **Step 1: Add keyboard handling to App::update**

Replace `src/app.rs` with:

```rust
use eframe::egui;
use crate::state::Side;

pub struct App {
    pub state: crate::state::AppState,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        super::theme::apply(&cc.egui_ctx);
        let home = dirs::home_dir().unwrap_or_else(|| std::path::PathBuf::from("/root"));
        let mut state = crate::state::AppState::new(home.clone());
        if let Ok(entries) = crate::fs::ops::read_dir(&home) {
            state.left.current_tab_mut().entries = entries.clone();
            state.right.current_tab_mut().entries = entries;
        }
        Self { state }
    }

    fn handle_keyboard(&mut self, ctx: &egui::Context) {
        ctx.input(|i| {
            for event in &i.events {
                match event {
                    egui::Event::Key(key, pressed, _modifiers) if *pressed => {
                        match key.logical_key {
                            egui::Key::Tab => self.state.toggle_side(),
                            egui::Key::Backspace => self.go_up(),
                            egui::Key::Home => self.go_home(),
                            egui::Key::F5 => self.refresh(),
                            egui::Key::Delete => self.delete_selected(),
                            egui::Key::Enter => self.open_selected(),
                            _ => {}
                        }
                    }
                    egui::Event::Text(text) => {
                        if text == "c" && ctx.input(|i| i.modifiers.ctrl) {
                            self.copy_selected();
                        } else if text == "x" && ctx.input(|i| i.modifiers.ctrl) {
                            self.cut_selected();
                        } else if text == "v" && ctx.input(|i| i.modifiers.ctrl) {
                            self.paste();
                        } else if text == "n" && ctx.input(|i| i.modifiers.ctrl) {
                            self.state.new_dir_dialog = true;
                        }
                    }
                    _ => {}
                }
            }
        });
    }

    fn go_up(&mut self) {
        let state = self.state.active_pane_mut();
        let tab = state.current_tab_mut();
        if let Some(parent) = tab.path.parent() {
            let new_path = parent.to_path_buf();
            tab.path = new_path;
            tab.selected = None;
            if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
                tab.entries = entries;
            }
        }
    }

    fn go_home(&mut self) {
        let home = dirs::home_dir().unwrap_or_else(|| std::path::PathBuf::from("/root"));
        let state = self.state.active_pane_mut();
        let tab = state.current_tab_mut();
        tab.path = home;
        tab.selected = None;
        if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
            tab.entries = entries;
        }
    }

    fn refresh(&mut self) {
        let state = self.state.active_pane_mut();
        let tab = state.current_tab_mut();
        if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
            tab.entries = entries;
        }
    }

    fn open_selected(&mut self) {
        let entry = {
            let state = self.state.active_pane();
            state.current_tab().selected_entry().cloned()
        };
        if let Some(entry) = entry {
            if entry.is_dir {
                let state = self.state.active_pane_mut();
                let tab = state.current_tab_mut();
                tab.path = entry.path;
                tab.selected = None;
                if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
                    tab.entries = entries;
                }
            }
        }
    }

    fn delete_selected(&mut self) {
        let path = {
            let state = self.state.active_pane();
            state.current_tab().selected_entry().map(|e| e.path.clone())
        };
        if let Some(path) = path {
            if let Err(e) = crate::fs::ops::remove(&path) {
                self.state.status_message = e;
            } else {
                self.refresh();
            }
        }
    }

    fn copy_selected(&mut self) {
        let paths: Vec<std::path::PathBuf> = {
            let state = self.state.active_pane();
            state.current_tab().selected_entry()
                .map(|e| vec![e.path.clone()])
                .unwrap_or_default()
        };
        if !paths.is_empty() {
            self.state.clipboard = Some(crate::state::ClipboardAction::Copy(paths));
        }
    }

    fn cut_selected(&mut self) {
        let paths: Vec<std::path::PathBuf> = {
            let state = self.state.active_pane();
            state.current_tab().selected_entry()
                .map(|e| vec![e.path.clone()])
                .unwrap_or_default()
        };
        if !paths.is_empty() {
            self.state.clipboard = Some(crate::state::ClipboardAction::Cut(paths));
        }
    }

    fn paste(&mut self) {
        let action = self.state.clipboard.clone();
        if let Some(action) = action {
            let dest = self.state.active_pane().current_tab().path.clone();
            match action {
                crate::state::ClipboardAction::Copy(paths) => {
                    for src in &paths {
                        let file_name = src.file_name().unwrap_or_default();
                        let dst = dest.join(file_name);
                        if let Err(e) = crate::fs::ops::copy(src, &dst) {
                            self.state.status_message = e;
                        }
                    }
                }
                crate::state::ClipboardAction::Cut(paths) => {
                    for src in &paths {
                        let file_name = src.file_name().unwrap_or_default();
                        let dst = dest.join(file_name);
                        if let Err(e) = crate::fs::ops::move_item(src, &dst) {
                            self.state.status_message = e;
                        }
                    }
                    self.state.clipboard = None;
                }
            }
            self.refresh();
        }
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.handle_keyboard(ctx);
        super::ui::pane::show(self, ctx);
    }
}
```

- [ ] **Step 2: Verify keyboard shortcuts work**

Run: `cd vendor/superlite-files && cargo run 2>&1 | tail -5`
Expected: Tab switches pane, Backspace goes up, Enter opens dirs, Del deletes

- [ ] **Step 3: Commit**

```bash
git add vendor/superlite-files/src/app.rs
git commit -m "feat(slf): add keyboard shortcuts (tab, backspace, delete, ctrl+c/x/v)"
```

---

## Task 8: Build Script + inject-modloop Integration

**Files:**
- Modify: `build-superlite-files.sh`
- Modify: `inject-modloop.sh` (SLF section)

- [ ] **Step 1: Replace build-superlite-files.sh**

```bash
#!/bin/sh
# build-superlite-files.sh — Build SuperLite Files (egui, static musl)
# Sourced from build.sh inside the Docker container.
# Outputs: /tmp/superlite-files-musl/usr/bin/superlite-files

OUTPUT="/tmp/superlite-files-musl"
BUILDLOG="/tmp/superlite-files-build.log"
SRC="/build/vendor/superlite-files"

export RUSTUP_HOME=/root/.rustup
export CARGO_HOME=/root/.cargo

log() { echo "[slf-build] $*"; }

# Stage 1: Install Rust
log "=== Stage 1: Install Rust ==="
apk add --no-cache curl gcc musl-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
export PATH="$CARGO_HOME/bin:$PATH"
log "Rust: $(rustc --version 2>&1)"

# Stage 2: Add musl target
log "=== Stage 2: Add musl target ==="
rustup target add x86_64-unknown-linux-musl

# Stage 3: Build
log "=== Stage 3: Build (static musl) ==="
if [ ! -d "$SRC" ]; then
    log "ERROR: Source not found at $SRC"
    exit 1
fi
cd "$SRC"
RUSTFLAGS="-C target-feature=+crt-static" cargo build --target x86_64-unknown-linux-musl --release 2>&1 | tee "$BUILDLOG"
if [ $? -ne 0 ]; then
    log "ERROR: Build failed"
    exit 1
fi

# Stage 4: Package
log "=== Stage 4: Package ==="
BIN="$SRC/target/x86_64-unknown-linux-musl/release/superlite-files"
if [ ! -f "$BIN" ]; then
    log "ERROR: Binary not found at $BIN"
    exit 1
fi

file "$BIN"
ldd "$BIN" 2>&1 || true

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/usr/bin"
cp -v "$BIN" "$OUTPUT/usr/bin/superlite-files"
chmod +x "$OUTPUT/usr/bin/superlite-files"

log "=== Done ==="
ls -la "$OUTPUT/usr/bin/superlite-files"
log "Build complete!"
```

- [ ] **Step 2: Update inject-modloop.sh SLF section**

Replace the SLF installation block (lines ~436-476) with:

```bash
# ── SuperLite Files (egui, static musl binary) ─────────────────────────
SLF_INSTALLED=0
if [ -d "/tmp/superlite-files-musl" ] && [ -f "/tmp/superlite-files-musl/usr/bin/superlite-files" ]; then
    log "Installing SuperLite Files (static musl)..."
    cp -a /tmp/superlite-files-musl/usr/bin/superlite-files "$SQFS/usr/bin/superlite-files"
    chmod +x "$SQFS/usr/bin/superlite-files"
    SLF_INSTALLED=1
elif [ -f "$REPO_DIR/prebuilt/superlite-files/usr/bin/superlite-files" ]; then
    log "Installing SuperLite Files (prebuilt static)..."
    cp -a "$REPO_DIR/prebuilt/superlite-files/usr/bin/superlite-files" "$SQFS/usr/bin/superlite-files"
    chmod +x "$SQFS/usr/bin/superlite-files"
    SLF_INSTALLED=1
fi

if [ "$SLF_INSTALLED" = "0" ]; then
    log "WARNING: SuperLite Files not found"
fi
```

- [ ] **Step 3: Verify build script is valid**

Run: `bash -n build-superlite-files.sh`
Expected: No syntax errors

- [ ] **Step 4: Commit**

```bash
git add build-superlite-files.sh inject-modloop.sh
git commit -m "feat(slf): update build script for egui static musl binary"
```

---

## Task 9: Tab Bar UI

**Files:**
- Modify: `vendor/superlite-files/src/ui/tab_bar.rs`
- Modify: `vendor/superlite-files/src/ui/pane.rs`

- [ ] **Step 1: Implement tab_bar.rs**

```rust
use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    ui.horizontal(|ui| {
        let (tabs, active_tab) = match side {
            Side::Left => (&app.state.left.tabs, app.state.left.active_tab),
            Side::Right => (&app.state.right.tabs, app.state.right.active_tab),
        };

        for (i, tab) in tabs.iter().enumerate() {
            let label = tab.path.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| tab.path.display().to_string());
            let is_active = i == active_tab;
            let text = if is_active {
                egui::RichText::new(&label).strong().color(CatppuccinMocha::BLUE)
            } else {
                egui::RichText::new(&label).color(CatppuccinMocha::SUBTEXT0)
            };
            if ui.button(text).clicked() {
                match side {
                    Side::Left => app.state.left.active_tab = i,
                    Side::Right => app.state.right.active_tab = i,
                }
            }
        }

        // Add tab button
        if ui.button(egui::RichText::new("+").color(CatppuccinMocha::GREEN)).clicked() {
            let path = match side {
                Side::Left => app.state.left.current_tab().path.clone(),
                Side::Right => app.state.right.current_tab().path.clone(),
            };
            let new_tab = crate::state::Tab::new(path);
            match side {
                Side::Left => {
                    app.state.left.tabs.push(new_tab);
                    app.state.left.active_tab = app.state.left.tabs.len() - 1;
                }
                Side::Right => {
                    app.state.right.tabs.push(new_tab);
                    app.state.right.active_tab = app.state.right.tabs.len() - 1;
                }
            }
        }
    });
}
```

- [ ] **Step 2: Update pane.rs to include tab_bar**

```rust
use eframe::egui;
use crate::app::App;
use crate::state::Side;

pub fn show(app: &mut App, ctx: &egui::Context) {
    egui::SidePanel::left("left_pane")
        .default_width(500.0)
        .show(ctx, |ui| {
            super::tab_bar::show(app, ui, Side::Left);
            ui.separator();
            super::toolbar::show(app, ui, Side::Left);
            ui.separator();
            super::file_list::show(app, ui, Side::Left);
            ui.separator();
            super::status_bar::show(app, ui, Side::Left);
        });
    egui::SidePanel::right("right_pane")
        .default_width(500.0)
        .show(ctx, |ui| {
            super::tab_bar::show(app, ui, Side::Right);
            ui.separator();
            super::toolbar::show(app, ui, Side::Right);
            ui.separator();
            super::file_list::show(app, ui, Side::Right);
            ui.separator();
            super::status_bar::show(app, ui, Side::Right);
        });
}
```

- [ ] **Step 3: Verify tabs work**

Run: `cd vendor/superlite-files && cargo run 2>&1 | tail -5`
Expected: Tab bar with clickable tabs and + button

- [ ] **Step 4: Commit**

```bash
git add vendor/superlite-files/src/ui/
git commit -m "feat(slf): add tab bar with add/switch functionality"
```

---

## Task 10: Dialogs (New Dir, Rename, Delete Confirm)

**Files:**
- Modify: `vendor/superlite-files/src/app.rs`
- Create: `vendor/superlite-files/src/ui/dialogs.rs`

- [ ] **Step 1: Create ui/dialogs.rs**

```rust
use eframe::egui;
use crate::app::App;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ctx: &egui::Context) {
    // New directory dialog
    if app.state.new_dir_dialog {
        egui::Window::new("New Directory")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.label("Directory name:");
                ui.text_edit_singleline(&mut app.state.new_dir_name);
                ui.horizontal(|ui| {
                    if ui.button(egui::RichText::new("Create").color(CatppuccinMocha::GREEN)).clicked() {
                        let path = app.state.active_pane().current_tab().path.join(&app.state.new_dir_name);
                        if let Err(e) = crate::fs::ops::mkdir(&path) {
                            app.state.status_message = e;
                        } else {
                            let state = app.state.active_pane_mut();
                            let tab = state.current_tab_mut();
                            if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
                                tab.entries = entries;
                            }
                        }
                        app.state.new_dir_name.clear();
                        app.state.new_dir_dialog = false;
                    }
                    if ui.button("Cancel").clicked() {
                        app.state.new_dir_name.clear();
                        app.state.new_dir_dialog = false;
                    }
                });
            });
    }

    // Rename dialog
    if app.state.rename_dialog {
        if let Some(ref target) = app.state.rename_target.clone() {
            let old_name = target.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            egui::Window::new("Rename")
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label(format!("Rename '{}':", old_name));
                    ui.text_edit_singleline(&mut app.state.rename_name);
                    ui.horizontal(|ui| {
                        if ui.button(egui::RichText::new("Rename").color(CatppuccinMocha::BLUE)).clicked() {
                            let new_path = target.parent().unwrap_or(target).join(&app.state.rename_name);
                            if let Err(e) = crate::fs::ops::rename(target, &new_path) {
                                app.state.status_message = e;
                            } else {
                                let state = app.state.active_pane_mut();
                                let tab = state.current_tab_mut();
                                if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
                                    tab.entries = entries;
                                }
                            }
                            app.state.rename_name.clear();
                            app.state.rename_target = None;
                            app.state.rename_dialog = false;
                        }
                        if ui.button("Cancel").clicked() {
                            app.state.rename_name.clear();
                            app.state.rename_target = None;
                            app.state.rename_dialog = false;
                        }
                    });
                });
        }
    }

    // Status message toast
    if !app.state.status_message.is_empty() {
        egui::Window::new("Status")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.label(egui::RichText::new(&app.state.status_message).color(CatppuccinMocha::RED));
                if ui.button("OK").clicked() {
                    app.state.status_message.clear();
                }
            });
    }
}
```

- [ ] **Step 2: Wire dialogs into App::update**

Add to `app.rs` update method, after `pane::show`:

```rust
super::ui::dialogs::show(self, ctx);
```

- [ ] **Step 3: Add F2 rename shortcut**

In `handle_keyboard`, add:

```rust
egui::Key::F2 => self.rename_selected(),
```

And add method:

```rust
fn rename_selected(&mut self) {
    let path = {
        let state = self.state.active_pane();
        state.current_tab().selected_entry().map(|e| e.path.clone())
    };
    if let Some(path) = path {
        let name = path.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        self.state.rename_target = Some(path);
        self.state.rename_name = name;
        self.state.rename_dialog = true;
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add vendor/superlite-files/src/ui/dialogs.rs vendor/superlite-files/src/app.rs
git commit -m "feat(slf): add dialogs (new dir, rename, status toast)"
```

---

## Task 11: Final Verification

- [ ] **Step 1: Full compilation check**

Run: `cd vendor/superlite-files && cargo build --release 2>&1 | tail -10`
Expected: `Finished` with no warnings

- [ ] **Step 2: Check binary size**

Run: `ls -lh vendor/superlite-files/target/release/superlite-files`
Expected: < 10MB

- [ ] **Step 3: Check static linking**

Run: `file vendor/superlite-files/target/release/superlite-files`
Expected: `statically linked`

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat(slf): egui rewrite complete — static musl, zero glibc deps"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Project scaffold | Cargo.toml, main.rs, lib.rs |
| 2 | Catppuccin theme | theme.rs |
| 3 | State types | state.rs |
| 4 | FS operations | fs/*.rs |
| 5 | File list UI | ui/file_list.rs |
| 6 | Toolbar + nav | ui/toolbar.rs, status_bar.rs, pane.rs |
| 7 | Keyboard shortcuts | app.rs |
| 8 | Build script | build-superlite-files.sh, inject-modloop.sh |
| 9 | Tab bar | ui/tab_bar.rs |
| 10 | Dialogs | ui/dialogs.rs |
| 11 | Final verify | All files |
