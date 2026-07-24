//! Roc platform host implementation for basic-webserver, using Roc's
//! direct-symbol host ABI.
//!
//! The root module keeps the staticlib entrypoint small. The ABI module owns
//! Roc host state and shared generated-type aliases; top-level host modules
//! implement the hosted functions declared in platform/main.roc.

#![allow(improper_ctypes_definitions)]

mod abi;
mod cmd;
mod dir;
mod env;
mod file;
mod http;
mod http_error;
mod http_server;
mod os_str;
mod path;
mod request_body;
mod roc_platform_abi;
mod shutdown;
mod sqlite;
mod stdio;
mod tcp;
mod time;

use crate::roc_platform_abi::make_roc_host;

#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(_argc: i32, _argv: *const *const std::ffi::c_char) -> i32 {
    rust_main()
}

pub fn rust_main() -> i32 {
    // Leak the RocHost so the pointer stashed in ABI state stays valid for the
    // whole life of the long-running server.
    let roc_host = Box::leak(Box::new(make_roc_host(core::ptr::null_mut())));
    abi::set_roc_host(roc_host);

    http_server::start()
}
