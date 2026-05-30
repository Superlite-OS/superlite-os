use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq)]
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
