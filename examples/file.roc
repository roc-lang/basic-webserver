app "file"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.File,
        pf.Path,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Utc,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    path = Path.fromStr "log.txt"

    date <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
    
    # Log request date, method and url to a file
    _ <- File.writeBytes path (Str.toUtf8 "\(date) \(Http.methodToStr req.method) \(req.url)" ) |> Task.attempt

    # Read the file back
    _ <- File.readBytes path |> Task.attempt

    # Delete the file
    _ <- File.delete path |> Task.attempt

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }

