app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Http
import pf.Sqlite
import pf.Path
import pf.Stdout
import http.Response

Model : {
    list_todos_stmt : Sqlite.Stmt,
    create_todo_stmt : Sqlite.Stmt,
    last_created_todo_stmt : Sqlite.Stmt,
    begin_stmt : Sqlite.Stmt,
    end_stmt : Sqlite.Stmt,
    rollback_stmt : Sqlite.Stmt,
}

program = { init!, respond! }

prepare_stmt! : Path.Path, Str => Try(Sqlite.Stmt, [ServerErr(Str), ..])
prepare_stmt! = |path, query|
    match Sqlite.prepare!({ path, query }) {
        Ok(stmt) => Ok(stmt)
        Err(err) => Err(ServerErr("Failed to prepare Sqlite statement: ${Str.inspect(err)}"))
    }

read_env_var! : Str => Try(Str, [ServerErr(Str), ..])
read_env_var! = |name|
    match Env.var!(name) {
        Ok(value) => Ok(value)
        Err(_) => Err(ServerErr("${name} not set on environment"))
    }

init! : () => Try(Model, _)
init! = || {
    db_path = Path.utf8(read_env_var!("DB_PATH")?)

    list_todos_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos")?
    create_todo_stmt = prepare_stmt!(db_path, "INSERT INTO todos (task, status) VALUES (:task, :status)")?
    last_created_todo_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos WHERE id = last_insert_rowid()")?
    begin_stmt = prepare_stmt!(db_path, "BEGIN")?
    end_stmt = prepare_stmt!(db_path, "END")?
    rollback_stmt = prepare_stmt!(db_path, "ROLLBACK")?

    list_todos_stmt.execute!([])?

    Ok({ list_todos_stmt, create_todo_stmt, last_created_todo_stmt, begin_stmt, end_stmt, rollback_stmt })
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, _| {
    Stdout.line!("hey") ? |err| ServerErr("Failed to write to stdout: ${Str.inspect(err)}")

    Ok(
        Response.from_status(200)
        .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
        .with_body(Str.to_utf8("yow")),
    )
}
