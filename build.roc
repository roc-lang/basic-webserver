app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.13.0/nW9yMRtZuCYf1Oa9vbE5XoirMwzLbtoSgv7NGhUlqYA.tar.br",
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
## run with: roc ./build.roc
##
main : Task {} _
main =

    cliParser =
        Arg.Opt.maybeStr { short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path."}
        |> Arg.Cli.finish {
            name: "basic-webserver-builder",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "Generates all files needed by Roc to use this basic-cli platform.",
        }
        |> Arg.Cli.assertValid

    when Arg.Cli.parseOrDisplayMessage cliParser (Arg.list! {}) is
        Ok parsedArgs -> run parsedArgs
        Err errMsg -> Task.err (Exit 1 errMsg)

run : Result Str err -> Task {} _
run = \maybeRoc ->

    # rocCmd may be a path or just roc
    rocCmd = maybeRoc |> Result.withDefault "roc"

    rocVersion! rocCmd

    osAndArch = getOSAndArch!

    stubLibPath = "platform/libapp.$(stubFileExtension osAndArch)"

    buildStubAppLib! rocCmd stubLibPath

    cargoBuildHost!

    rustTargetFolder = getRustTargetFolder!

    copyHostLib! osAndArch rustTargetFolder

    preprocessHost! rocCmd stubLibPath rustTargetFolder

    info! "Successfully built platform files!"


rocVersion : Str -> Task {} _
rocVersion = \rocCmd ->

    info! "Checking provided roc; executing `$(rocCmd) version`:"

    rocCmd
        |> Cmd.exec  ["version"]
        |> Task.mapErr! RocVersionCheckFailed

getOSAndArch : Task OSAndArch _
getOSAndArch =

    info! "Getting the native operating system and architecture..."

    Env.platform
    |> Task.await convertOSAndArch

buildStubAppLib : Str, Str -> Task {} _
buildStubAppLib = \rocCmd, stubLibPath ->

    info! "Building stubbed app shared library ..."

    rocCmd
        |> Cmd.exec  ["build", "--lib", "platform/libapp.roc", "--output", stubLibPath, "--optimize"]
        |> Task.mapErr! ErrBuildingAppStub

getRustTargetFolder : Task Str _
getRustTargetFolder =
    when Env.var "CARGO_BUILD_TARGET" |> Task.result! is
        Ok targetEnvVar ->
            if Str.isEmpty targetEnvVar then
                Task.ok "target/release/"
            else
                Task.ok "target/$(targetEnvVar)/release/"
        Err e -> 
            info! "Failed to get env var CARGO_BUILD_TARGET with error \(Inspect.toStr e). Assuming default CARGO_BUILD_TARGET (native)..."
            
            Task.ok "target/release/"

cargoBuildHost : Task {} _
cargoBuildHost =

    info! "Building rust host ..."

    "cargo"
        |> Cmd.exec ["build", "--release"]
        |> Task.mapErr! ErrBuildingHostBinaries

copyHostLib : OSAndArch, Str -> Task {} _
copyHostLib = \osAndArch, rustTargetFolder ->
    hostBuildPath = "$(rustTargetFolder)libhost.a"
    hostDestPath = "platform/$(prebuiltStaticLibFile osAndArch)"

    info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."
    "cp"
        |> Cmd.exec  [hostBuildPath, hostDestPath]
        |> Task.mapErr! ErrMovingPrebuiltLegacyBinary


OSAndArch : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

convertOSAndArch : _ -> Task OSAndArch _
convertOSAndArch =\{os, arch} ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

stubFileExtension : OSAndArch -> Str
stubFileExtension = \osAndArch ->
    when osAndArch is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64-> "so"
        WindowsX64| WindowsArm64 -> "dll"

prebuiltStaticLibFile : OSAndArch -> Str
prebuiltStaticLibFile = \osAndArch ->
    when osAndArch is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64.a"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

preprocessHost : Str, Str, Str -> Task {} _
preprocessHost = \rocCmd, stubLibPath, rustTargetFolder ->
    info! "Preprocessing surgical host ..."
    surgicalBuildPath = "$(rustTargetFolder)host"

    rocCmd
        |> Cmd.exec  ["preprocess-host", surgicalBuildPath, "platform/main.roc", stubLibPath]
        |> Task.mapErr! ErrPreprocessingSurgicalBinary

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
