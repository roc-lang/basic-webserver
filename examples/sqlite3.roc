app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.SQLite3
import pf.Env

main : Request -> Task Response []
main = \_ ->

    # Read DB_PATH environment variable
    maybeDbPath <- Env.var "DB_PATH" |> Task.attempt

    # Query todos table
    rows <-
        SQLite3.execute {
            path: maybeDbPath |> Result.withDefault "<DB_PATH> not set on environment",
            query: "SELECT id, task FROM todos WHERE status = :status;",
            bindings: [{ name: ":status", value: "completed" }],
        }
        |> Task.map \rows ->
            # Parse each row into a string
            List.map rows \cols ->
                when cols is
                    [Integer id, String task] -> "row $(Num.toStr id), task: $(task)"
                    _ -> crash "unexpected values returned, expected Integer and String got $(Inspect.toStr cols)"
        |> Task.onErr \err ->
            # Crash on any errors for now
            crash "$(SQLite3.errToStr err)"
        |> Task.await

    body = rows |> Str.joinWith "\n"
    # Print out the results
    Stdout.line! body

    Task.ok {
        status: 200,
        headers: [{ name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" }],
        body: Str.toUtf8 body,
    }
