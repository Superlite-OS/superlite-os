use eframe::egui;
use crate::app::App;
use crate::theme::CatppuccinMocha;

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    let ctx = ui.ctx().clone();

    // New directory dialog
    if app.state.new_dir_dialog {
        egui::Window::new("New Directory")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(&ctx, |ui| {
                ui.label("Directory name:");
                ui.text_edit_singleline(&mut app.state.new_dir_name);
                ui.horizontal(|ui| {
                    if ui.button(egui::RichText::new("Create").color(CatppuccinMocha::GREEN)).clicked() {
                        let path = app.state.active_pane().current_tab().path.join(&app.state.new_dir_name);
                        if let Err(e) = crate::fs::ops::mkdir(&path) {
                            app.state.status_message = e;
                        } else {
                            app.refresh_pane(app.state.active_side.clone());
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
        if let Some(target) = app.state.rename_target.clone() {
            let old_name = target.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            egui::Window::new("Rename")
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .show(&ctx, |ui| {
                    ui.label(format!("Rename '{}':", old_name));
                    ui.text_edit_singleline(&mut app.state.rename_name);
                    ui.horizontal(|ui| {
                        if ui.button(egui::RichText::new("Rename").color(CatppuccinMocha::BLUE)).clicked() {
                            let new_path = target.parent().unwrap_or(&target).join(&app.state.rename_name);
                            if let Err(e) = crate::fs::ops::rename(&target, &new_path) {
                                app.state.status_message = e;
                            } else {
                                app.refresh_pane(app.state.active_side.clone());
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
            .show(&ctx, |ui| {
                ui.label(egui::RichText::new(&app.state.status_message).color(CatppuccinMocha::RED));
                if ui.button("OK").clicked() {
                    app.state.status_message.clear();
                }
            });
    }
}
