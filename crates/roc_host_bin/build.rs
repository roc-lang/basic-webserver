fn main() {
    println!("cargo:rustc-link-search=crates/roc_host_bin/");

    #[cfg(not(windows))]
    println!("cargo:rustc-link-lib=dylib=app");

    #[cfg(windows)]
    println!("cargo:rustc-link-lib=dylib=libapp");
}
