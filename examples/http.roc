app "http"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Utc,
        pf.Env,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    handleReq =
        # Log the date, time, method, and url to stdout
        {} <- logRequest req |> Task.await

        # Read TARGET_URL environment variable
        url <- readUrlEnv |> Task.await

        # Fetch the Roc website
        content <- fetchContent url |> Task.await

        # Respond with the website content
        respond 200 content

    # Handle any application errors
    handleReq |> Task.onErr handleErr

AppError : [
    EnvURLNotFound,
    HttpError Http.Error,
]

logRequest : Request -> Task {} AppError
logRequest = \req ->
    dateTime <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await

    Stdout.line "\(dateTime) \(Http.methodToStr req.method) \(req.url)"

readUrlEnv : Task Str AppError
readUrlEnv =
    maybeDbPath <- Env.var "TARGET_URL" |> Task.attempt

    when maybeDbPath is
        Ok url -> Task.ok url
        Err VarNotFound -> Task.err EnvURLNotFound

fetchContent : Str -> Task Str AppError
fetchContent = \url ->
    result <- Http.getUtf8 url |> Task.attempt

    when result is
        Ok content -> Task.ok content
        Err err -> Task.err (HttpError err)

handleErr : AppError -> Task Response []
handleErr = \err ->

    # Build error message
    message =
        when err is
            EnvURLNotFound -> "TARGET_URL environment variable not set"
            HttpError _ -> "Http error fetching content"

    # Log error to stderr
    {} <- Stderr.line "Internal Server Error: \(message)" |> Task.await
    _ <- Stderr.flush |> Task.attempt

    # Respond with Http 500 Error
    Task.ok {
        status: 500,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" },
        ],
        body: Str.toUtf8 "Error 500 Internal Server Error\n",
    }

# Respond with the given status code and body
respond : U16, Str -> Task Response AppError
respond = \code, body ->
    Task.ok {
        status: code,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" },
        ],
        body: Str.toUtf8 body,
    }
