# NOTE: the init exit code is `I64`, not `I32`. Stock roc's `roc glue` mis-sizes
# any aggregate containing an unresolved type variable: the glue size table treats
# an `unknown` (rigid/flex) type as 0 bytes while every backend renders it as an
# 8-byte opaque pointer. With a 4-byte `I32` error that off-by-pointer-width
# surfaces as a wrong size assertion in the generated glue (for the orphan
# `Try(model, [Exit(I32)])` app-contract type); with an 8-byte `I64` the two
# happen to agree and it compiles. The host casts the code back to `i32` for
# `process::exit`. (Root cause: src/glue/glue.zig `getSizeAlignForRepr` .unknown.)
platform "webserver"
    requires {
        [Model : model] for program : {
            init! : {} => Try(model, [Exit(I64), ..]),
            respond! : {
                method : [OPTIONS, GET, POST, PUT, DELETE, HEAD, TRACE, CONNECT, PATCH, EXTENSION(Str)],
                headers : List({ name : Str, value : Str }),
                uri : Str,
                body : List(U8),
                timeout_ms : [TimeoutMilliseconds(U64), NoTimeout],
            }, model => Try(
                {
                    status : U16,
                    headers : List({ name : Str, value : Str }),
                    body : List(U8),
                },
                [ServerErr(Str), ..],
            ),
        }
    }
    exposes [
        Cmd,
        Dir,
        Env,
        File,
        Http,
        IOErr,
        InternalSqlite,
        Path,
        Sqlite,
        Stderr,
        Stdout,
        Utc,
    ]
    packages {}
    provides {
        "roc_init_for_host": init_for_host!,
        "roc_respond_for_host": respond_for_host!,
    }
    hosted {
        "hosted_cmd_host_exec_exit_code": Cmd.host_exec_exit_code!,
        "hosted_cmd_host_exec_output": Cmd.host_exec_output!,
        "hosted_dir_create": Dir.create!,
        "hosted_dir_create_all": Dir.create_all!,
        "hosted_dir_delete_all": Dir.delete_all!,
        "hosted_dir_delete_empty": Dir.delete_empty!,
        "hosted_dir_list": Dir.list!,
        "hosted_env_cwd": Env.cwd!,
        "hosted_env_exe_path": Env.exe_path!,
        "hosted_env_temp_dir": Env.temp_dir!,
        "hosted_env_var": Env.var!,
        "hosted_file_delete": File.delete!,
        "hosted_file_is_executable": File.is_executable!,
        "hosted_file_is_readable": File.is_readable!,
        "hosted_file_is_writable": File.is_writable!,
        "hosted_file_read_bytes": File.read_bytes!,
        "hosted_file_read_utf8": File.read_utf8!,
        "hosted_file_size_in_bytes": File.size_in_bytes!,
        "hosted_file_time_accessed": File.time_accessed!,
        "hosted_file_time_created": File.time_created!,
        "hosted_file_time_modified": File.time_modified!,
        "hosted_file_write_bytes": File.write_bytes!,
        "hosted_file_write_utf8": File.write_utf8!,
        "hosted_path_type": Path.host_path_type!,
        "hosted_stdout_line": Stdout.line!,
        "hosted_stdout_write": Stdout.write!,
        "hosted_stdout_write_bytes": Stdout.write_bytes!,
        "hosted_stderr_line": Stderr.line!,
        "hosted_stderr_write": Stderr.write!,
        "hosted_stderr_write_bytes": Stderr.write_bytes!,
        "hosted_utc_now": Utc.now!,
        # SQLite hosted functions are kept at the end so adding them does not
        # renumber the generated glue types for the modules declared above.
        "hosted_sqlite_prepare": Sqlite.host_prepare!,
        "hosted_sqlite_bind": Sqlite.host_bind!,
        "hosted_sqlite_columns": Sqlite.host_columns!,
        "hosted_sqlite_column_value": Sqlite.host_column_value!,
        "hosted_sqlite_step": Sqlite.host_step!,
        "hosted_sqlite_reset": Sqlite.host_reset!,
    }
    targets: {
        inputs_dir: "targets/",
        x64mac: { inputs: ["libhost.a", app] },
        arm64mac: { inputs: ["libhost.a", app] },
        x64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
        arm64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
        x64win: { inputs: ["host.lib", app] },
        arm64win: { inputs: ["host.lib", app] },
    }

import Cmd
import Dir
import Env
import File
import Http
import IOErr
import Path
import Sqlite
import InternalSqlite
import Stdout
import Stderr
import Utc
import InternalHttp

init_for_host! : {} => Try(Box(Model), I64)
init_for_host! = |{}|
    match (program.init!)({}) {
        Ok(model) => Ok(Box.box(model))
        Err(Exit(code)) => Err(code)
        Err(other) => {
            _ = Stderr.line!("Server init! failed with error:\n\n❌ ${Str.inspect(other)}\n")
            Err(1)
        }
    }

respond_for_host! : InternalHttp.RequestToAndFromHost, Box(Model) => InternalHttp.ResponseToAndFromHost
respond_for_host! = |request, boxed_model|
    match (program.respond!)(InternalHttp.from_host_request(request), Box.unbox(boxed_model)) {
        Ok(response) => InternalHttp.to_host_response(response)
        Err(ServerErr(msg)) => {
            _ = Stderr.line!("ServerErr: ${msg}")
            { status: 500, headers: [], body: [] }
        }
        Err(other) => {
            _ = Stderr.line!("Server error:\n\n❌ ${Str.inspect(other)}\n")
            { status: 500, headers: [], body: [] }
        }
    }
