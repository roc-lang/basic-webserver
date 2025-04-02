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
                query: "SELECT * FROM todos;",
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
                bindings: [],
                rows: { Sqlite.decode_record <-
                    id: Sqlite.i64("id"),
                    task: Sqlite.str("task"),
                    status: Sqlite.str("status") |> Sqlite.map_value_result(decode_db_status),
                },
            },
        )?
        |> List.map(|todo| Inspect.to_str(todo))
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

TodoStatus : [Todo, Completed, InProgress]

decode_db_status : Str -> Result TodoStatus _
decode_db_status = |status_str|
    when status_str is
        "todo" -> Ok(Todo)
        "completed" -> Ok(Completed)
        "in-progress" -> Ok(InProgress)
        _ -> Err(ParseError("Unknown status str: ${status_str}"))