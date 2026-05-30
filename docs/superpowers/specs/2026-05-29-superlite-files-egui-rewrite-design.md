# SuperLite Files — egui Rewrite Design Spec

**Date:** 2026-05-29
**Status:** Approved
**Goal:** Eliminate glibc/webkit2gtk dependency. Single static musl binary.

## Problem

SuperLite Files is currently a Tauri 2 app (Rust + React/TypeScript). Tauri requires `webkit2gtk-4.1` which brings a massive chain of system dependencies. Even with musl dynamic linking, the binary has messy `ldd` output and dependency management is fragile.

## Solution

Rewrite as an egui + eframe application. Single Rust binary, fully static musl, zero external dependencies.

## Architecture

```
superlite-files/
├── Cargo.toml
├── src/
│   ├── main.rs          — eframe window setup, entry point
│   ├── app.rs           — App state + egui update() loop
│   ├── ui/
│   │   ├── mod.rs
│   │   ├── pane.rs      — Dual-pane layout (left/right)
│   │   ├── toolbar.rs   — Navigation bar, action buttons
│   │   ├── file_list.rs — Scrollable file rows (name, size, date, perms)
│   │   ├── tab_bar.rs   — Tab management per pane
│   │   └── status_bar.rs — Current path, selection count
│   ├── fs/
│   │   ├── mod.rs
│   │   ├── ops.rs       — File operations (rename, delete, mkdir, copy, move)
│   │   ├── search.rs    — Recursive/non-recursive file search
│   │   └── mime.rs      — MIME type detection
│   ├── state.rs         — App state (panes, tabs, clipboard, selection)
│   └── theme.rs         — Catppuccin Mocha color palette
```

## Dependencies

```toml
[package]
name = "superlite-files"
version = "0.2.0"
edition = "2021"

[dependencies]
eframe = "0.31"
walkdir = "2"
mime_guess = "2"
chrono = "0.4"
dirs = "6"
```

All pure Rust. Zero C/glibc dependencies.

## UI Layout

```
+-----------------------------------------------+
| <- -> ^  /home/user/documents    [Tab1] [+]   |  <- Toolbar
+------------------------+----------------------+
| Name       Size   Date | Name       Size   Date |  <- Headers
| ..         -      -    | ..         -      -    |
| Documents  <dir>       | Pictures  <dir>       |  <- File list
| file.txt   1.2K        | photo.jpg 2.3M        |
| script.sh  4.5K        | notes.md   0.8K        |
|                        |                        |
+------------------------+----------------------+
| /home/user/docs | 3 items | 1 selected         |  <- Status bar
+-----------------------------------------------+
```

- **Dual pane**: Two side-by-side panels via `egui::SidePanel` or custom layout
- **Tab switcher**: Top of each pane, click to switch, `+` to add
- **File list**: `egui::ScrollArea` with selectable rows
- **Toolbar**: Back/Forward/Up navigation + path display
- **Status bar**: Current path, item count, selection info

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Tab | Switch active pane |
| Enter | Open file/directory |
| Backspace | Go to parent directory |
| Delete | Delete selected |
| Ctrl+C | Copy to clipboard |
| Ctrl+X | Cut to clipboard |
| Ctrl+V | Paste from clipboard |
| Ctrl+N | New directory |
| Ctrl+F | Focus search bar |
| Home | Go to home directory |
| F5 | Refresh current pane |

## File Operations

All file ops run in background threads via `std::sync::mpsc`:

1. UI sends command to channel
2. Worker thread executes (copy/move/delete)
3. Sends progress/result back to UI
4. UI shows progress indicator, no blocking

### Operations

- **Read directory**: `std::fs::read_dir` + `walkdir` for recursive
- **Copy**: Recursive copy with progress
- **Move**: `std::fs::rename`, fallback to copy+delete for cross-filesystem
- **Delete**: `std::fs::remove_file` / `remove_dir_all`
- **Rename**: `std::fs::rename`
- **Mkdir**: `std::fs::create_dir_all`
- **Search**: `walkdir` with pattern matching (case-insensitive)
- **MIME**: `mime_guess::from_path`

## Theme (Catppuccin Mocha)

```rust
pub struct CatppuccinMocha;

impl CatppuccinMocha {
    pub const BASE: Color32 = Color32::from_rgb(30, 30, 46);      // #1e1e2e
    pub const SURFACE: Color32 = Color32::from_rgb(49, 50, 68);   // #313244
    pub const OVERLAY: Color32 = Color32::from_rgb(69, 71, 90);   // #45475a
    pub const TEXT: Color32 = Color32::from_rgb(205, 214, 244);   // #cdd6f4
    pub const SUBTEXT: Color32 = Color32::from_rgb(186, 194, 222);// #bac2de
    pub const BLUE: Color32 = Color32::from_rgb(137, 180, 250);   // #89b4fa
    pub const GREEN: Color32 = Color32::from_rgb(166, 227, 161);  // #a6e3a1
    pub const MAUVE: Color32 = Color32::from_rgb(203, 166, 247);  // #cba6f7
    pub const RED: Color32 = Color32::from_rgb(243, 139, 168);    // #f38ba8
    pub const YELLOW: Color32 = Color32::from_rgb(249, 226, 175); // #f9e2af
    pub const PEACH: Color32 = Color32::from_rgb(250, 179, 135);  // #fab387
}
```

Applied via `egui::Visuals::dark()` with custom color overrides in `theme.rs`.

## Build

```bash
# Static musl binary
RUSTFLAGS="-C target-feature=+crt-static" \
  cargo build --target x86_64-unknown-linux-musl --release

# Output: single binary, ~5-8MB
# ldd: "not a dynamic executable"
```

## Build Script Changes

Update `build-superlite-files.sh` to:
1. Remove Node.js/pnpm/frontend dependencies
2. Remove Tauri system dependencies (webkit2gtk, GTK, etc.)
3. Install only: `curl gcc musl-dev` for rustup + musl build
4. Run `cargo build --target x86_64-unknown-linux-musl --release`
5. Copy single binary to output

## Migration Notes

- Remove `vendor/superlite-files/` (Tauri source)
- Replace with new egui source in same location
- Update `inject-modloop.sh`: remove glibc wrapper logic for SLF, install binary directly
- Update `build-superlite-files.sh`: simplified build
- Remove pnpm/node/tauri dependencies from CI

## Success Criteria

1. `cargo build --target x86_64-unknown-linux-musl --release` succeeds
2. Binary is static: `ldd superlite-files` shows "not a dynamic executable"
3. Binary runs on Alpine musl without any glibc/webkit2gtk
4. All file operations work: browse, copy, move, delete, rename, mkdir, search
5. Dual-pane layout with tab support
6. Catppuccin Mocha theme applied
7. Keyboard shortcuts functional
8. Binary size < 10MB
