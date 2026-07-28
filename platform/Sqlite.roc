import InternalSqlite
import InternalPath
import Host
import Path

## Execute bounded SQLite statements with statically dispatched parameter
## encoders and row parsers.
##
## Query parameters are ordinary flat records. Their field names map to SQLite
## parameters with a leading colon, so `{ status }` binds `:status`. Query
## results are selected by the expected Roc type. Structural records derive
## their parser automatically when their fields use supported SQLite types.
##
## Treat `query` as trusted, application-owned SQL. Never interpolate request
## data or other untrusted values into it. Pass data values through `params`,
## which uses SQLite parameter binding rather than manual escaping. Parameters
## cannot represent identifiers or SQL syntax; choose dynamic identifiers and
## clauses from an application-controlled allowlist before constructing a
## query.
##
## ```roc
## Todo : { id : I64, task : Str }
##
## todos : List(Todo)
## db = Sqlite.open!(Sqlite.default_config(db_path))?
## todos = Sqlite.query_many!({
##     db,
##     query: "SELECT id, task FROM todos WHERE status = :status",
##     params: { status: "open" },
##     limits: Sqlite.default_query_limits,
## })?
## ```
##
## SQLite INTEGER maps strictly to `I64`, REAL to `F64`, TEXT to
## `Str`, and BLOB to `Sqlite.Blob`. No text/number coercions are performed.
## TODO: Add derived nullable fields once the compiler can compose their parser
## errors through a platform-defined encoding.
##
## A `Db` owns a bounded host connection pool. Statements are immutable logical
## query descriptors; each execution briefly leases a connection and a cached
## native prepared statement. Executions are safe to use concurrently. Their
## final ARC release resets the native statement and returns the connection on
## every success and error path.
Sqlite :: [].{

	## Configuration for one bounded host-owned connection pool.
	## `max_connections` is 1-64, both timeouts are at most ten minutes, and
	## each connection caches at most 256 native statements.
	Config : {
		path : Path.Path,
		max_connections : U64,
		acquire_timeout_ms : U64,
		busy_timeout_ms : U64,
		max_cached_statements_per_connection : U64,
		journal_mode : JournalMode,
		synchronous : Synchronous,
	}

	## SQLite rollback-journal policy applied and verified on every connection.
	JournalMode : [Delete, Wal]

	## `Full` is the durable default. `Normal` trades power-loss durability for
	## substantially faster commits while preserving database consistency.
	Synchronous : [Full, Normal]

	## Conservative defaults for a conventional web application.
	default_config : Path.Path -> Config
	default_config = |path| {
		path,
		max_connections: 8,
		acquire_timeout_ms: 100,
		busy_timeout_ms: 1_000,
		max_cached_statements_per_connection: 32,
		journal_mode: Wal,
		synchronous: Full,
	}

	## A host-owned SQLite connection pool, safe to retain in immutable context.
	Db :: { host : Host.SqliteDb }.{
		to_inspect : Db -> Str
		to_inspect = |_| "Sqlite.Db(<opaque>)"
	}

	## A raw SQLite value. Most applications use derived record codecs instead.
	Value : [
		Null,
		Real(F64),
		Integer(I64),
		String(Str),
		Bytes(List(U8)),
	]

	## A raw named binding used internally by the derived parameter encoder.
	Binding : {
		name : Str,
		value : Value,
	}

	## Bounds on a materialized query. `max_bytes` covers the host-side SQLite
	## value storage handed to Roc; `max_rows` also bounds per-row record
	## overhead after decoding. `timeout_ms` interrupts SQLite virtual-machine
	## execution; pool acquisition has its own database-level timeout.
	QueryLimits : {
		max_bytes : U64,
		max_rows : U64,
		timeout_ms : U64,
	}

	## Conservative defaults for ordinary request-scoped queries.
	default_query_limits : QueryLimits
	default_query_limits = {
		max_bytes: 16 * 1024 * 1024,
		max_rows: 10_000,
		timeout_ms: 5_000,
	}

	## SQLite's five runtime storage classes, used in decode diagnostics.
	ValueType : [Blob, Integer, Null, Real, Text]

	## Every failure produced by SQLite operations and their derived codecs.
	QueryError : [
		DuplicateColumn(Str),
		ExpectedSingleColumn({ actual : U64 }),
		InvalidValue({ column : Str }),
		MalformedRow,
		MissingRequiredField(Str),
		MultipleValuesForParameter,
		NestedParameterRecord,
		NoRowsReturned,
		ParameterValueMissing(Str),
		ParameterValueOutsideRecord,
		PoolSaturated,
		QueryTimedOut,
		ResourceSaturated,
		ResultTooLarge({ max_bytes : U64 }),
		RowsReturnedUseQueryInstead,
		SqliteErr(ErrCode, Str),
		TooManyRows({ max_rows : U64 }),
		TooManyRowsReturned,
		ConcurrentTransactionUse,
		TransactionFinished,
		UnconsumedColumns,
		UnexpectedType({ actual : ValueType, column : Str, expected : ValueType }),
	]

	## A SQLite BLOB. The nominal wrapper distinguishes blobs from ordinary Roc
	## lists for generic parsing and encoding.
	##
	## TODO: Use `Blob` inside mixed result records once the compiler composes a
	## custom nominal parser's errors with sibling derived fields.
	Blob :: { bytes : List(U8) }.{

		from_bytes : List(U8) -> Blob
		from_bytes = |bytes| Blob.{ bytes }

		to_bytes : Blob -> List(U8)
		to_bytes = |blob| blob.bytes

		parser_for = |encoding| {
			|state| {
				parsed = RowEncoding.parse_bytes(encoding, state)?
				Ok({ value: Blob.{ bytes: parsed.value }, rest: parsed.rest })
			}
		}

		encoder_for : encoding -> (Blob, state -> Try(state, err))
			where [
				encoding.encode_bytes : List(U8), state -> Try(state, err),
			]
		encoder_for = |_encoding| {
			Encoding : encoding

			|blob, state| Encoding.encode_bytes(blob.bytes, state)
		}
	}

	## State used by the derived parameter-record encoder.
	ParamsState : {
		bindings : List(Binding),
		field : [Field(Str), NoField],
		value : [Encoded(Value), NoValue],
	}

	## SQLite named-parameter encoding.
	ParamsEncoding :: [Default].{

		rename_field : ParamsEncoding, Str -> Str
		rename_field = |_, name| name

		encode_record : ParamsState, U64, (ParamsState, (ParamsState, Str, (ParamsState -> Try(ParamsState, QueryError)) -> Try(ParamsState, QueryError)) -> Try(ParamsState, QueryError)) -> Try(ParamsState, QueryError)
		encode_record = |state, _, write_fields|
			match state.field {
				Field(_) => Err(NestedParameterRecord)
				NoField => {
					finished = write_fields(
						state,
						|cursor, name, write_value| {
							encoded = write_value({
								bindings: cursor.bindings,
								field: Field(name),
								value: NoValue,
							})?

							match encoded.value {
								Encoded(value) =>
									Ok({
										bindings: encoded.bindings.append({
											name: Str.concat(":", name),
											value,
										}),
										field: NoField,
										value: NoValue,
									})
								NoValue => Err(ParameterValueMissing(name))
							}
						},
					)?
					Ok(finished)
				}
			}

		encode_str : Str, ParamsState -> Try(ParamsState, QueryError)
		encode_str = |value, state| set_param_value(state, String(value))

		encode_i64 : I64, ParamsState -> Try(ParamsState, QueryError)
		encode_i64 = |value, state| set_param_value(state, Integer(value))

		encode_f64 : F64, ParamsState -> Try(ParamsState, QueryError)
		encode_f64 = |value, state| set_param_value(state, Real(value))

		encode_bytes : List(U8), ParamsState -> Try(ParamsState, QueryError)
		encode_bytes = |value, state| set_param_value(state, Bytes(value))

		encode_null : ParamsState -> Try(ParamsState, QueryError)
		encode_null = |state| set_param_value(state, Null)
	}

	## Pure state used by a compiler-derived SQLite row parser.
	RowState : {
		columns : List(Str),
		current : [Current({ name : Str, value : Value }), NoCurrent],
		next : U64,
		values : List(Value),
	}

	## SQLite row encoding consumed by `parser_for`.
	RowEncoding :: [Default].{

		rename_field : RowEncoding, Str -> Str
		rename_field = |_, name| name

		parse_record_start : RowEncoding, RowState -> Try([Counted({ len : U64, rest : RowState }), Uncounted(RowState)], QueryError)
		parse_record_start = |_, state| Ok(Uncounted(state))

		parse_str : RowEncoding, RowState -> Try({ value : Str, rest : RowState }, QueryError)
		parse_str = |_, state| {
			taken = take_row_value(state)?
			match taken.value {
				String(value) => Ok({ value, rest: taken.rest })
				other => Err(
					UnexpectedType({
						actual: value_type(other),
						column: taken.column,
						expected: Text,
					}),
				)
			}
		}

		parse_i64 : RowEncoding, RowState -> Try({ value : I64, rest : RowState }, QueryError)
		parse_i64 = |_, state| {
			taken = take_row_value(state)?
			match taken.value {
				Integer(value) => Ok({ value, rest: taken.rest })
				other => Err(
					UnexpectedType({
						actual: value_type(other),
						column: taken.column,
						expected: Integer,
					}),
				)
			}
		}

		parse_f64 : RowEncoding, RowState -> Try({ value : F64, rest : RowState }, QueryError)
		parse_f64 = |_, state| {
			taken = take_row_value(state)?
			match taken.value {
				Real(value) => Ok({ value, rest: taken.rest })
				other => Err(
					UnexpectedType({
						actual: value_type(other),
						column: taken.column,
						expected: Real,
					}),
				)
			}
		}

		parse_bytes : RowEncoding, RowState -> Try({ value : List(U8), rest : RowState }, QueryError)
		parse_bytes = |_, state| {
			taken = take_row_value(state)?
			match taken.value {
				Bytes(value) => Ok({ value, rest: taken.rest })
				other => Err(
					UnexpectedType({
						actual: value_type(other),
						column: taken.column,
						expected: Blob,
					}),
				)
			}
		}

		invalid_value : RowEncoding, RowState -> QueryError
		invalid_value = |_, state| {
			column = 
				match state.current {
					Current({ name, .. }) => name
					NoCurrent => state.columns.get(0) ?? ""
				}
			InvalidValue({ column: column })
		}

		parse_record_field : RowEncoding,
		Encoding.FieldName.FieldNames(_shape),
		RowState -> Try(
			[
				Field({ field : Encoding.FieldName(_shape), rest : RowState }),
				TryField({ name : Str, rest : RowState }),
				TryFieldCaseless({ name : Str, rest : RowState }),
				Continue(RowState),
				Done(RowState),
			],
			QueryError,
		)
		parse_record_field = |_, fields, state|
			if state.next >= state.columns.len() {
				Ok(Done(state))
			} else {
				name = state.columns.get(state.next) ? |_| MalformedRow
				value = state.values.get(state.next) ? |_| MalformedRow
				rest = {
					columns: state.columns,
					current: Current({ name, value }),
					next: state.next + 1,
					values: state.values,
				}

				match find_field(fields, name) {
					Ok(field) => Ok(Field({ field, rest }))
					Err(NotFound) =>
						Ok(
							Continue({
								columns: rest.columns,
								current: NoCurrent,
								next: rest.next,
								values: rest.values,
							}),
						)
					}
			}

		parse_record_after_field : RowEncoding, RowState -> Try([Continue(RowState), Done(RowState)], QueryError)
		parse_record_after_field = |_, state|
			if state.next >= state.columns.len() {
				Ok(Done(state))
			} else {
				Ok(Continue(state))
			}

		skip_record_field : RowEncoding, RowState -> Try(RowState, QueryError)
		skip_record_field = |_, state|
			Ok({
				columns: state.columns,
				current: NoCurrent,
				next: state.next,
				values: state.values,
			})
	}

	## Represents a prepared statement that can be executed many times.
	Stmt :: { columns : List(Str), host : Host.SqliteStmt }.{

		to_inspect : Stmt -> Str
		to_inspect = |_| "Sqlite.Stmt(<opaque>)"

		## Execute a prepared statement that must not return rows.
		execute! : Stmt, params => Try({}, QueryError)
			where [
				params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
			]
		execute! = |stmt, params| {
			bindings = encode_params(params)?
			exec = sqlite_start!(stmt_to_host(stmt), bindings, Sqlite.default_query_limits.timeout_ms)?
			match sqlite_next_row!(exec, 0, False) {
				Ok(Done) => Ok({})
				Ok(RowLimitExceeded) => Err(RowsReturnedUseQueryInstead)
				Ok(Row(_)) => Err(RowsReturnedUseQueryInstead)
				Ok(ResultTooLarge) => Err(RowsReturnedUseQueryInstead)
				Err(err) => Err(err)
			}
		}

		## Decode exactly one row as the expected result type.
		query! : Stmt, params, QueryLimits => Try(row, QueryError)
			where [
				params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
				row.parser_for : RowEncoding -> (RowState -> Try({ value : row, rest : RowState }, QueryError)),
			]
		query! = |stmt, params, limits| {
			bindings = encode_params(params)?
			Row : row
			parse_row = Row.parser_for(RowEncoding.Default)
			exec = sqlite_start!(stmt_to_host(stmt), bindings, limits.timeout_ms)?
			decode_exactly_one_row!(exec, stmt.columns, parse_row, limits)
		}

		## Decode all rows as the expected list item type.
		query_many! : Stmt, params, QueryLimits => Try(List(row), QueryError)
			where [
				params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
				row.parser_for : RowEncoding -> (RowState -> Try({ value : row, rest : RowState }, QueryError)),
			]
		query_many! = |stmt, params, limits| {
			bindings = encode_params(params)?
			Row : row
			parse_row = Row.parser_for(RowEncoding.Default)
			exec = sqlite_start!(stmt_to_host(stmt), bindings, limits.timeout_ms)?
			decode_rows!(exec, stmt.columns, parse_row, limits)
		}
	}

	## A transaction pinned to one pooled connection. Dropping its final Roc
	## reference before `commit!` or `rollback!` rolls it back automatically.
	## Operations within one transaction are sequential; overlapping use returns
	## `ConcurrentTransactionUse`.
	Transaction :: { host : Host.SqliteTxn }.{

		to_inspect : Transaction -> Str
		to_inspect = |_| "Sqlite.Transaction(<opaque>)"

		prepare! : Transaction, Str => Try(Stmt, QueryError)
		prepare! = |transaction, query| {
			host = sqlite_txn_prepare!(transaction_to_host(transaction), query)?
			columns = sqlite_columns!(host)?
			validate_unique_columns(columns)?
			Ok(Stmt.{ columns, host })
		}

		execute! : Transaction, { query : Str, params : params } => Try({}, QueryError)
			where [
				params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
			]
		execute! = |transaction, { query, params }| {
			stmt = transaction.prepare!(query)?
			stmt.execute!(params)
		}

		query! : Transaction, { query : Str, params : params, limits : QueryLimits } => Try(row, QueryError)
			where [
				params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
				row.parser_for : RowEncoding -> (RowState -> Try({ value : row, rest : RowState }, QueryError)),
			]
		query! = |transaction, { query, params, limits }| {
			stmt = transaction.prepare!(query)?
			stmt.query!(params, limits)
		}

		query_many! : Transaction, { query : Str, params : params, limits : QueryLimits } => Try(List(row), QueryError)
			where [
				params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
				row.parser_for : RowEncoding -> (RowState -> Try({ value : row, rest : RowState }, QueryError)),
			]
		query_many! = |transaction, { query, params, limits }| {
			stmt = transaction.prepare!(query)?
			stmt.query_many!(params, limits)
		}

		commit! : Transaction => Try({}, QueryError)
		commit! = |transaction| sqlite_txn_finish!(transaction_to_host(transaction), True)

		rollback! : Transaction => Try({}, QueryError)
		rollback! = |transaction| sqlite_txn_finish!(transaction_to_host(transaction), False)
	}

	TransactionMode : [Deferred, Immediate, Exclusive]

	## Represents SQLite result codes.
	ErrCode : [
		Error,
		Internal,
		Perm,
		Abort,
		Busy,
		Locked,
		NoMem,
		ReadOnly,
		Interrupt,
		IOErr,
		Corrupt,
		NotFound,
		Full,
		CanNotOpen,
		Protocol,
		Empty,
		Schema,
		TooBig,
		Constraint,
		Mismatch,
		Misuse,
		NoLFS,
		AuthDenied,
		Format,
		OutOfRange,
		NotADatabase,
		Notice,
		Warning,
		Row,
		Done,
		Unknown(I64),
	]

	## Open and validate a bounded database pool.
	open! : Config => Try(Db, QueryError)
	open! = |config| {
		raw_journal_mode = 
			match config.journal_mode {
				Delete => 0
				Wal => 1
			}
		raw_synchronous = 
			match config.synchronous {
				Full => 0
				Normal => 1
			}
		host = sqlite_open!(
			InternalPath.to_host_raw!(config.path),
			config.max_connections,
			config.acquire_timeout_ms,
			config.busy_timeout_ms,
			config.max_cached_statements_per_connection,
			raw_journal_mode,
			raw_synchronous,
		)?
		Ok(Db.{ host })
	}

	## Prepare a reusable logical statement and cache its result-column metadata.
	prepare! : { db : Db, query : Str } => Try(Stmt, QueryError)
	prepare! = |{ db, query: q }| {
		host = sqlite_prepare!(db_to_host(db), q)?
		columns = sqlite_columns!(host)?
		validate_unique_columns(columns)?
		Ok(Stmt.{ columns, host })
	}

	## Execute a one-shot statement that must not return rows.
	execute! : { db : Db, query : Str, params : params } => Try({}, QueryError)
		where [
			params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
		]
	execute! = |{ db, query: q, params }| {
		stmt = prepare!({ db, query: q })?
		stmt.execute!(params)
	}

	## Execute a one-shot query returning exactly one inferred result value.
	query! : { db : Db, query : Str, params : params, limits : QueryLimits } => Try(row, QueryError)
		where [
			params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
			row.parser_for : RowEncoding -> (RowState -> Try({ value : row, rest : RowState }, QueryError)),
		]
	query! = |{ db, query: q, params, limits }| {
		stmt = prepare!({ db, query: q })?
		stmt.query!(params, limits)
	}

	## Execute a one-shot query returning a list of inferred result values.
	query_many! : { db : Db, query : Str, params : params, limits : QueryLimits } => Try(List(row), QueryError)
		where [
			params.encoder_for : ParamsEncoding -> (params, ParamsState -> Try(ParamsState, QueryError)),
			row.parser_for : RowEncoding -> (RowState -> Try({ value : row, rest : RowState }, QueryError)),
		]
	query_many! = |{ db, query: q, params, limits }| {
		stmt = prepare!({ db, query: q })?
		stmt.query_many!(params, limits)
	}

	## Begin a transaction on one connection leased from the pool.
	begin! : Db, TransactionMode => Try(Transaction, QueryError)
	begin! = |db, mode| {
		raw_mode = 
			match mode {
				Deferred => 0
				Immediate => 1
				Exclusive => 2
			}
		host = sqlite_begin!(db_to_host(db), raw_mode)?
		Ok(Transaction.{ host })
	}

	## Convert an `ErrCode` to a display string.
	errcode_to_str = |code|
		match code {
			Error => "Error: SQL error or missing database"
			Internal => "Internal: Internal logic error in SQLite"
			Perm => "Perm: Access permission denied"
			Abort => "Abort: Callback routine requested an abort"
			Busy => "Busy: The database file is locked"
			Locked => "Locked: A table in the database is locked"
			NoMem => "NoMem: Allocation failed"
			ReadOnly => "ReadOnly: Attempt to write a readonly database"
			Interrupt => "Interrupt: Operation was interrupted"
			IOErr => "IOErr: Disk I/O error"
			Corrupt => "Corrupt: Database image is malformed"
			NotFound => "NotFound: Unknown SQLite operation"
			Full => "Full: Database or disk is full"
			CanNotOpen => "CanNotOpen: Unable to open the database"
			Protocol => "Protocol: Database lock protocol error"
			Empty => "Empty: Database is empty"
			Schema => "Schema: Database schema changed"
			TooBig => "TooBig: String or BLOB exceeds SQLite's limit"
			Constraint => "Constraint: Constraint violation"
			Mismatch => "Mismatch: Data type mismatch"
			Misuse => "Misuse: SQLite API used incorrectly"
			NoLFS => "NoLFS: Required large-file support is unavailable"
			AuthDenied => "AuthDenied: Authorization denied"
			Format => "Format: Auxiliary database format error"
			OutOfRange => "OutOfRange: Parameter index is out of range"
			NotADatabase => "NotADatabase: File is not a database"
			Notice => "Notice: SQLite notice"
			Warning => "Warning: SQLite warning"
			Row => "Row: Another row is ready"
			Done => "Done: Statement execution completed"
			Unknown(value) => "Unknown SQLite result code ${I64.to_str(value)}"
		}
}

