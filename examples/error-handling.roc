# This example demonstrates error handling and fetching content from another website.
app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Utc
import pf.Env

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, _ ->
    handleReq =
        # Log the date, time, method, and url to stdout
        logRequest! req

        # Read environment variable
        url = readEnvVar! "TARGET_URL"

        # Fetch content of url
        content = fetchContent! url

        # Respond with the website content
        responseWithCode 200 content

    # Handle any application errors
    handleReq |> Task.onErr handleErr

AppError : [
    EnvVarNotSet Str,
    HttpErr Http.Err,
]

logRequest : Request -> Task {} *
logRequest = \req ->
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line "$(datetime) $(Http.methodToStr req.method) $(req.url)"

readEnvVar : Str -> Task Str [EnvVarNotSet Str]
readEnvVar = \envVarName ->
    Env.var envVarName
    |> Task.mapErr \_ -> EnvVarNotSet envVarName

fetchContent : Str -> Task Str [HttpErr Http.Err]
fetchContent = \url ->
    Http.getUtf8 url

handleErr : AppError -> Task Response []
handleErr = \appErr ->

    # Build error message
    errMsg =
        when appErr is
            EnvVarNotSet envVarName -> "Environment variable \"$(envVarName)\" was not set."
            HttpErr err -> "Http error fetching content:\n\t$(Inspect.toStr err)"
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
responseWithCode : U16, Str -> Task Response *
responseWithCode = \code, body ->
    Task.ok {
        status: code,
        headers: [],
        body: Str.toUtf8 body,
    }
