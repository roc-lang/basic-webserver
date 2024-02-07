app "echo"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.SQLite3,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    query = 
        """
        CREATE TABLE things (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
        );
        """

    result <- SQLite3.execute "test.db" query |> Task.attempt

    body = when result is 
        Ok {} -> "Success!!"
        Err err -> "Error!! $(SQLite3.errToStr err)" 

    {} <- Stdout.line body |> Task.await

    Task.ok {
        status: 200, 
        headers: [{ name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" }], 
        body: Str.toUtf8 body,
    }