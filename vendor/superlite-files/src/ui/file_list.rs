use eframe::egui;
use crate::app::App;
use crate::state::Side;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui, side: Side) {
    let tab_entries = match side {
        Side::Left => app.state.left.current_tab().entries.clone(),
        Side::Right => app.state.right.current_tab().entries.clone(),
    };
    let selected = match side {
        Side::Left => app.state.left.current_tab().selected,
        Side::Right => app.state.right.current_tab().selected,
    };

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
        for (i, entry) in tab_entries.iter().enumerate() {
            let is_selected = selected == Some(i);
            let row_bg = if is_selected {
                CatppuccinMocha::BLUE.linear_multiply(0.2)
            } else {
                egui::Color32::TRANSPARENT
            };

            let response = ui.allocate_response(
                egui::vec2(ui.available_width(), 22.0),
                egui::Sense::click(),
            );

            if response.rect.width() > 0.0 {
                ui.painter().rect_filled(response.rect, 0.0, row_bg);
            }

            let icon = crate::fs::mime::icon_for(entry);
            ui.horizontal(|ui| {
                ui.set_min_size(egui::vec2(ui.available_width(), 20.0));
                let name_color = if entry.is_dir {
                    CatppuccinMocha::BLUE
                } else {
                    CatppuccinMocha::TEXT
                };
                ui.label(egui::RichText::new(format!("{} {}", icon, entry.name)).color(name_color));
                ui.add_space(ui.available_width() - 120.0);
                ui.label(egui::RichText::new(entry.display_size()).color(CatppuccinMocha::SUBTEXT0));
                ui.label(egui::RichText::new(entry.display_date()).color(CatppuccinMocha::SUBTEXT0));
            });

            if response.clicked() {
                match side {
                    Side::Left => app.state.left.current_tab_mut().selected = Some(i),
                    Side::Right => app.state.right.current_tab_mut().selected = Some(i),
                }
            }

            if response.double_clicked() && entry.is_dir {
                app.navigate_to(side, entry.path.clone());
            }
        }
    });
}