stmt_to_host : Sqlite.Stmt -> Host.SqliteStmt
stmt_to_host = |stmt| stmt.host

db_to_host : Sqlite.Db -> Host.SqliteDb
db_to_host = |db| db.host

transaction_to_host : Sqlite.Transaction -> Host.SqliteTxn
transaction_to_host = |transaction| transaction.host

set_param_value = |state, value|
	match state.field {
		NoField => Err(ParameterValueOutsideRecord)
		Field(_) =>
			match state.value {
				NoValue => Ok({
					bindings: state.bindings,
					field: state.field,
					value: Encoded(value),
				})
				Encoded(_) => Err(MultipleValuesForParameter)
			}
		}

encode_params : params -> Try(List({ name : Str, value : [Null, Real(F64), Integer(I64), String(Str), Bytes(List(U8))] }), _)
	where [
		params.encoder_for : Sqlite.ParamsEncoding -> (params, Sqlite.ParamsState -> Try(Sqlite.ParamsState, _)),
	]
encode_params = |params| {
	Params : params
	encode = Params.encoder_for(Sqlite.ParamsEncoding.Default)
	encoded = encode(
		params,
		{
			bindings: [],
			field: NoField,
			value: NoValue,
		},
	)?
	Ok(encoded.bindings)
}

sqlite_open! = |raw_path, max_connections, acquire_timeout_ms, busy_timeout_ms, max_cached_statements, journal_mode, synchronous|
	Host.sqlite_open!(raw_path, max_connections, acquire_timeout_ms, busy_timeout_ms, max_cached_statements, journal_mode, synchronous)
		.map_err(sqlite_host_error)

