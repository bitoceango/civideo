pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("启动 Tauri 应用失败");
}
