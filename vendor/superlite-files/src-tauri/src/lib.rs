mod modules;

use modules::fs::*;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_window_state::Builder::new().build())
        .invoke_handler(tauri::generate_handler![
            fs_read_dir,
            fs_stat,
            fs_rename,
            fs_delete,
            fs_mkdir,
            fs_copy,
            fs_move,
            fs_search,
            fs_get_mime,
            fs_get_home,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
