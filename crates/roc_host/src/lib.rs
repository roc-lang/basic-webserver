mod http_client;
mod http_server;
mod roc;
mod roc_http;
mod roc_sql;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    http_server::start()
}
