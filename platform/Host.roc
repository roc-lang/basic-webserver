import IOErr exposing [IOErr]
import InternalHttp
import InternalSqlite

Host := [].{
    Cmd : {
        args : List(Str),
        clear_envs : Bool,
        envs : List(Str),
        program : Str,
    }

    CmdOutputSuccess : {
        stderr_bytes : List(U8),
        stdout_bytes : List(U8),
    }

    CmdOutputFailure : {
        stderr_bytes : List(U8),
        stdout_bytes : List(U8),
        exit_code : I32,
    }

    PathType : {
        is_file : Bool,
        is_sym_link : Bool,
        is_dir : Bool,
    }

    RawPath : {
        is_windows : Bool,
        unix_bytes : List(U8),
        windows_u16s : List(U16),
    }

    SqliteStmt :: Box(U64)

    TcpStream :: Box(U64)

    cmd_exec_exit_code! : Cmd => Try(I32, IOErr)
    cmd_exec_output! : Cmd => Try(CmdOutputSuccess, Try(CmdOutputFailure, IOErr))

    dir_create! : Str => Try({}, [DirErr(IOErr)])
    dir_create_all! : Str => Try({}, [DirErr(IOErr)])
    dir_delete_empty! : Str => Try({}, [DirErr(IOErr)])
    dir_delete_all! : Str => Try({}, [DirErr(IOErr)])
    dir_list! : Str => Try(List(RawPath), [DirErr(IOErr)])

    env_var! : Str => Try(Str, [VarNotFound(Str)])
    env_cwd! : Str => Try(Str, [EnvErr(IOErr)])
    env_exe_path! : Str => Try(Str, [EnvErr(IOErr)])
    env_temp_dir! : Str => Str

    file_read_bytes! : Str => Try(List(U8), [FileErr(IOErr)])
    file_write_bytes! : Str, List(U8) => Try({}, [FileErr(IOErr)])
    file_read_utf8! : Str => Try(Str, [FileErr(IOErr)])
    file_write_utf8! : Str, Str => Try({}, [FileErr(IOErr)])
    file_delete! : Str => Try({}, [FileErr(IOErr)])
    file_size_in_bytes! : Str => Try(U64, [FileErr(IOErr)])
    file_is_executable! : Str => Try(Bool, [FileErr(IOErr)])
    file_is_readable! : Str => Try(Bool, [FileErr(IOErr)])
    file_is_writable! : Str => Try(Bool, [FileErr(IOErr)])
    file_time_accessed! : Str => Try(U128, [FileErr(IOErr)])
    file_time_modified! : Str => Try(U128, [FileErr(IOErr)])
    file_time_created! : Str => Try(U128, [FileErr(IOErr)])

    http_send_request! : InternalHttp.RequestToAndFromHost => InternalHttp.ResponseToAndFromHost

    path_type! : RawPath => Try(PathType, IOErr)

    sqlite_prepare! : Str, Str => Try(SqliteStmt, InternalSqlite.SqliteError)
    sqlite_bind! : SqliteStmt, List(InternalSqlite.SqliteBindings) => Try({}, InternalSqlite.SqliteError)
    sqlite_columns! : SqliteStmt => List(Str)
    sqlite_column_value! : SqliteStmt, U64 => Try(InternalSqlite.SqliteValue, InternalSqlite.SqliteError)
    sqlite_step! : SqliteStmt => Try(Bool, InternalSqlite.SqliteError)
    sqlite_reset! : SqliteStmt => Try({}, InternalSqlite.SqliteError)

    stdout_line! : Str => Try({}, [StdoutErr(IOErr)])
    stdout_write! : Str => Try({}, [StdoutErr(IOErr)])
    stdout_write_bytes! : List(U8) => Try({}, [StdoutErr(IOErr)])

    stderr_line! : Str => Try({}, [StderrErr(IOErr)])
    stderr_write! : Str => Try({}, [StderrErr(IOErr)])
    stderr_write_bytes! : List(U8) => Try({}, [StderrErr(IOErr)])

    tcp_connect! : Str, U16 => Try(TcpStream, Str)
    tcp_read_up_to! : TcpStream, U64 => Try(List(U8), Str)
    tcp_read_exactly! : TcpStream, U64 => Try(List(U8), Str)
    tcp_read_until! : TcpStream, U8 => Try(List(U8), Str)
    tcp_write! : TcpStream, List(U8) => Try({}, Str)

    utc_now! : {} => U128
}
