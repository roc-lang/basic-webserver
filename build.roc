app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.13.0/zsDHOdxyAcj6EhyNZx_3qhIICVlnho-OZ5X2lFDLi0k.tar.br",
}

import cli.Task exposing [Task]
import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import cli.Arg.Opt
import cli.Arg.Cli

## Builds the basic-webserver [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc --release
##
main : Task {} _
main =

    rawArgs = Arg.list! {}

    cliParser =
        { Arg.Cli.combine <-
            release: Arg.Opt.flag { short: "r", long: "release", help: "Release build. Passes `--release` to `cargo build`." },
            maybeRoc: Arg.Opt.maybeStr { short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path."},
        }
        |> Arg.Cli.finish {
            name: "basic-webserver-builder",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "Generates all files needed by Roc to use this basic-cli platform.",
        }
        |> Arg.Cli.assertValid

    when Arg.Cli.parseOrDisplayMessage cliParser rawArgs is
        Ok parsedArgs -> run parsedArgs
        Err errMsg -> Task.err (Exit 1 errMsg)

run = \{ release, maybeRoc } ->

    roc = maybeRoc |> Result.withDefault "roc"

    info! "Getting the native target ..."
    target =
        Env.platform
        |> Task.await! getNativeTarget

    stubPath = "platform/libapp.$(stubExt target)"

    info! "Building stubbed app shared library ..."
    roc
        |> Cmd.exec  ["build", "--lib", "platform/libapp.roc", "--output", stubPath]
        |> Task.mapErr! ErrBuildingAppStub

    (cargoBuildArgs, message) =
        if release then
            (["build", "--release"], "Building host in RELEASE mode ...")
        else
            (["build"], "Building host in DEBUG mode ...")

    info! message
    "cargo"
        |> Cmd.exec  cargoBuildArgs
        |> Task.mapErr! ErrBuildingHostBinaries

    hostBuildPath = if release then "target/release/libhost.a" else "target/debug/libhost.a"
    hostDestPath = "platform/$(prebuiltStaticLibrary target)"

    info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."
    "cp"
        |> Cmd.exec  [hostBuildPath, hostDestPath]
        |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

    info! "Preprocessing surgical host ..."
    surgicalBuildPath = if release then "target/release/host" else "target/debug/host"
    roc
        |> Cmd.exec  ["preprocess-host", surgicalBuildPath, "platform/main.roc", stubPath]
        |> Task.mapErr! ErrPreprocessingSurgicalBinary

    info! "Successfully completed building platform binaries."

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

getNativeTarget : _ -> Task RocTarget _
getNativeTarget =\{os, arch} ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

stubExt : RocTarget -> Str
stubExt = \target ->
    when target is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64-> "so"
        WindowsX64| WindowsArm64 -> "dll"

prebuiltStaticLibrary : RocTarget -> Str
prebuiltStaticLibrary = \target ->
    when target is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64.a"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
