app [Context, program] {
	pf: platform "../../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Path
import pf.Server
import pf.Sqlite
import http.Response

# Isolated local-only application for measuring contention on one prepared
# statement retained in immutable application context.

Context : { shared_point : Sqlite.Stmt }

Record : { body : Str, category : Str, id : I64 }

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
	shared_point =
		Sqlite.prepare!({
			db,
			query: "SELECT id, category, body FROM records WHERE id = 125000;",
		})
			? |_| Exit(2)

	Ok({
		config: Server.with_limits(
			Server.default_config,
			{
				max_connections: 128,
				max_handlers: 64,
				max_queued_handlers: 64,
			},
		),
		context: { shared_point: shared_point },
	})
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, context| {
	row : Record
	row =
		context.shared_point.query!({}, Sqlite.default_query_limits)
			? |err| ServerErr(Str.inspect(err))
	body = "${row.id.to_str()}:${row.category}:${row.body}"
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(body))))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})

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
