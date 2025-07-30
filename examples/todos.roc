# Webapp for todos using a SQLite 3 database
app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Stdout
import pf.Url
import pf.Utc
import "todos.html" as todo_html : List U8

# To run this example: check the README.md in this folder

Model : {
    list_todos_stmt : Sqlite.Stmt,
    create_todo_stmt : Sqlite.Stmt,
    last_created_todo_stmt : Sqlite.Stmt,
    begin_stmt : Sqlite.Stmt,
    rollback_stmt : Sqlite.Stmt,
    end_stmt : Sqlite.Stmt,
}

init! : {} => Result Model [Exit I32 Str]_
init! = |{}|
    db_path = read_env_var!("DB_PATH")?

    list_todos_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos")?
    create_todo_stmt = prepare_stmt!(db_path, "INSERT INTO todos (task, status) VALUES (:task, :status)")?
    last_created_todo_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos WHERE id = last_insert_rowid()")?
    begin_stmt = prepare_stmt!(db_path, "BEGIN")?
    end_stmt = prepare_stmt!(db_path, "END")?
    rollback_stmt = prepare_stmt!(db_path, "ROLLBACK")?

    Ok({ list_todos_stmt, create_todo_stmt, last_created_todo_stmt, begin_stmt, end_stmt, rollback_stmt })

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |req, model|
    response_task =
        log_request!(req)?

        split_url =
            req.uri
            |> Url.from_str
            |> Url.path
            |> Str.split_on("/")

        # Route to handler based on url path
        when split_url is
            ["", ""] -> byte_response(200, todo_html)
            ["", "todos", ..] -> route_todos!(model, req)
            _ -> text_response(404, "URL Not Found (404)")

    # Handle any application errors
    response_task |> Result.map_err(map_app_err)

AppError : [
    EnvVarNotSet Str,
    StdoutErr Str,
]

map_app_err : AppError -> [ServerErr Str]
map_app_err = |app_err|
    when app_err is
        EnvVarNotSet(var_name) -> ServerErr("Environment variable \"${var_name}\" was not set. Please set it to the path of todos.db")
        StdoutErr(msg) -> ServerErr(msg)

route_todos! : Model, Request => Result Response _
route_todos! = |model, req|
    when req.method is
        GET ->
            list_todos!(model)

        POST ->
            # Create todo
            when task_from_query(req.uri) is
                Ok(props) -> create_todo!(model, props)
                Err(InvalidQuery) -> text_response(400, "Invalid query string, I expected: ?task=foo&status=bar")

        other_method ->
            # Not supported
            text_response(405, "HTTP method ${Inspect.to_str(other_method)} is not supported for the URL ${req.uri}")

list_todos! : Model => Result Response _
list_todos! = |{ list_todos_stmt }|
    result =
        # TODO: it might be nicer if the decoder was stored with the prepared query instead of defined here.
        Sqlite.query_many_prepared!(
            {
                stmt: list_todos_stmt,
                bindings: [],
                # This uses the record builder syntax: https://www.roc-lang.org/examples/RecordBuilder/README.html
                rows: { Sqlite.decode_record <-
                    id: Sqlite.i64("id"),
                    task: Sqlite.str("task"),
                    status: Sqlite.str("status"),
                },
            },
        )

    when result is
        Ok(task) ->
            task
            |> List.map(encode_task)
            |> Str.join_with(",")
            |> |list| "[${list}]"
            |> Str.to_utf8
            |> json_response

        Err(err) ->
            err_response(err)

