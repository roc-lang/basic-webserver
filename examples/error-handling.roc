# This example demonstrates error handling and fetching content from another website.
app "error-handling"
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

        # Read environment variable
        url <- readEnvVar "TARGET_URL" |> Task.await

        # Fetch content of url
        content <- fetchContent url |> Task.await

        # Respond with the website content
        respond 200 content

    # Handle any application errors
    handleReq |> Task.onErr handleErr

AppError : [
    EnvVarNotSet Str,
    HttpError Http.Error,
]

logRequest : Request -> Task {} AppError
logRequest = \req ->
    dateTime <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await

    Stdout.line "$(dateTime) $(Http.methodToStr req.method) $(req.url)"

readEnvVar : Str -> Task Str AppError
readEnvVar = \envVarName ->
    Env.var envVarName 
    |> Task.mapErr \_ -> EnvVarNotSet envVarName

fetchContent : Str -> Task Str AppError
fetchContent = \url ->
    Http.getUtf8 url
    |> Task.mapErr \err -> HttpError err

handleErr : AppError -> Task Response []
handleErr = \appErr ->

    # Build error message
    errMsg =
        when appErr is
            EnvVarNotSet envVarName -> "Environment variable \"$(envVarName)\" was not set."
            HttpError err -> "Http error fetching content:\n\t$(Inspect.toStr err)"

    # Log error to stderr
    {} <- Stderr.line "Internal Server Error:\n\t$(errMsg)" |> Task.await
    _ <- Stderr.flush |> Task.attempt

    # Respond with Http 500 Error
    Task.ok {
        status: 500,
        headers: [],
        body: Str.toUtf8 "Internal Server Error.\n",
    }

# Respond with the given status code and body
respond : U16, Str -> Task Response AppError
respond = \code, body ->
    Task.ok {
        status: code,
        headers: [],
        body: Str.toUtf8 body,
    }
