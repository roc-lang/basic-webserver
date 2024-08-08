use roc_std::{roc_dealloc, RocList, RocStr};

mod http_client;
mod http_server;
mod roc;
mod roc_http;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    let (model, captures) = roc::call_roc_init();

    let mut request = roc_http::RequestToAndFromHost {
        body: RocList::empty(),
        headers: RocList::empty(),
        method: RocStr::from("Get"),
        mime_type: RocStr::from("text/plain"),
        timeout_ms: 0,
        url: RocStr::from("http://localhost:8080"),
    };
    _ = roc::call_roc_respond(&mut request, &mut model.clone(), &mut captures.clone());
    _ = roc::call_roc_respond(&mut request, &mut model.clone(), &mut captures.clone());
    _ = roc::call_roc_respond(&mut request, &mut model.clone(), &mut captures.clone());

    println!("DONE");

    return 0;

    // TODO restore the server
    // http_server::start()
}
