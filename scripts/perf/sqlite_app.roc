app [Context, program] {
	pf: platform "../../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Path
import pf.Server
import pf.Sqlite
import http.Response

# Local-only performance application. The fixture is created by
# scripts/sqlite_benchmark.py and is never part of release validation.

Context : { db : Sqlite.Db }

Record : { body : Str, category : Str, id : I64 }

ValueRow : { value : I64 }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	db_path = 
		match Env.var!("SQLITE_BENCH_DB") {
			Ok(path) => Path.from_os_str(path)
			Err(_) => Path.utf8("./target/perf-harness/sqlite-load.db")
		}
	pool_size = 
		match Env.var_str!("SQLITE_BENCH_POOL") {
			Ok(raw) => parse_pool_size(raw) ?? 8
			Err(_) => 8
		}
	db = 
		Sqlite.open!({
			path: db_path,
			max_connections: pool_size,
			acquire_timeout_ms: 100,
			busy_timeout_ms: 1_000,
			max_cached_statements_per_connection: 32,
			journal_mode: Wal,
			synchronous: Normal,
		})
			? |_| Exit(2)
	Ok({
		config: Server.with_limits(
			Server.default_config,
			{
				max_connections: 512,
				max_handlers: 64,
				max_queued_handlers: 64,
			},
		),
		context: { db: db },
	})
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, context|
	match request.target() {
		Resource({ raw_path: "/point", .. }) => point_read!(context.db)
		Resource({ raw_path: "/range-10", .. }) => range_read!(context.db, 10)
		Resource({ raw_path: "/range-1000", .. }) => range_read!(context.db, 1000)
		Resource({ raw_path: "/range-10000", .. }) => range_read!(context.db, 10000)
		Resource({ raw_path: "/range-100000", .. }) => range_read!(context.db, 100000)
		Resource({ raw_path: "/blob-1k", .. }) => blob_read!(context.db, 1)
		Resource({ raw_path: "/blob-64k", .. }) => blob_read!(context.db, 2)
		Resource({ raw_path: "/blob-1m", .. }) => blob_read!(context.db, 3)
		Resource({ raw_path: "/aggregate", .. }) => aggregate_read!(context.db)
		Resource({ raw_path: "/scan", .. }) => scan_read!(context.db)
		Resource({ raw_path: "/write", .. }) => write_counter!(context.db)
		Resource({ raw_path: "/transaction", .. }) => transaction_counter!(context.db)
		_ => Ok(text_outcome(404, "unknown benchmark route"))
	}

point_read! = |db| {
	row : Record
	row = 
		Sqlite.query!({
			db,
			query: "SELECT id, category, body FROM records WHERE id = 125000;",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, "${row.id.to_str()}:${row.category}:${row.body}"))
}

range_read! = |db, limit| {
	query = 
		if limit == 10 {
			"SELECT id, category, body FROM records WHERE id >= 100000 ORDER BY id LIMIT 10;"
		} else if limit == 1000 {
			"SELECT id, category, body FROM records WHERE id >= 100000 ORDER BY id LIMIT 1000;"
		} else if limit == 10000 {
			"SELECT id, category, body FROM records WHERE id >= 100000 ORDER BY id LIMIT 10000;"
		} else {
			"SELECT id, category, body FROM records WHERE id >= 100000 ORDER BY id LIMIT 100000;"
		}
	rows : List(Record)
	rows = 
		Sqlite.query_many!({
			db,
			query,
			params: {},
			limits: {
				max_bytes: 64 * 1024 * 1024,
				max_rows: 100_000,
				timeout_ms: 5_000,
			},
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, rows.len().to_str()))
}

blob_read! : Sqlite.Db, I64 => Try(Server.Outcome, [ServerErr(Str), ..])
blob_read! = |db, id| {
	payload : Sqlite.Blob
	payload = 
		Sqlite.query!({
			db,
			query: "SELECT payload FROM payloads WHERE id = :id;",
			params: {
				id
			},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(Server.respond(Response.from_status(200).with_body(Sqlite.Blob.to_bytes(payload))))
}

aggregate_read! = |db| {
	row : ValueRow
	row = 
		Sqlite.query!({
			db,
			query: "SELECT count(*) AS value FROM records WHERE category = 'category-42';",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, row.value.to_str()))
}

scan_read! = |db| {
	row : ValueRow
	row = 
		Sqlite.query!({
			db,
			query: "SELECT count(*) AS value FROM records WHERE unindexed_text = 'needle';",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, row.value.to_str()))
}

write_counter! = |db| {
	row : ValueRow
	row = 
		Sqlite.query!({
			db,
			query: "UPDATE counters SET value = value + 1 WHERE id = 1 RETURNING value;",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, row.value.to_str()))
}

transaction_counter! = |db| {
	transaction = Sqlite.begin!(db, Immediate)
		? |err| ServerErr(Str.inspect(err))
	row : ValueRow
	row = 
		transaction.query!({
			query: "UPDATE counters SET value = value + 1 WHERE id = 1 RETURNING value;",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	transaction.commit!()
		? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, row.value.to_str()))
}

parse_pool_size = |raw| {
	bytes = Str.to_utf8(raw)
	if bytes.is_empty() or bytes.any(|byte| byte < 48 or byte > 57) {
		Err(InvalidPoolSize)
	} else {
		value = bytes.fold(0, |total, byte| total * 10 + U8.to_u64(byte - 48))
		if value >= 1 and value <= 64 {
			Ok(value)
		} else {
			Err(InvalidPoolSize)
		}
	}
}

text_outcome = |status, body|
	Server.respond(Response.from_status(status).with_body(Str.to_utf8(body)))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