sqlite_prepare! = |db, query|
	Host.sqlite_prepare!(db, query)
		.map_err(sqlite_host_error)

sqlite_start! = |stmt, bindings, timeout_ms|
	Host.sqlite_start!(stmt, bindings, timeout_ms)
		.map_err(sqlite_host_error)

sqlite_columns! = |stmt|
	Host.sqlite_columns!(stmt)
		.map_err(sqlite_host_error)

sqlite_next_row! = |exec, max_bytes, allow_row|
	Host.sqlite_next_row!(exec, max_bytes, allow_row)
		.map_err(sqlite_host_error)

sqlite_begin! = |db, mode|
	Host.sqlite_begin!(db, mode)
		.map_err(sqlite_host_error)

sqlite_txn_prepare! = |transaction, query|
	Host.sqlite_txn_prepare!(transaction, query)
		.map_err(sqlite_host_error)

sqlite_txn_finish! = |transaction, commit|
	Host.sqlite_txn_finish!(transaction, commit)
		.map_err(sqlite_host_error)

sqlite_host_error = |{ code, message }|
	match code {
		-1 => PoolSaturated
		-2 => QueryTimedOut
		-3 => TransactionFinished
		-4 => ResourceSaturated
		-5 => ConcurrentTransactionUse
		_ => SqliteErr(code_from_i64(code), message)
	}

