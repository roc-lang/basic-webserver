app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Sqlite exposing [Stmt]
import pf.Env

Model : { list_todos_stmt: Stmt, create_todo_stmt: Stmt, last_created_todo_stmt: Stmt, begin_stmt: Stmt, end_stmt: Stmt, rollback_stmt: Stmt }

prepare_stmt! : Str, Str => Result Stmt _
prepare_stmt! = |path, query|
    Sqlite.prepare!({path, query})
    |> Result.map_err(|err| ServerErr("Failed to prepare Sqlite statement: ${Inspect.to_str(err)}"))

read_env_var! : Str => Result Str _
read_env_var! = |name|
    Env.var!(name)
    |> Result.map_err(|_| ServerErr("${name} not set on environment"))

init! : {} => Result Model _
init! = |{}|
    db_path = read_env_var!("DB_PATH")?
    list_todos_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos")?
    create_todo_stmt = prepare_stmt!(db_path, "INSERT INTO todos (task, status) VALUES (:task, :status)")?
    last_created_todo_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos WHERE id = last_insert_rowid()")?
    begin_stmt = prepare_stmt!(db_path, "BEGIN")?
    end_stmt = prepare_stmt!(db_path, "END")?
    rollback_stmt = prepare_stmt!(db_path, "ROLLBACK")?

    Sqlite.execute_prepared!({ bindings: [], stmt: list_todos_stmt })?   #**<--  this will crash**

    Ok({ list_todos_stmt, create_todo_stmt, last_created_todo_stmt, begin_stmt, end_stmt, rollback_stmt })

respond! : Request, Model => Result Response _
respond! = |_, _|
    # Print out the results
    Stdout.line!("hey")?

    Ok(
        {
            status: 200,
            headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
            body: Str.to_utf8("yow"),
        },
    )
