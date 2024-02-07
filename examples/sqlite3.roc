app "echo"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.SQLite3,
        pf.Env,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    # Read DB_PATH environment variable
    maybeDbPath <- Env.var "DB_PATH" |> Task.attempt

    # Query todos table
    result <-
        SQLite3.execute {
            path: maybeDbPath |> Result.withDefault "<DB_PATH> not set on environment",
            query: "SELECT * FROM todos WHERE status = :status;",
            bindings: [{name : ":status", value : "completed"}],
        }
        |> Task.attempt

    # Print out the results
    body =
        when result is
            Ok rows -> "$(Inspect.toStr rows)"
            Err err -> crash "$(SQLite3.errToStr err)"

    {} <- Stdout.line body |> Task.await

    Task.ok {
        status: 200,
        headers: [{ name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" }],
        body: Str.toUtf8 body,
    }
