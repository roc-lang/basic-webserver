app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Server
import pf.OsStr
import pf.Sqlite
import pf.Path
import pf.Stdout
import http.Response

Context : {
    list_todos_stmt : Sqlite.Stmt,
    create_todo_stmt : Sqlite.Stmt,
    last_created_todo_stmt : Sqlite.Stmt,
    begin_stmt : Sqlite.Stmt,
    end_stmt : Sqlite.Stmt,
    rollback_stmt : Sqlite.Stmt,
}

program = { init!, respond!, shutdown! }

prepare_stmt! : Path.Path, Str => Try(Sqlite.Stmt, [ServerErr(Str), ..])
prepare_stmt! = |path, query|
    match Sqlite.prepare!({ path, query }) {
        Ok(stmt) => Ok(stmt)
        Err(err) => Err(ServerErr("Failed to prepare Sqlite statement: ${Str.inspect(err)}"))
    }

read_env_var! : Str => Try(Path.Path, [ServerErr(Str), ..])
read_env_var! = |name|
    match Env.var!(OsStr.from_str(name)) {
        Ok(value) => Ok(Path.from_os_str(value))
        Err(_) => Err(ServerErr("${name} not set on environment"))
    }

init! : () => Try({ config : Server.Config, context : Context }, _)
init! = || {
    db_path = read_env_var!("DB_PATH")?

    list_todos_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos")?
    create_todo_stmt = prepare_stmt!(db_path, "INSERT INTO todos (task, status) VALUES (:task, :status)")?
    last_created_todo_stmt = prepare_stmt!(db_path, "SELECT id, task, status FROM todos WHERE id = last_insert_rowid()")?
    begin_stmt = prepare_stmt!(db_path, "BEGIN")?
    end_stmt = prepare_stmt!(db_path, "END")?
    rollback_stmt = prepare_stmt!(db_path, "ROLLBACK")?

    list_todos_stmt.execute!([])?

    Ok({
        config: Server.default_config,
        context: { list_todos_stmt, create_todo_stmt, last_created_todo_stmt, begin_stmt, end_stmt, rollback_stmt },
    })
}


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, _state| {
    Stdout.line!("hey") ? |err| ServerErr("Failed to write to stdout: ${Str.inspect(err)}")

    Ok(
        Server.respond(Response.from_status(200)
        .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
        .with_body(Str.to_utf8("yow"))),
    )
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