decode_exactly_one_row! = |stmt, columns, parse_row, limits| {
	first = sqlite_next_row!(stmt, limits.max_bytes, True)?
	match first {
		Done => Err(NoRowsReturned)
		ResultTooLarge => Err(ResultTooLarge({ max_bytes: limits.max_bytes }))
		RowLimitExceeded => Err(NoRowsReturned)
		Row({ bytes: _, values }) => {
			row = parse_materialized_row(columns, values, parse_row)?
			match sqlite_next_row!(stmt, 0, False)? {
				Done => Ok(row)
				RowLimitExceeded => Err(TooManyRowsReturned)
				Row(_) => Err(TooManyRowsReturned)
				ResultTooLarge => Err(TooManyRowsReturned)
			}
		}
	}
}

decode_rows! = |stmt, columns, parse_row, limits| {
	helper! = |out, used_bytes|
		match sqlite_next_row!(
			stmt,
			limits.max_bytes - used_bytes,
			out.len() < limits.max_rows,
		)? {
			Done => Ok(out)
			ResultTooLarge => Err(ResultTooLarge({ max_bytes: limits.max_bytes }))
			RowLimitExceeded => Err(TooManyRows({ max_rows: limits.max_rows }))
			Row({ bytes, values }) => {
				row = parse_materialized_row(columns, values, parse_row)?
				helper!(out.append(row), used_bytes + bytes)
			}
		}
	helper!([], 0)
}

