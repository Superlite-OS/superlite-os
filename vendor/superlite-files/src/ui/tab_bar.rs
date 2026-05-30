use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    ui.horizontal(|ui| {
        let (tab_count, active_tab) = match side {
            Side::Left => (app.state.left.tabs.len(), app.state.left.active_tab),
            Side::Right => (app.state.right.tabs.len(), app.state.right.active_tab),
        };

        for i in 0..tab_count {
            let label = match side {
                Side::Left => {
                    let tab = &app.state.left.tabs[i];
                    tab.path.file_name()
                        .map(|n| n.to_string_lossy().to_string())
                        .unwrap_or_else(|| tab.path.display().to_string())
                }
                Side::Right => {
                    let tab = &app.state.right.tabs[i];
                    tab.path.file_name()
                        .map(|n| n.to_string_lossy().to_string())
                        .unwrap_or_else(|| tab.path.display().to_string())
                }
            };
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
