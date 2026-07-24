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

Context : { db_path : Path }

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
	Ok({
		config: Server.with_limits(
			Server.default_config,
			{
				max_connections: 512,
				max_handlers: 64,
				max_queued_handlers: 64,
			},
		),
		context: { db_path: db_path },
	})
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, context|
	match request.target() {
		"/point" => point_read!(context.db_path)
		"/range-10" => range_read!(context.db_path, 10)
		"/range-1000" => range_read!(context.db_path, 1000)
		"/range-10000" => range_read!(context.db_path, 10000)
		"/range-100000" => range_read!(context.db_path, 100000)
		"/blob-1k" => blob_read!(context.db_path, 1)
		"/blob-64k" => blob_read!(context.db_path, 2)
		"/blob-1m" => blob_read!(context.db_path, 3)
		"/aggregate" => aggregate_read!(context.db_path)
		"/scan" => scan_read!(context.db_path)
		"/write" => write_counter!(context.db_path)
		_ => Ok(text_outcome(404, "unknown benchmark route"))
	}

point_read! = |db_path| {
	row : Record
	row = 
		Sqlite.query!({
			path: db_path,
			query: "SELECT id, category, body FROM records WHERE id = 125000;",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, "${row.id.to_str()}:${row.category}:${row.body}"))
}

range_read! = |db_path, limit| {
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
			path: db_path,
			query,
			params: {},
			limits: {
				max_bytes: 64 * 1024 * 1024,
				max_rows: 100_000,
			},
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, rows.len().to_str()))
}

blob_read! : Path, I64 => Try(Server.Outcome, [ServerErr(Str), ..])
blob_read! = |db_path, id| {
	payload : Sqlite.Blob
	payload = 
		Sqlite.query!({
			path: db_path,
			query: "SELECT payload FROM payloads WHERE id = :id;",
			params: {
				id
			},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(Server.respond(Response.from_status(200).with_body(Sqlite.Blob.to_bytes(payload))))
}

aggregate_read! = |db_path| {
	row : ValueRow
	row = 
		Sqlite.query!({
			path: db_path,
			query: "SELECT count(*) AS value FROM records WHERE category = 'category-42';",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, row.value.to_str()))
}

scan_read! = |db_path| {
	row : ValueRow
	row = 
		Sqlite.query!({
			path: db_path,
			query: "SELECT count(*) AS value FROM records WHERE unindexed_text = 'needle';",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, row.value.to_str()))
}

write_counter! = |db_path| {
	row : ValueRow
	row = 
		Sqlite.query!({
			path: db_path,
			query: "UPDATE counters SET value = value + 1 WHERE id = 1 RETURNING value;",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| ServerErr(Str.inspect(err))
	Ok(text_outcome(200, row.value.to_str()))
}

text_outcome = |status, body|
	Server.respond(Response.from_status(status).with_body(Str.to_utf8(body)))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
