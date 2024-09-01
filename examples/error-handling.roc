# This example demonstrates error handling and fetching content from another website.
app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc
import pf.Env

Model : {}

server = { init: Task.ok {}, respond }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, _ -> handleReq req |> Task.mapErr mapAppErr

AppError : [
    EnvVarNotSet Str,
    HttpErr Http.Err,
    StdoutErr Str,
]

mapAppErr : AppError -> [ServerErr Str]
mapAppErr = \appErr ->
    when appErr is
        EnvVarNotSet envVarName -> ServerErr "Environment variable \"$(envVarName)\" was not set."
        HttpErr err -> ServerErr "Http error fetching content:\n\t$(Inspect.toStr err)"
        StdoutErr err -> ServerErr "Stdout error logging request:\n\t$(err)"

# Here we use AppError to ensure all errors must be handled within our application.
handleReq : Request -> Task Response AppError
handleReq = \req ->
    # Log the date, time, method, and url to stdout
    logRequest! req

    # Read environment variable
    url = readEnvVar! "TARGET_URL"

    # Fetch content of url
    content = fetchContent! url

    # Respond with the website content
    responseWithCode 200 content

logRequest : Request -> Task {} [StdoutErr Str]
logRequest = \req ->
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line "$(datetime) $(Http.methodToStr req.method) $(req.url)"
    |> Task.mapErr \err -> StdoutErr (Inspect.toStr err)

readEnvVar : Str -> Task Str [EnvVarNotSet Str]
readEnvVar = \envVarName ->
    Env.var envVarName
    |> Task.mapErr \_ -> EnvVarNotSet envVarName

fetchContent : Str -> Task Str [HttpErr Http.Err]
fetchContent = \url ->
    Http.getUtf8 url

# Respond with the given status code and body
responseWithCode : U16, Str -> Task Response *
responseWithCode = \code, body ->
    Task.ok {
        status: code,
        headers: [],
        body: Str.toUtf8 body,
    }
