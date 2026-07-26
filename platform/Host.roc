import IOErr exposing [IOErr]
import InternalHttp
import InternalSqlite
import OsStr

Host := [].{
	RawEnvVar : {
		name : OsStr.Raw,
		value : OsStr.Raw,
	}

	Cmd : {
		args : List(OsStr.Raw),
		clear_envs : Bool,
		envs : List(RawEnvVar),
		program : OsStr.Raw,
		timeout_ms : U64,
		stdout_limit_bytes : U64,
		stderr_limit_bytes : U64,
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

	Platform : {
		arch : Str,
		os : Str,
	}

	SqliteDb :: Box(U64)

	SqliteStmt :: Box(U64)

	SqliteExec :: Box(U64)

	SqliteTxn :: Box(U64)

	FileReader :: Box(U64)

	TcpStream :: Box(U64)

	RequestBody :: Box(U64)

	RequestBodyRead : [Chunk(List(U8)), End]

	RequestBodyErr : [
		TooLarge({ limit_bytes : U64, received_at_least : U64 }),
		ClientDisconnected,
		InvalidBody(Str),
		RequestFinished,
		ConcurrentRead,
		Cancelled,
	]

	CmdExecErr : [FailedToGetExitCode(IOErr), Timeout, Saturated]

	CmdOutputErr : [
		NonZeroExitCode(CmdOutputFailure),
		FailedToGetExitCode(IOErr),
		Timeout,
		Saturated,
		StdoutTooLarge({ limit_bytes : U64, received_at_least : U64 }),
		StderrTooLarge({ limit_bytes : U64, received_at_least : U64 }),
	]

	cmd_exec_exit_code! : Cmd, [Inherit, Set(OsStr.Raw)] => Try(I32, CmdExecErr)
	cmd_exec_output! : Cmd, [Inherit, Set(OsStr.Raw)] => Try(CmdOutputSuccess, CmdOutputErr)

	dir_create! : RawPath => Try({}, [DirErr(IOErr)])
	dir_create_all! : RawPath => Try({}, [DirErr(IOErr)])
	dir_delete_empty! : RawPath => Try({}, [DirErr(IOErr)])
	dir_delete_all! : RawPath => Try({}, [DirErr(IOErr)])
	dir_list! : RawPath => Try(List(RawPath), [DirErr(IOErr)])

	env_var! : OsStr.Raw => Try(OsStr.Raw, [VarNotFound(OsStr.Raw), EnvErr(IOErr)])
	env_is_windows! : Str => Bool
	env_cwd_unix! : Str => Try(List(U8), [EnvErr(IOErr)])
	env_cwd_windows! : Str => Try(List(U16), [EnvErr(IOErr)])
	env_exe_path_unix! : Str => Try(List(U8), [EnvErr(IOErr)])
	env_exe_path_windows! : Str => Try(List(U16), [EnvErr(IOErr)])
	env_temp_dir! : Str => RawPath
	env_dict! : () => List(RawEnvVar)
	env_current_arch_os! : Str => Platform

	file_read_bytes! : RawPath => Try(List(U8), [FileErr(IOErr)])
	file_write_bytes! : RawPath, List(U8) => Try({}, [FileErr(IOErr)])
	file_read_utf8! : RawPath => Try(Str, [FileErr(IOErr)])
	file_write_utf8! : RawPath, Str => Try({}, [FileErr(IOErr)])
	file_open_reader! : RawPath, U64 => Try(FileReader, [FileErr(IOErr)])
	file_read_line! : FileReader => Try(List(U8), [FileErr(IOErr)])
	file_delete! : RawPath => Try({}, [FileErr(IOErr)])
	file_hard_link! : RawPath, RawPath => Try({}, [FileErr(IOErr)])
	file_rename! : RawPath, RawPath => Try({}, [FileErr(IOErr)])
	file_size_in_bytes! : RawPath => Try(U64, [FileErr(IOErr)])
	file_is_executable! : RawPath => Try(Bool, [FileErr(IOErr)])
	file_is_readable! : RawPath => Try(Bool, [FileErr(IOErr)])
	file_is_writable! : RawPath => Try(Bool, [FileErr(IOErr)])
	file_time_accessed! : RawPath => Try(U128, [FileErr(IOErr)])
	file_time_modified! : RawPath => Try(U128, [FileErr(IOErr)])
	file_time_created! : RawPath => Try(U128, [FileErr(IOErr)])

	http_send_request! : InternalHttp.OutboundRequestToHost => Try(InternalHttp.OutboundResponseFromHost, InternalHttp.SendErr)

	request_body_read! : RequestBody, U64 => Try(RequestBodyRead, RequestBodyErr)
	request_body_read_all! : RequestBody, U64 => Try(List(U8), RequestBodyErr)

	path_type! : RawPath => Try(PathType, IOErr)

	sqlite_open! : RawPath, U64, U64, U64, U64, I64, I64 => Try(SqliteDb, InternalSqlite.SqliteError)
	sqlite_prepare! : SqliteDb, Str => Try(SqliteStmt, InternalSqlite.SqliteError)
	sqlite_start! : SqliteStmt, List(InternalSqlite.SqliteBindings), U64 => Try(SqliteExec, InternalSqlite.SqliteError)
	sqlite_columns! : SqliteStmt => Try(List(Str), InternalSqlite.SqliteError)
	sqlite_next_row! : SqliteExec, U64, Bool => Try(InternalSqlite.SqliteState, InternalSqlite.SqliteError)
	sqlite_begin! : SqliteDb, I64 => Try(SqliteTxn, InternalSqlite.SqliteError)
	sqlite_txn_prepare! : SqliteTxn, Str => Try(SqliteStmt, InternalSqlite.SqliteError)
	sqlite_txn_finish! : SqliteTxn, Bool => Try({}, InternalSqlite.SqliteError)

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

	sleep_millis! : U64 => {}

	utc_now! : () => U128
}
