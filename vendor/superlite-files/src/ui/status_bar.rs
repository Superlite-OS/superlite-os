use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    let (path, count, selected_name) = match side {
        Side::Left => {
            let tab = app.state.left.current_tab();
            let count = tab.entries.len().saturating_sub(1);
            let sel = tab.selected.and_then(|i| tab.entries.get(i)).map(|e| e.name.clone());
            (tab.path.display().to_string(), count, sel)
        }
        Side::Right => {
            let tab = app.state.right.current_tab();
            let count = tab.entries.len().saturating_sub(1);
            let sel = tab.selected.and_then(|i| tab.entries.get(i)).map(|e| e.name.clone());
            (tab.path.display().to_string(), count, sel)
        }
    };

    ui.horizontal(|ui| {
        ui.label(egui::RichText::new(&path).color(CatppuccinMocha::SUBTEXT0).small().monospace());
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if let Some(name) = selected_name {
                ui.label(egui::RichText::new(format!("{} selected", name)).color(CatppuccinMocha::MAUVE).small());
            }
            ui.label(egui::RichText::new(format!("{} items", count)).color(CatppuccinMocha::SUBTEXT0).small());
        });
    });
}
