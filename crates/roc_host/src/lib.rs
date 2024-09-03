mod heap;
mod http_client;
mod http_server;
mod json_web_token;
mod roc;
mod roc_http;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    http_server::start()
}
