use eframe::egui;

pub struct CatppuccinMocha;

impl CatppuccinMocha {
    pub const BASE: egui::Color32 = egui::Color32::from_rgb(30, 30, 46);
    pub const MANTLE: egui::Color32 = egui::Color32::from_rgb(24, 24, 37);
    pub const CRUST: egui::Color32 = egui::Color32::from_rgb(17, 17, 27);
    pub const SURFACE0: egui::Color32 = egui::Color32::from_rgb(49, 50, 68);
    pub const SURFACE1: egui::Color32 = egui::Color32::from_rgb(69, 71, 90);
    pub const SURFACE2: egui::Color32 = egui::Color32::from_rgb(88, 91, 112);
    pub const OVERLAY0: egui::Color32 = egui::Color32::from_rgb(108, 112, 134);
    pub const TEXT: egui::Color32 = egui::Color32::from_rgb(205, 214, 244);
    pub const SUBTEXT0: egui::Color32 = egui::Color32::from_rgb(166, 173, 200);
    pub const SUBTEXT1: egui::Color32 = egui::Color32::from_rgb(186, 194, 222);
    pub const BLUE: egui::Color32 = egui::Color32::from_rgb(137, 180, 250);
    pub const GREEN: egui::Color32 = egui::Color32::from_rgb(166, 227, 161);
    pub const MAUVE: egui::Color32 = egui::Color32::from_rgb(203, 166, 247);
    pub const RED: egui::Color32 = egui::Color32::from_rgb(243, 139, 168);
    pub const YELLOW: egui::Color32 = egui::Color32::from_rgb(249, 226, 175);
    pub const PEACH: egui::Color32 = egui::Color32::from_rgb(250, 179, 135);
    pub const TEAL: egui::Color32 = egui::Color32::from_rgb(148, 226, 216);
}

pub fn apply(ctx: &egui::Context) {
    let mut visuals = egui::Visuals::dark();
    let cr4 = egui::CornerRadius::same(4);
    let cr8 = egui::CornerRadius::same(8);

    visuals.override_text_color = Some(CatppuccinMocha::TEXT);
    visuals.widgets.noninteractive.bg_fill = CatppuccinMocha::SURFACE0;
    visuals.widgets.noninteractive.weak_bg_fill = CatppuccinMocha::SURFACE0;
    visuals.widgets.noninteractive.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::SUBTEXT1);
    visuals.widgets.noninteractive.corner_radius = cr4;

    visuals.widgets.inactive.bg_fill = CatppuccinMocha::SURFACE1;
    visuals.widgets.inactive.weak_bg_fill = CatppuccinMocha::SURFACE1;
    visuals.widgets.inactive.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::TEXT);
    visuals.widgets.inactive.corner_radius = cr4;

    visuals.widgets.hovered.bg_fill = CatppuccinMocha::BLUE;
    visuals.widgets.hovered.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::BASE);
    visuals.widgets.hovered.corner_radius = cr4;

    visuals.widgets.active.bg_fill = CatppuccinMocha::MAUVE;
    visuals.widgets.active.fg_stroke = egui::Stroke::new(1.0, CatppuccinMocha::BASE);
    visuals.widgets.active.corner_radius = cr4;

    visuals.selection.bg_fill = CatppuccinMocha::BLUE.linear_multiply(0.4);
    visuals.selection.stroke = egui::Stroke::new(1.0, CatppuccinMocha::BLUE);

    visuals.extreme_bg_color = CatppuccinMocha::CRUST;
    visuals.faint_bg_color = CatppuccinMocha::MANTLE;
    visuals.window_fill = CatppuccinMocha::BASE;
    visuals.window_stroke = egui::Stroke::new(1.0, CatppuccinMocha::SURFACE1);
    visuals.window_corner_radius = cr8;

    ctx.set_visuals(visuals);

    let mut style = (*ctx.global_style()).clone();
    style.spacing.item_spacing = egui::vec2(8.0, 4.0);
    style.spacing.button_padding = egui::vec2(8.0, 4.0);
    ctx.set_global_style(style);
}