parse_materialized_row = |columns, values, parse_row| {
	if columns.len() != values.len() {
		Err(MalformedRow)
	} else {
		initial : Sqlite.RowState
		initial = {
			columns,
			current: NoCurrent,
			next: 0.U64,
			values,
		}
		parsed = parse_row(initial)?

		if parsed.rest.next == columns.len() {
			match parsed.rest.current {
				NoCurrent => Ok(parsed.value)
				Current(_) => Err(UnconsumedColumns)
			}
		} else {
			Err(UnconsumedColumns)
		}
	}
}

peek_row_value = |state|
	match state.current {
		Current({ name, value }) => Ok({ column: name, value })
		NoCurrent =>
			if state.columns.len() == 1 and state.values.len() == 1 and state.next == 0.U64 {
				name = state.columns.get(0) ? |_| MalformedRow
				value = state.values.get(0) ? |_| MalformedRow
				Ok({ column: name, value })
			} else {
				Err(ExpectedSingleColumn({ actual: state.columns.len() }))
			}
		}

take_row_value = |state| {
	peeked = peek_row_value(state)?
	rest = 
		match state.current {
			Current(_) => {
				columns: state.columns,
				current: NoCurrent,
				next: state.next,
				values: state.values,
			}
			NoCurrent => {
				columns: state.columns,
				current: NoCurrent,
				next: 1,
				values: state.values,
			}
		}
	Ok({ column: peeked.column, rest, value: peeked.value })
}

