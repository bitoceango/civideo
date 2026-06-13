// Windows release 下不弹控制台窗口
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    childvideo_lib::run()
}
