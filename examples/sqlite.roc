## Queries completed todos from SQLite and serves their inspected records.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sqlite
import pf.Env
import pf.Path
import http.Response

# Set `DB_PATH` to choose a database; otherwise this uses
# `./examples/todos.db`. The database must already contain this table:
#
# CREATE TABLE todos (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     task TEXT NOT NULL,
#     status TEXT NOT NULL
# );

# The path is resolved once during `init!` and stored as immutable context.
Context : { db_path : Path }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	db_path = 
		match Env.var!("DB_PATH") {
			Ok(path) => Path.from_os_str(path)
			Err(_) => Path.utf8("./examples/todos.db")
		}
	Ok({ config: Server.default_config, context: { db_path: db_path } })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, { db_path }| {
	match query_todos_by_status!(db_path, Completed) {
		Ok(todos) => {
			lines = todos.map(|todo| Str.inspect(todo))
			body = Str.join_with(lines, "\n")
			response = 
				Response.from_status(200)
					.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
					.with_body(Str.to_utf8(body))
			Ok(Server.respond(response))
		}
		Err(err) => Err(ServerErr("Failed to query Sqlite: ${Str.inspect(err)}"))
	}
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})

Todo : { id : I64, status : TodoStatus, task : Str }

# TODO: Decode `Todo` directly once application-defined `parser_for` methods
# compose their validation errors through a platform-derived record parser.
StoredTodo : { id : I64, status : Str, task : Str }

query_todos_by_status! : Path, TodoStatus => Try(List(Todo), Sqlite.QueryError)
query_todos_by_status! = |db_path, status| {
	stored : List(StoredTodo)
	stored = Sqlite.query_many!({
		path: db_path,
		query: "SELECT id, task, status FROM todos WHERE status = :status;",
		# TODO: Pass `status` directly once a nested application-defined
		# `encoder_for` receives the field state across the platform boundary.
		params: { status: todo_status_to_str(status) },
		limits: Sqlite.default_query_limits,
	})?

	stored.map_try(
		|todo|
			match parse_todo_status(todo.status) {
				Ok(decoded_status) => Ok({ id: todo.id, status: decoded_status, task: todo.task })
				Err(_) => Err(InvalidValue({ column: "status" }))
			},
	)
}

TodoStatus := [Todo, Planned, Completed, InProgress].{}

todo_status_to_str : TodoStatus -> Str
todo_status_to_str = |status|
	match status {
		Todo => "todo"
		Planned => "planned"
		Completed => "completed"
		InProgress => "in-progress"
	}

parse_todo_status : Str -> Try(TodoStatus, [InvalidTodoStatus])
parse_todo_status = |status_str|
	match status_str {
		"todo" => Ok(Todo)
		"planned" => Ok(Planned)
		"completed" => Ok(Completed)
		"in-progress" => Ok(InProgress)
		_ => Err(InvalidTodoStatus)
	}
