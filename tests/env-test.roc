app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Http
import pf.Env
import pf.Path
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            Stdout.line!("Ran all tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    Stdout.line!("Testing Env module functions...\n\nTesting Env.cwd!:")?
    cwd = Env.cwd!()?
    Stdout.line!("cwd: ${Path.display(cwd)}\n\nTesting Env.exe_path!:")?

    exe_path = Env.exe_path!()?
    Stdout.line!("exe_path: ${Path.display(exe_path)}\n\nTesting Env.platform!:")?

    platform_info = Env.platform!()
    Stdout.line!("Current platform:{arch: ${format_arch(platform_info.arch)}, os: ${format_os(platform_info.os)}}\n\nTesting Env.dict!:")?

    env_vars = Env.dict!()
    env_pairs = Dict.to_list(env_vars)
    Stdout.line!("Environment variables count: ${env_pairs.len().to_str()}")?
    Stdout.line!("Sample environment variables:${sample_env_vars(env_vars)}\n\nTesting Env.set_cwd!:")?

    Env.set_cwd!(Path.utf8("examples"))?
    changed_cwd = Env.cwd!()?
    Stdout.line!("Changed current directory to: ${Path.display(changed_cwd)}\n\nTesting Env.temp_dir!:")?

    temp_dir = Env.temp_dir!()
    Stdout.line!("temp_dir: ${Path.display(temp_dir)}\n\nTesting Env.var!:")?

    # A variable that should exist in most environments
    match Env.var!("PATH") {
        Ok(_) => {
            Stdout.line!("PATH variable is set (expected)")?
            {}
        }
        Err(VarNotFound(name)) => {
            Stdout.line!("PATH variable not found: ${name}")?
            {}
        }
    }

    # A variable that should not exist
    match Env.var!("DEFINITELY_NOT_A_REAL_ENV_VAR_123456") {
        Ok(value) => {
            Stdout.line!("Unexpected value: ${value}")?
            {}
        }
        Err(VarNotFound(name)) => {
            Stdout.line!("var not found (expected): ${name}")?
            {}
        }
    }

    Stdout.line!("\nAll tests executed.")
}

format_arch : Env.ARCH -> Str
format_arch = |arch|
    match arch {
        X86 => "X86"
        X64 => "X64"
        ARM => "ARM"
        AARCH64 => "AARCH64"
        OTHER(_) => "OTHER"
    }

format_os : Env.OS -> Str
format_os = |os|
    match os {
        LINUX => "LINUX"
        MACOS => "MACOS"
        WINDOWS => "WINDOWS"
        OTHER(_) => "OTHER"
    }

sample_env_vars : Dict(Str, Str) -> Str
sample_env_vars = |env_vars|
    match Dict.get(env_vars, "PATH") {
        Ok(_) => "[(\"PATH\", \"set\")]"
        Err(_) => "[(\"ENV\", \"set\")]"
    }

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
