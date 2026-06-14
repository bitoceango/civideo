// Android(mobile) 入口：mobile_entry_point 生成 JNI 入口供 Android 包装层调用。
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("启动 Tauri 应用失败");
}
