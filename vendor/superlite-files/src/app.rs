use crate::state::AppState;

pub struct App {
    pub state: AppState,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        super::theme::apply(&cc.egui_ctx);
        let home = dirs::home_dir().unwrap_or_else(|| std::path::PathBuf::from("/root"));
        let mut state = AppState::new(home.clone());
        if let Ok(entries) = crate::fs::ops::read_dir(&home) {
            state.left.current_tab_mut().entries = entries.clone();
            state.right.current_tab_mut().entries = entries;
        }
        Self { state }
    }

    fn handle_keyboard(&mut self, ui: &mut egui::Ui) {
        let events: Vec<egui::Event> = ui.input(|i| i.events.clone());
        let ctrl = ui.input(|i| i.modifiers.ctrl);
        for event in &events {
            match event {
                egui::Event::Key { key, pressed, .. } if *pressed => {
                    match key {
                        egui::Key::Tab => self.state.toggle_side(),
                        egui::Key::Backspace => self.go_up(),
                        egui::Key::Home => self.go_home(),
                        egui::Key::F2 => self.rename_selected(),
                        egui::Key::F5 => self.refresh(),
                        egui::Key::Delete => self.delete_selected(),
                        egui::Key::Enter => self.open_selected(),
                        _ => {}
                    }
                }
                egui::Event::Text(text) => {
                    if text == "c" && ctrl { self.copy_selected(); }
                    else if text == "x" && ctrl { self.cut_selected(); }
                    else if text == "v" && ctrl { self.paste(); }
                    else if text == "n" && ctrl { self.state.new_dir_dialog = true; }
                }
                _ => {}
            }
        }
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

    pub fn navigate_to(&mut self, side: crate::state::Side, path: std::path::PathBuf) {
        let pane = match side {
            crate::state::Side::Left => &mut self.state.left,
            crate::state::Side::Right => &mut self.state.right,
        };
        let tab = pane.current_tab_mut();
        tab.path = path;
        tab.selected = None;
        if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
            tab.entries = entries;
        }
    }

    pub fn refresh_pane(&mut self, side: crate::state::Side) {
        let pane = match side {
            crate::state::Side::Left => &mut self.state.left,
            crate::state::Side::Right => &mut self.state.right,
        };
        let tab = pane.current_tab_mut();
        if let Ok(entries) = crate::fs::ops::read_dir(&tab.path) {
            tab.entries = entries;
        }
    }
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.handle_keyboard(ui);

        // Dual pane layout
        ui.columns(2, |cols| {
            super::ui::pane::show_pane(self, &mut cols[0], crate::state::Side::Left);
            super::ui::pane::show_pane(self, &mut cols[1], crate::state::Side::Right);
        });

        // Dialogs (rendered on top)
        super::ui::dialogs::show(self, ui);
    }
}