find_field : Encoding.FieldName.FieldNames(_shape), Str -> Try(Encoding.FieldName(_shape), [NotFound])
find_field = |fields, name| {
	var $remaining = Encoding.FieldName.FieldNames.for_size(fields, Str.count_utf8_bytes(name))

	while True {
		match Iter.next($remaining) {
			One({ item, rest }) =>
				if Encoding.FieldName.name(item) == name {
					return Ok(item)
				} else {
					$remaining = rest
				}
			Skip({ rest }) => {
				$remaining = rest
			}
			Done => return Err(NotFound)
		}
	}
}

validate_unique_columns : List(Str) -> Try({}, [DuplicateColumn(Str), ..])
validate_unique_columns = |columns| {
	var $index = 0
	while $index < columns.len() {
		name = columns.get($index) ?? ""
		var $other = $index + 1
		while $other < columns.len() {
			other_name = columns.get($other) ?? ""
			if name == other_name {
				return Err(DuplicateColumn(name))
			}
			$other = $other + 1
		}
		$index = $index + 1
	}
	Ok({})
}

value_type : [Null, Real(F64), Integer(I64), String(Str), Bytes(List(U8))] -> Sqlite.ValueType
value_type = |value|
	match value {
		Null => Null
		Real(_) => Real
		Integer(_) => Integer
		String(_) => Text
		Bytes(_) => Blob
	}

