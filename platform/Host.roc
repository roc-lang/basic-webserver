hosted Host
    exposes [
        TcpStream,
        FileReader,
        InternalIOErr,
        args!,
        dir_list!,
        dir_create!,
        dir_create_all!,
        dir_delete_empty!,
        dir_delete_all!,
        hard_link!,
        env_dict!,
        env_var!,
        cwd!,
        set_cwd!,
        exe_path!,
        stdout_line!,
        stdout_write!,
        stdout_write_bytes!,
        stderr_line!,
        stderr_write!,
        stderr_write_bytes!,
        tty_mode_canonical!,
        tty_mode_raw!,
        send_request!,
        file_delete!,
        file_exists!,
        file_read_bytes!,
        file_reader!,
        file_read_line!,
        file_size_in_bytes!,
        file_write_bytes!,
        file_write_utf8!,
        file_is_executable!,
        file_is_readable!,
        file_is_writable!,
        file_time_accessed!,
        file_time_modified!,
        file_time_created!,
        file_rename!,
        path_type!,
        posix_time!,
        tcp_connect!,
        tcp_read_up_to!,
        tcp_read_exactly!,
        tcp_read_until!,
        tcp_write!,
        sleep_millis!,
        command_exec_output!,
        command_exec_exit_code!,
        current_arch_os!,
        temp_dir!,
        get_locale!,
        get_locales!,
        sqlite_prepare!,
        sqlite_bind!,
        sqlite_columns!,
        sqlite_column_value!,
        sqlite_step!,
        sqlite_reset!,
    ]
    imports []

import InternalHttp
import InternalCmd
import InternalIOErr
import InternalPath
import InternalSqlite

InternalIOErr : {
    tag : [
        EndOfFile,
        NotFound,
        PermissionDenied,
        BrokenPipe,
        AlreadyExists,
        Interrupted,
        Unsupported,
        OutOfMemory,
        Other,
    ],
    msg : Str,
}

# COMMAND
command_exec_exit_code! : InternalCmd.Command => Result I32 InternalIOErr.IOErrFromHost
command_exec_output! : InternalCmd.Command => Result InternalCmd.OutputFromHostSuccess (Result InternalCmd.OutputFromHostFailure InternalIOErr.IOErrFromHost)

# FILE
file_write_bytes! : List U8, List U8 => Result {} InternalIOErr.IOErrFromHost
file_write_utf8! : List U8, Str => Result {} InternalIOErr.IOErrFromHost
file_delete! : List U8 => Result {} InternalIOErr.IOErrFromHost
file_read_bytes! : List U8 => Result (List U8) InternalIOErr.IOErrFromHost
file_size_in_bytes! : List U8 => Result U64 InternalIOErr.IOErrFromHost
file_exists! : List U8 => Result Bool InternalIOErr.IOErrFromHost
file_is_executable! : List U8 => Result Bool InternalIOErr.IOErrFromHost
file_is_readable! : List U8 => Result Bool InternalIOErr.IOErrFromHost
file_is_writable! : List U8 => Result Bool InternalIOErr.IOErrFromHost
file_time_accessed! : List U8 => Result U128 InternalIOErr.IOErrFromHost
file_time_modified! : List U8 => Result U128 InternalIOErr.IOErrFromHost
file_time_created! : List U8 => Result U128 InternalIOErr.IOErrFromHost
file_rename! : List U8, List U8 => Result {} InternalIOErr.IOErrFromHost
FileReader := Box {}
file_reader! : List U8, U64 => Result FileReader InternalIOErr
file_read_line! : FileReader => Result (List U8) InternalIOErr

dir_list! : List U8 => Result (List (List U8)) InternalIOErr.IOErrFromHost
dir_create! : List U8 => Result {} InternalIOErr.IOErrFromHost
dir_create_all! : List U8 => Result {} InternalIOErr.IOErrFromHost
dir_delete_empty! : List U8 => Result {} InternalIOErr.IOErrFromHost
dir_delete_all! : List U8 => Result {} InternalIOErr.IOErrFromHost

hard_link! : List U8, List U8 => Result {} InternalIOErr.IOErrFromHost
path_type! : List U8 => Result InternalPath.InternalPathType InternalIOErr.IOErrFromHost
cwd! : {} => Result (List U8) {}
temp_dir! : {} => List U8

# STDIO
stdout_line! : Str => Result {} InternalIOErr.IOErrFromHost
stdout_write! : Str => Result {} InternalIOErr.IOErrFromHost
stdout_write_bytes! : List U8 => Result {} InternalIOErr.IOErrFromHost
stderr_line! : Str => Result {} InternalIOErr.IOErrFromHost
stderr_write! : Str => Result {} InternalIOErr.IOErrFromHost
stderr_write_bytes! : List U8 => Result {} InternalIOErr.IOErrFromHost

# TCP
send_request! : InternalHttp.RequestToAndFromHost => InternalHttp.ResponseToAndFromHost

TcpStream := Box {}
tcp_connect! : Str, U16 => Result TcpStream Str
tcp_read_up_to! : TcpStream, U64 => Result (List U8) Str
tcp_read_exactly! : TcpStream, U64 => Result (List U8) Str
tcp_read_until! : TcpStream, U8 => Result (List U8) Str
tcp_write! : TcpStream, List U8 => Result {} Str

# OTHERS
current_arch_os! : {} => { arch : Str, os : Str }

get_locale! : {} => Result Str {}
get_locales! : {} => List Str

posix_time! : {} => U128 # TODO why is this a U128 but then getting converted to a I128 in Utc.roc?

sleep_millis! : U64 => {}

tty_mode_canonical! : {} => {}
tty_mode_raw! : {} => {}

env_dict! : {} => List (Str, Str)
env_var! : Str => Result Str {}
exe_path! : {} => Result (List U8) {}
set_cwd! : List U8 => Result {} {}

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args! : {} => List Str

# SQLITE
sqlite_prepare! : Str, Str => Result (Box {}) InternalSqlite.SqliteError
sqlite_bind! : Box {}, List InternalSqlite.SqliteBindings => Result {} InternalSqlite.SqliteError
sqlite_columns! : Box {} => List Str
sqlite_column_value! : Box {}, U64 => Result InternalSqlite.SqliteValue InternalSqlite.SqliteError
sqlite_step! : Box {} => Result InternalSqlite.SqliteState InternalSqlite.SqliteError
sqlite_reset! : Box {} => Result {} InternalSqlite.SqliteError
