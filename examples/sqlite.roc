app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Env

Model : { stmt : Sqlite.Stmt }

init! : {} => Result Model _
init! = |{}|
    # Read DB_PATH environment variable
    db_path = Env.var!("DB_PATH") ? |_| ServerErr("DB_PATH not set on environment")

    stmt =
        Sqlite.prepare!(
            {
                path: db_path,
                query: "SELECT id, task FROM todos WHERE status = :status;",
            },
        )
        ? |err| ServerErr("Failed to prepare Sqlite statement: ${Inspect.to_str(err)}")

    Ok({ stmt })

respond! : Request, Model => Result Response _
respond! = |_, { stmt }|
    # Query todos table
    strings : Str
    strings =
        Sqlite.query_many_prepared!(
            {
                stmt,
                bindings: [{ name: ":status", value: String("completed") }],
                rows: { Sqlite.decode_record <-
                    id: Sqlite.i64("id"),
                    task: Sqlite.str("task"),
                },
            },
        )?
        |> List.map(|{ id, task }| "row ${Num.to_str(id)}, task: ${task}")
        |> Str.join_with("\n")

    # Print out the results
    Stdout.line!(strings)?

    Ok(
        {
            status: 200,
            headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
            body: Str.to_utf8(strings),
        },
    )