code_from_i64 : I64 -> Sqlite.ErrCode
code_from_i64 = |code|
	match code {
		0 => Error
		1 => Error
		2 => Internal
		3 => Perm
		4 => Abort
		5 => Busy
		6 => Locked
		7 => NoMem
		8 => ReadOnly
		9 => Interrupt
		10 => IOErr
		11 => Corrupt
		12 => NotFound
		13 => Full
		14 => CanNotOpen
		15 => Protocol
		16 => Empty
		17 => Schema
		18 => TooBig
		19 => Constraint
		20 => Mismatch
		21 => Misuse
		22 => NoLFS
		23 => AuthDenied
		24 => Format
		25 => OutOfRange
		26 => NotADatabase
		27 => Notice
		28 => Warning
		100 => Row
		101 => Done
		other => Unknown(other)
	}

expect {
	encoded = encode_params({ id: 7.I64, name: "todo" })?
	encoded == [
		{ name: ":id", value: Integer(7) },
		{ name: ":name", value: String("todo") },
	]
}

expect {
	encoded = encode_params({ payload: Sqlite.Blob.from_bytes([1, 2, 3]) })?
	encoded == [{ name: ":payload", value: Bytes([1, 2, 3]) }]
}

expect {
	parse_blob = Sqlite.Blob.parser_for(Sqlite.RowEncoding.Default)
	blob = parse_materialized_row(
		["payload"],
		[Bytes([1, 2, 3])],
		parse_blob,
	)?

	Sqlite.Blob.to_bytes(blob) == [1, 2, 3]
}

expect sqlite_host_error({ code: -1, message: "" }) == PoolSaturated

expect sqlite_host_error({ code: -2, message: "" }) == QueryTimedOut

expect sqlite_host_error({ code: -3, message: "" }) == TransactionFinished

expect sqlite_host_error({ code: -4, message: "" }) == ResourceSaturated

expect sqlite_host_error({ code: -5, message: "" }) == ConcurrentTransactionUse
