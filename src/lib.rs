//! Roc platform host implementation for basic-webserver, using Roc's
//! direct-symbol host ABI.
//!
//! The root module keeps the staticlib entrypoint small. The ABI module owns
//! Roc host state and shared generated-type aliases; top-level host modules
//! implement the hosted functions declared in platform/main.roc.

#![allow(improper_ctypes_definitions)]

mod abi;
mod body_sink;
mod bounded_gate;
mod capability;
mod cmd;
mod compression;
mod dir;
mod env;
mod file;
mod file_server;
mod host_resource;
mod http;
mod http_error;
mod http_server;
mod native_router;
mod os_str;
mod path;
mod readiness;
mod request_body;
mod request_limits;
mod request_parts;
mod request_target;
mod response;
mod roc_alloc;
mod roc_platform_abi;
mod server_transport;
mod shutdown;
mod sqlite;
mod stdio;
mod tcp;
mod telemetry;
mod time;

#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(_argc: i32, _argv: *const *const std::ffi::c_char) -> i32 {
    rust_main()
}

pub fn rust_main() -> i32 {
    env::initialize_launch_dir();
    abi::initialize_roc_host();
    let exit_code = http_server::start();
    let live_resources = sqlite::active_resources()
        + file::active_resources()
        + tcp::active_resources()
        + request_parts::active_backings()
        + request_body::metrics().active_bodies
        + request_body::metrics().active_backings
        + readiness::active_resources();
    if live_resources != 0 {
        eprintln!(
            "host resource lifecycle error: {live_resources} native resources remained after \
             shutdown (high-water marks: sqlite={}, file_readers={}, tcp_streams={}, \
             request_backings={}, request_bodies={}, body_backings={}, readiness={})",
            sqlite::resource_high_water(),
            file::resource_high_water(),
            tcp::resource_high_water(),
            request_parts::high_water(),
            request_body::metrics().body_high_water,
            request_body::metrics().backing_high_water,
            readiness::resource_high_water(),
        );
        1
    } else {
        exit_code
    }
}