create_todo! : Model, { task : Str, status : Str } => Result Response _
create_todo! = |model, params|
    result =
        exec_transaction!(
            model,
            |{}|
                # prepare create todo statement
                Sqlite.execute_prepared!(
                    {
                        stmt: model.create_todo_stmt,
                        bindings: [
                            { name: ":task", value: String(params.task) },
                            { name: ":status", value: String(params.status) },
                        ],
                    },
                )?

                # prepare last created todo statement
                Sqlite.query_prepared!(
                    {
                        stmt: model.last_created_todo_stmt,
                        bindings: [],
                        # This uses the record builder syntax: https://www.roc-lang.org/examples/RecordBuilder/README.html
                        row: { Sqlite.decode_record <-
                            id: Sqlite.i64("id"),
                            task: Sqlite.str("task"),
                            status: Sqlite.str("status"),
                        },
                    },
                ),
        )

    when result is
        Ok(task) ->
            task
            |> encode_task
            |> Str.to_utf8
            |> json_response

        Err(err) ->
            err_response(err)

exec_transaction! : Model, ({} => Result ok err) => Result ok _
exec_transaction! = |{ begin_stmt, rollback_stmt, end_stmt }, transaction!|

    # TODO: create a nicer transaction wrapper
    Sqlite.execute_prepared!(
        {
            stmt: begin_stmt,
            bindings: [],
        },
    )
    ? |err| FailedToBeginTransaction(err)

    end_transaction! = |res|
        when res is
            Ok(v) ->
                Sqlite.execute_prepared!(
                    {
                        stmt: end_stmt,
                        bindings: [],
                    },
                )
                ? |err| FailedToEndTransaction(err)

                Ok(v)

            Err(e) ->
                Err(TransactionFailed(e))

    when transaction!({}) |> end_transaction! is
        Ok(v) ->
            Ok(v)

        Err(e) ->
            Sqlite.execute_prepared!(
                {
                    stmt: rollback_stmt,
                    bindings: [],
                },
            )
            ? |err| FailedToRollbackTransaction(err)

            Err(e)

task_from_query : Str -> Result { task : Str, status : Str } [InvalidQuery]
task_from_query = |url|

    params = url |> Url.from_str |> Url.query_params

    when (params |> Dict.get("task"), params |> Dict.get("status")) is
        (Ok(task), Ok(status)) ->
            Ok(
                {
                    task: Str.replace_each(task, "%20", " "),
                    status: Str.replace_each(status, "%20", " "),
                },
            )

        _ -> Err(InvalidQuery)

encode_task : { id : I64, task : Str, status : Str } -> Str
encode_task = |{ id, task, status }|
    # TODO: this should use our json encoder
    """
    {"id":${Num.to_str(id)},"task":"${task}","status":"${status}"}
    """

json_response : List U8 -> Result Response []
json_response = |bytes|
    Ok(
        {
            status: 200,
            headers: [
                { name: "Content-Type", value: "application/json; charset=utf-8" },
            ],
            body: bytes,
        },
    )

err_response : err -> Result Response * where err implements Inspect
err_response = |err|
    byte_response(500, Str.to_utf8(Inspect.to_str(err)))

text_response : U16, Str -> Result Response []
text_response = |status, str|
    Ok(
        {
            status,
            headers: [
                { name: "Content-Type", value: "text/html; charset=utf-8" },
            ],
            body: Str.to_utf8(str),
        },
    )

byte_response : U16, List U8 -> Result Response *
byte_response = |status, bytes|
    Ok(
        {
            status,
            headers: [
                { name: "Content-Type", value: "text/html; charset=utf-8" },
            ],
            body: bytes,
        },
    )

log_request! : Request => Result {} [StdoutErr Str]
log_request! = |req|
    datetime = Utc.to_iso_8601(Utc.now!({}))

    Stdout.line!("${datetime} ${Inspect.to_str(req.method)} ${req.uri}")
    |> Result.map_err(|err| StdoutErr(Inspect.to_str(err)))

read_env_var! : Str => Result Str [EnvVarNotSet Str]_
read_env_var! = |env_var_name|
    Env.var!(env_var_name)
    |> Result.map_err(|_| EnvVarNotSet(env_var_name))

prepare_stmt! : Str, Str => Result Sqlite.Stmt [FailedToPrepareQuery _]
prepare_stmt! = |path, query|
    Sqlite.prepare!({ path, query })
    |> Result.map_err(FailedToPrepareQuery)
