app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.File
import pf.Http
import pf.Sqlite
import pf.Stderr
import pf.Stdout
import http.Response

Model : {}

program = { init!, respond! }

db_path = "issue-104.db"

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            cleanup!() ?? {}
            Stdout.line!("Ran issue 104 regression.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            cleanup!() ?? {}
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    cleanup!()?

    Sqlite.execute!({
        path: db_path,
        query: "CREATE TABLE todos (id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL, status TEXT NOT NULL);",
        bindings: [],
    })?

    Sqlite.execute!({
        path: db_path,
        query: "INSERT INTO todos (task, status) VALUES ('write test', 'todo');",
        bindings: [],
    })?

    list_todos_stmt =
        Sqlite.prepare!({
            path: db_path,
            query: "SELECT id, task, status FROM todos;",
        })?

    match Sqlite.execute_prepared!({ bindings: [], stmt: list_todos_stmt }) {
        Err(RowsReturnedUseQueryInstead) => Ok({})
        other => Err(FailedExpectation("expected execute_prepared! to reject row-returning SQL, got ${Str.inspect(other)}"))
    }
}

cleanup! : () => Try({}, _)
cleanup! = || {
    File.delete!(db_path) ?? {}
    Ok({})
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, _|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
