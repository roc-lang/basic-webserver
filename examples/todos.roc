# Web app for todos using a SQLite 3 database.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Path
import pf.Server
import pf.Sqlite
import pf.Stdout
import pf.Url
import pf.Utc
import http.Response
import "todos.html" as todo_html : List(U8)

# To run this example: check the root README.md.
# Set `DB_PATH` to override the default database path (`./examples/todos.db`).

Context : Path

TodoStatus : [Todo, Planned, Completed, InProgress]

Todo : { id : I64, task : Str, status : TodoStatus }

CreateTodoBody : { task : Str, status : Str }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), FailedToEnsureSchema(_), ..])
init! = || {
	db_path = 
		match Env.var!("DB_PATH") {
			Ok(path) => Path.from_os_str(path)
			Err(_) => Path.utf8("./examples/todos.db")
		}

	ensure_schema!(db_path) ? |err| FailedToEnsureSchema(err)

	Ok({ config: Server.default_config, context: db_path })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, db_path|
	match handle_req!(req, db_path) {
		Ok(response) => Ok(Server.respond(response))
		Err(err) => Err(ServerErr(Str.inspect(err)))
	}

handle_req! : Server.Request, Path => Try(Response, _)
handle_req! = |req, db_path| {
	log_request!(req)?

	request_url = Url.resolve(todo_origin, req.target()) ? InvalidRequestTarget
	path_parts = Str.split_on(Url.path(request_url), "/")

	match path_parts {
		["", ""] => Ok(html_response(200, todo_html))
		["", "todos"] => route_todos!(db_path, req)
		["", "todos", ..] => route_todos!(db_path, req)
		_ => Ok(text_response(404, "URL Not Found (404)"))
	}
}

todo_origin : Url
todo_origin = "http://localhost"

route_todos! : Path, Server.Request => Try(Response, _)
route_todos! = |db_path, req|
	match req.method() {
		GET => list_todos!(db_path)

		POST => create_todo_from_request!(db_path, req)

		other_method =>
			Ok(text_response(405, "HTTP method ${Str.inspect(other_method)} is not supported for ${req.target()}"))
		}

list_todos! : Path => Try(Response, _)
list_todos! = |db_path| {
	todos = 
		Sqlite.query_many!({
			path: db_path,
			query: "SELECT id, task, status FROM todos ORDER BY id;",
			bindings: [],
			rows: decode_todo,
		})
			? |err| DbErr(Str.inspect(err))

	Ok(json_response(todos))
}

create_todo_from_request! : Path, Server.Request => Try(Response, _)
create_todo_from_request! = |db_path, req| {
	body = req.body().with_limit(16 * 1024).read_all!()
		? |err| RequestErr(Str.inspect(err))
	json = 
		match Str.from_utf8(body) {
			Ok(value) => value
			Err(_) => return Ok(text_response(400, "Request body must be valid UTF-8 JSON."))
		}

	decoded_result : Try(CreateTodoBody, [InvalidJson(Str), MissingRequiredField(Str)])
	decoded_result = Json.parse(json)
	decoded = 
		match decoded_result {
			Ok(value) => value
			Err(_) => return Ok(text_response(400, "Expected JSON with string fields \"task\" and \"status\"."))
		}
	status = 
		match parse_todo_status(decoded.status) {
			Ok(value) => value
			Err(_) => return Ok(text_response(400, "Status must be \"todo\", \"planned\", \"completed\", or \"in-progress\"."))
		}

	if Str.is_empty(decoded.task) {
		Ok(text_response(400, "Task must not be empty."))
	} else {
		create_todo!(db_path, { task: decoded.task, status })
	}
}

create_todo! : Path, { task : Str, status : TodoStatus } => Try(Response, _)
create_todo! = |db_path, params| {
	todo = 
		Sqlite.query!({
			path: db_path,
			query: "INSERT INTO todos (task, status) VALUES (:task, :status) RETURNING id, task, status;",
			bindings: [
				{ name: ":task", value: String(params.task) },
				{ name: ":status", value: String(todo_status_to_str(params.status)) },
			],
			row: decode_todo,
		})
			? |err| DbErr(Str.inspect(err))

	Ok(json_response([todo]))
}

# The statement type supplied to row decoders is host-internal, so this top-level
# decoder cannot name its inferred type from application code.
decode_todo = |cols|
	|stmt| {
		id = Sqlite.i64("id")(cols)(stmt)?
		task = Sqlite.str("task")(cols)(stmt)?
		status_str = Sqlite.str("status")(cols)(stmt)?
		status = parse_todo_status(status_str) ? |_| InvalidStoredStatus(status_str)

		Ok({ id, task, status })
	}

parse_todo_status : Str -> Try(TodoStatus, [InvalidTodoStatus])
parse_todo_status = |status|
	match status {
		"todo" => Ok(Todo)
		"planned" => Ok(Planned)
		"completed" => Ok(Completed)
		"in-progress" => Ok(InProgress)
		_ => Err(InvalidTodoStatus)
	}

todo_status_to_str : TodoStatus -> Str
todo_status_to_str = |status|
	match status {
		Todo => "todo"
		Planned => "planned"
		Completed => "completed"
		InProgress => "in-progress"
	}

ensure_schema! : Path => Try({}, _)
ensure_schema! = |db_path|
	Sqlite.execute!({
		path: db_path,
		query: "CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL, status TEXT NOT NULL);",
		bindings: [],
	})

log_request! : Server.Request => Try({}, _)
log_request! = |req| {
	datetime = Utc.to_iso_8601(Utc.now!())
	Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.target()}")
		? |err| StdoutErr(Str.inspect(err))
	Ok({})
}

json_response : List(Todo) -> Response
json_response = |todos| {
	json_todos = todos.map(
		|todo| {
			id: todo.id,
			task: todo.task,
			status: todo_status_to_str(todo.status),
		},
	)

	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "application/json; charset=utf-8" }])
		.with_body(Str.to_utf8(Json.to_str(json_todos)))
}

html_response : U16, List(U8) -> Response
html_response = |status, bytes|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
		.with_body(bytes)

text_response : U16, Str -> Response
text_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
