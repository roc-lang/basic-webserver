## Implements a todo web application backed by a SQLite database.
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

# Set `DB_PATH` to override the default database path (`./examples/todos.db`).

Context : Sqlite.Db

TodoStatus := [Todo, Planned, Completed, InProgress].{
	encoder_for : encoding -> (TodoStatus, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding

		|status, state| Encoding.encode_str(todo_status_to_str(status), state)
	}
}

Todo : { id : I64, task : Str, status : TodoStatus }

# TODO: Decode `Todo` directly once application-defined `parser_for` methods
# compose their validation errors through a platform-derived record parser.
StoredTodo : { id : I64, task : Str, status : Str }

CreateTodoBody : { task : Str, status : Str }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), FailedToEnsureSchema(_), ..])
init! = || {
	db_path = 
		match Env.var!("DB_PATH") {
			Ok(path) => Path.from_os_str(path)
			Err(_) => Path.utf8("./examples/todos.db")
		}

	db = Sqlite.open!(Sqlite.default_config(db_path)) ? |err| FailedToEnsureSchema(err)
	ensure_schema!(db) ? |err| FailedToEnsureSchema(err)

	Ok({ config: Server.default_config, context: db })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, db|
	match handle_req!(req, db) {
		Ok(response) => Ok(Server.respond(response))
		Err(err) => Err(ServerErr(Str.inspect(err)))
	}

handle_req! : Server.Request, Sqlite.Db => Try(Response, _)
handle_req! = |req, db| {
	log_request!(req)?

	request_url = Url.resolve(todo_origin, req.target()) ? InvalidRequestTarget
	path_parts = Str.split_on(Url.path(request_url), "/")

	match path_parts {
		["", ""] => Ok(html_response(200, todo_html))
		["", "todos"] => route_todos!(db, req)
		["", "todos", ..] => route_todos!(db, req)
		_ => Ok(text_response(404, "URL Not Found (404)"))
	}
}

todo_origin : Url
todo_origin = "http://localhost"

route_todos! : Sqlite.Db, Server.Request => Try(Response, _)
route_todos! = |db, req|
	match req.method() {
		GET => list_todos!(db)

		POST => create_todo_from_request!(db, req)

		other_method =>
			Ok(text_response(405, "HTTP method ${Str.inspect(other_method)} is not supported for ${req.target()}"))
		}

list_todos! : Sqlite.Db => Try(Response, _)
list_todos! = |db| {
	stored : List(StoredTodo)
	stored = 
		Sqlite.query_many!({
			db,
			query: "SELECT id, task, status FROM todos ORDER BY id;",
			params: {},
			limits: Sqlite.default_query_limits,
		})
			? |err| DbErr(Str.inspect(err))
	todos = stored.map_try(decode_stored_todo)
		? |err| DbErr(Str.inspect(err))

	Ok(json_response(todos))
}

create_todo_from_request! : Sqlite.Db, Server.Request => Try(Response, _)
create_todo_from_request! = |db, req| {
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
		create_todo!(db, { task: decoded.task, status })
	}
}

create_todo! : Sqlite.Db, { task : Str, status : TodoStatus } => Try(Response, _)
create_todo! = |db, params| {
	stored : StoredTodo
	stored = 
		Sqlite.query!({
			db,
			query: "INSERT INTO todos (task, status) VALUES (:task, :status) RETURNING id, task, status;",
			params: {
				task: params.task,
				# TODO: Pass `params.status` directly once a nested
				# application-defined `encoder_for` receives the field state
				# across the platform boundary.
				status: todo_status_to_str(params.status),
			},
			limits: Sqlite.default_query_limits,
		})
			? |err| DbErr(Str.inspect(err))
	todo = decode_stored_todo(stored)
		? |err| DbErr(Str.inspect(err))

	Ok(json_response([todo]))
}

decode_stored_todo : StoredTodo -> Try(Todo, Sqlite.QueryError)
decode_stored_todo = |stored|
	match parse_todo_status(stored.status) {
		Ok(status) => Ok({ id: stored.id, task: stored.task, status })
		Err(_) => Err(InvalidValue({ column: "status" }))
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

ensure_schema! : Sqlite.Db => Try({}, _)
ensure_schema! = |db|
	Sqlite.execute!({
		db,
		query: "CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL, status TEXT NOT NULL);",
		params: {},
	})

log_request! : Server.Request => Try({}, _)
log_request! = |req| {
	datetime = Utc.to_iso_8601(Utc.now!())
	Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.target()}")
		? |err| StdoutErr(Str.inspect(err))
	Ok({})
}

json_response : List(Todo) -> Response
json_response = |todos|
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "application/json; charset=utf-8" }])
		.with_body(Str.to_utf8(Json.to_str(todos)))

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
