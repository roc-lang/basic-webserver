# This example demonstrates error handling and fetching content from another website.
app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc
import pf.Env

Model : {}

init! : {} => Result Model []
init! = \{} -> Ok {}

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \req, _ -> handle_req! req |> Result.mapErr map_app_err

AppError : [
    EnvVarNotSet Str,
    BadBody Str,
    StdoutErr Str,
]

map_app_err : AppError -> [ServerErr Str]
map_app_err = \app_err ->
    when app_err is
        EnvVarNotSet env_var_name -> ServerErr "Environment variable \"$(env_var_name)\" was not set."
        BadBody err -> ServerErr "Http error fetching content:\n\t$(Inspect.toStr err)"
        StdoutErr err -> ServerErr "Stdout error logging request:\n\t$(err)"

# Here we use AppError to ensure all errors must be handled within our application.
handle_req! : Request => Result Response AppError
handle_req! = \req ->
    # Log the date, time, method, and url to stdout
    try log_request! req

    # Read environment variable
    url = try read_env_var! "TARGET_URL"

    # Fetch content of url
    content = try fetch_content! url

    # Respond with the website content
    response_with_code! 200 content

log_request! : Request => Result {} [StdoutErr Str]
log_request! = \req ->
    datetime = Utc.to_iso_8601 (Utc.now! {})

    Stdout.line! "$(datetime) $(Inspect.toStr req.method) $(req.uri)"
    |> Result.mapErr \err -> StdoutErr (Inspect.toStr err)

read_env_var! : Str => Result Str [EnvVarNotSet Str]
read_env_var! = \env_var_name ->
    Env.var! env_var_name
    |> Result.mapErr \_ -> EnvVarNotSet env_var_name

fetch_content! : Str => Result Str _
fetch_content! = \url ->
    Http.get_utf8! url

# Respond with the given status code and body
response_with_code! : U16, Str => Result Response *
response_with_code! = \code, body ->
    Ok {
        status: code,
        headers: [],
        body: Str.toUtf8 body,
    }
