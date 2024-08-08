use roc_std::{RocList, RocRefcounted, RocStr};

mod http_client;
mod http_server;
mod roc;
mod roc_http;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    let mut server = roc::call_roc_init();

    let mut request = roc_http::RequestToAndFromHost {
        body: RocList::empty(),
        headers: RocList::empty(),
        method: RocStr::from("Get"),
        mime_type: RocStr::from("text/plain"),
        timeout_ms: 0,
        url: RocStr::from("http://localhost:8080"),
    };

    server.inc();
    _ = roc::call_roc_respond(&mut request, &server);

    server.inc();
    _ = roc::call_roc_respond(&mut request, &server);

    server.inc();
    _ = roc::call_roc_respond(&mut request, &server);

    println!("DONE");

    return 0;

    // TODO restore the server
    // http_server::start()
}
