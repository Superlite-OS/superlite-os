use crate::app::App;
use crate::state::Side;

pub fn show_pane(app: &mut App, ui: &mut egui::Ui, side: Side) {
    super::tab_bar::show(app, ui, side);
    ui.separator();
    super::toolbar::show(app, ui, side);
    ui.separator();
    super::file_list::show(app, ui, side);
    ui.separator();
    super::status_bar::show(app, ui, side);
}
