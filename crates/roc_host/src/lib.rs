mod http_client;
mod http_server;
mod roc;
mod roc_http;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    // let's wire it manually...
    let roc_server_fns = roc::call_roc();

    dbg!("DONE");

    // Prevent Rust from dropping RocServerFns, as its memory is managed by the Roc runtime.
    // This avoids conflicts between Rust's and Roc's memory management.
    std::mem::forget(roc_server_fns);

    return 0;

    // TODO restore the server
    // http_server::start()
}
