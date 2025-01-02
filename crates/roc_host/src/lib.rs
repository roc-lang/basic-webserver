mod http_server;
mod roc;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    http_server::start()
}
