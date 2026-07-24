# Host-ABI types shared between the SQLite host functions and the Sqlite module.
# These map 1:1 to the generated Rust glue types in src/roc_platform_abi.rs.
InternalSqlite :: [].{
	SqliteError : {
		code : I64,
		message : Str,
	}

	SqliteValue : [
		Null,
		Real(F64),
		Integer(I64),
		String(Str),
		Bytes(List(U8)),
	]

	SqliteState : [
		Done,
		ResultTooLarge,
		Row({ bytes : U64, values : List(SqliteValue) }),
		RowLimitExceeded,
	]

	SqliteBindings : {
		name : Str,
		value : SqliteValue,
	}
}
