use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    ui.horizontal(|ui| {
        let path = match side {
            Side::Left => app.state.left.current_tab().path.clone(),
            Side::Right => app.state.right.current_tab().path.clone(),
        };

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
            app.navigate_to(side, home);
        }

        // Refresh button
        if ui.button(egui::RichText::new("\u{21bb}").color(CatppuccinMocha::TEXT)).clicked() {
            app.refresh_pane(side);
        }

        // Path display
        ui.add_space(8.0);
        ui.label(egui::RichText::new(path.display().to_string()).color(CatppuccinMocha::SUBTEXT1).monospace());
    });
}
