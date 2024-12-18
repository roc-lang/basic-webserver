app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.17.0/lZFLstMUCUvd5bjnnpYromZJXkQUrdhbva4xdBInicE.tar.br",
}

import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import cli.Arg.Opt
import cli.Arg.Cli

## Builds the basic-webserver [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc
##
main : Task {} _
main =

    cli_parser =
        Arg.Opt.maybeStr { short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path." }
        |> Arg.Cli.finish {
            name: "basic-webserver-builder",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "Generates all files needed by Roc to use this basic-cli platform.",
        }
        |> Arg.Cli.assertValid

    when Arg.Cli.parseOrDisplayMessage cli_parser (Arg.list! {}) is
        Ok parsed_args -> run parsed_args
        Err err_msg -> Task.err (Exit 1 err_msg)

run : Result Str err -> Task {} _
run = \maybe_roc ->

    # roc_cmd may be a path or just roc
    roc_cmd = maybe_roc |> Result.withDefault "roc"

    roc_version! roc_cmd

    os_and_arch = get_os_and_arch!

    stub_lib_path = "platform/libapp.$(stub_file_extension os_and_arch)"

    build_stub_app_lib! roc_cmd stub_lib_path

    cargo_build_host!

    rust_target_folder = get_rust_target_folder!

    copy_host_lib! os_and_arch rust_target_folder

    preprocess_host! roc_cmd stub_lib_path rust_target_folder

    info! "Successfully built platform files!"

roc_version : Str -> Task {} _
roc_version = \roc_cmd ->

    info! "Checking provided roc; executing `$(roc_cmd) version`:"

    roc_cmd
    |> Cmd.exec ["version"]
    |> Task.mapErr! RocVersionCheckFailed

get_os_and_arch : Task OSAndArch _
get_os_and_arch =

    info! "Getting the native operating system and architecture..."

    Env.platform
    |> Task.await convert_os_and_arch

build_stub_app_lib : Str, Str -> Task {} _
build_stub_app_lib = \roc_cmd, stub_lib_path ->

    info! "Building stubbed app shared library ..."

    roc_cmd
    |> Cmd.exec ["build", "--lib", "platform/libapp.roc", "--output", stub_lib_path, "--optimize"]
    |> Task.mapErr! ErrBuildingAppStub

get_rust_target_folder : Task Str _
get_rust_target_folder =
    when Env.var "CARGO_BUILD_TARGET" |> Task.result! is
        Ok target_env_var ->
            if Str.isEmpty target_env_var then
                Task.ok "target/release/"
            else
                Task.ok "target/$(target_env_var)/release/"

        Err e ->
            info! "Failed to get env var CARGO_BUILD_TARGET with error $(Inspect.toStr e). Assuming default CARGO_BUILD_TARGET (native)..."

            Task.ok "target/release/"

cargo_build_host : Task {} _
cargo_build_host =

    info! "Building rust host ..."

    "cargo"
    |> Cmd.exec ["build", "--release"]
    |> Task.mapErr! ErrBuildingHostBinaries

copy_host_lib : OSAndArch, Str -> Task {} _
copy_host_lib = \os_and_arch, rust_target_folder ->
    host_build_path = "$(rust_target_folder)libhost.a"
    host_dest_path = "platform/$(prebuilt_static_lib_file os_and_arch)"

    info! "Moving the prebuilt binary from $(host_build_path) to $(host_dest_path) ..."
    "cp"
    |> Cmd.exec [host_build_path, host_dest_path]
    |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

OSAndArch : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

convert_os_and_arch : _ -> Task OSAndArch _
convert_os_and_arch = \{ os, arch } ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

stub_file_extension : OSAndArch -> Str
stub_file_extension = \os_and_arch ->
    when os_and_arch is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64 -> "so"
        WindowsX64 | WindowsArm64 -> "dll"

prebuilt_static_lib_file : OSAndArch -> Str
prebuilt_static_lib_file = \os_and_arch ->
    when os_and_arch is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64.a"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

preprocess_host : Str, Str, Str -> Task {} _
preprocess_host = \roc_cmd, stub_lib_path, rust_target_folder ->
    info! "Preprocessing surgical host ..."
    surgical_build_path = "$(rust_target_folder)host"

    roc_cmd
    |> Cmd.exec ["preprocess-host", surgical_build_path, "platform/main.roc", stub_lib_path]
    |> Task.mapErr! ErrPreprocessingSurgicalBinary

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
