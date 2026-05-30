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
