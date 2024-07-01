# This example demonstrates error handling and fetching content from another website.
app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Http exposing [Request, Response]
import pf.Utc
import pf.Env

main : Request -> Task Response []
main = \req ->

    handleReq =
        # Log the date, time, method, and url to stdout
        logRequest! req

        # Read environment variable
        url = readEnvVar! "TARGET_URL"

        # Fetch content of url
        content = fetchContent! url

        # Respond with the website content
        respond 200 content

    # Handle any application errors
    handleReq |> Task.onErr handleErr

AppError : [
    EnvVarNotSet Str,
    HttpError Http.Error,
]

logRequest : Request -> Task {} *
logRequest = \req ->
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line "$(datetime) $(Http.methodToStr req.method) $(req.url)"

readEnvVar : Str -> Task Str [EnvVarNotSet Str]
readEnvVar = \envVarName ->
    Env.var envVarName
    |> Task.mapErr \_ -> EnvVarNotSet envVarName

fetchContent : Str -> Task Str [HttpError Http.Error]
fetchContent = \url ->
    Http.getUtf8 url
    |> Task.mapErr \err -> HttpError err

handleErr : AppError -> Task Response *
handleErr = \appErr ->

    # Build error message
    errMsg =
        when appErr is
            EnvVarNotSet envVarName -> "Environment variable \"$(envVarName)\" was not set."
            HttpError err -> "Http error fetching content:\n\t$(Inspect.toStr err)"
    # Log error to stderr
    Stderr.line! "Internal Server Error:\n\t$(errMsg)"
    _ <- Stderr.flush |> Task.attempt

    # Respond with Http 500 Error
    Task.ok {
        status: 500,
        headers: [],
        body: Str.toUtf8 "Internal Server Error.\n",
    }

# Respond with the given status code and body
respond : U16, Str -> Task Response *
respond = \code, body ->
    Task.ok {
        status: code,
        headers: [],
        body: Str.toUtf8 body,
    }
