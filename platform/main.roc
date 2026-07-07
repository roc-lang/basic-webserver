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
            init! : () => Try(model, [Exit(I64), ..]),
            respond! : _, model => Try(_, [ServerErr(Str), ..]),
        }
    }
    exposes [
        Attribute,
        Cmd,
        Dir,
        Env,
        File,
        Html,
        Http,
        IOErr,
        InternalSqlite,
        MultipartFormData,
        Path,
        Sleep,
        Sqlite,
        Stderr,
        Stdout,
        Tcp,
        Url,
        Utc,
    ]
    packages {
        # HTTP data types (Method, Request, Response) come from the shared
        # roc-lang/http package so apps and other packages using it see the same
        # nominal types. The platform supplies the effectful server/client glue.
        http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
        # Pure filesystem path operations come from roc-lang/path; this
        # platform layers effectful filesystem queries on top in Path.roc.
        path: "https://github.com/roc-lang/path/releases/download/1.0.0/8p8iryUUorAFTUDeqYcwc9bFYSwpbVqhYpuHvRAS5Cq4.tar.zst",
    }
    provides {
        "roc_init_for_host": init_for_host!,
        "roc_respond_for_host": respond_for_host!,
    }
    hosted {
        "hosted_cmd_host_exec_exit_code": Host.cmd_exec_exit_code!,
        "hosted_cmd_host_exec_output": Host.cmd_exec_output!,
        "hosted_dir_create": Host.dir_create!,
        "hosted_dir_create_all": Host.dir_create_all!,
        "hosted_dir_delete_all": Host.dir_delete_all!,
        "hosted_dir_delete_empty": Host.dir_delete_empty!,
        "hosted_dir_list": Host.dir_list!,
        "hosted_env_is_windows": Host.env_is_windows!,
        "hosted_env_cwd_unix": Host.env_cwd_unix!,
        "hosted_env_cwd_windows": Host.env_cwd_windows!,
        "hosted_env_exe_path_unix": Host.env_exe_path_unix!,
        "hosted_env_exe_path_windows": Host.env_exe_path_windows!,
        "hosted_env_temp_dir": Host.env_temp_dir!,
        "hosted_env_var": Host.env_var!,
        "hosted_file_delete": Host.file_delete!,
        "hosted_file_is_executable": Host.file_is_executable!,
        "hosted_file_is_readable": Host.file_is_readable!,
        "hosted_file_is_writable": Host.file_is_writable!,
        "hosted_file_read_bytes": Host.file_read_bytes!,
        "hosted_file_read_utf8": Host.file_read_utf8!,
        "hosted_file_size_in_bytes": Host.file_size_in_bytes!,
        "hosted_file_time_accessed": Host.file_time_accessed!,
        "hosted_file_time_created": Host.file_time_created!,
        "hosted_file_time_modified": Host.file_time_modified!,
        "hosted_file_write_bytes": Host.file_write_bytes!,
        "hosted_file_write_utf8": Host.file_write_utf8!,
        "hosted_path_type": Host.path_type!,
        "hosted_stdout_line": Host.stdout_line!,
        "hosted_stdout_write": Host.stdout_write!,
        "hosted_stdout_write_bytes": Host.stdout_write_bytes!,
        "hosted_stderr_line": Host.stderr_line!,
        "hosted_stderr_write": Host.stderr_write!,
        "hosted_stderr_write_bytes": Host.stderr_write_bytes!,
        "hosted_utc_now": Host.utc_now!,
        # SQLite hosted functions are kept at the end so adding them does not
        # renumber the generated glue types for the modules declared above.
        "hosted_sqlite_prepare": Host.sqlite_prepare!,
        "hosted_sqlite_bind": Host.sqlite_bind!,
        "hosted_sqlite_columns": Host.sqlite_columns!,
        "hosted_sqlite_column_value": Host.sqlite_column_value!,
        "hosted_sqlite_step": Host.sqlite_step!,
        "hosted_sqlite_reset": Host.sqlite_reset!,
        # TCP and outbound HTTP are kept after SQLite for the same renumbering
        # reason: appending them adds new glue types without shifting the ones
        # above.
        "hosted_tcp_connect": Host.tcp_connect!,
        "hosted_tcp_read_up_to": Host.tcp_read_up_to!,
        "hosted_tcp_read_exactly": Host.tcp_read_exactly!,
        "hosted_tcp_read_until": Host.tcp_read_until!,
        "hosted_tcp_write": Host.tcp_write!,
        "hosted_http_send_request": Host.http_send_request!,
        "hosted_file_open_reader": Host.file_open_reader!,
        "hosted_file_read_line": Host.file_read_line!,
        "hosted_sleep_millis": Host.sleep_millis!,
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
import Host
import Attribute
import Html
import Http
import IOErr
import Path
import Sleep
import Sqlite
import InternalSqlite
import Stdout
import Stderr
import Tcp
import Url
import Utc
import InternalHttp
import MultipartFormData
import SplitList

init_for_host! : () => Try(Box(Model), I64)
init_for_host! = ||
    match (program.init!)() {
        Ok(model) => Ok(Box.box(model))
        Err(Exit(code)) => Err(code)
        Err(other) => {
            Stderr.line!("Server init! failed with error:\n\n❌ ${Str.inspect(other)}\n") ?? {}
            Err(1)
        }
    }

respond_for_host! : InternalHttp.RequestToAndFromHost, Box(Model) => InternalHttp.ResponseToAndFromHost
respond_for_host! = |request, boxed_model|
    match (program.respond!)(InternalHttp.from_host_request(request), Box.unbox(boxed_model)) {
        Ok(response) => InternalHttp.to_host_response(response)
        Err(ServerErr(msg)) => {
            Stderr.line!("ServerErr: ${msg}") ?? {}
            { status: 500, headers: [], body: [] }
        }
        Err(other) => {
            Stderr.line!("Server error:\n\n❌ ${Str.inspect(other)}\n") ?? {}
            { status: 500, headers: [], body: [] }
        }
    }
