# This example demonstrates error handling and fetching content from another website.
app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc
import pf.Env

# To run this example: check the README.md in this folder

Model : {}

init! : {} => Result Model []
init! = |{}| Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |req, _|
    handle_req!(req) |> Result.map_err(map_app_err)

AppError : [
    EnvVarNotSet Str,
    FetchErr Str,
    StdoutErr Str,
]

map_app_err : AppError -> [ServerErr Str]
map_app_err = |app_err|
    when app_err is
        EnvVarNotSet(env_var_name) -> ServerErr("Environment variable \"${env_var_name}\" was not set.")
        FetchErr(err) -> ServerErr("Failed to fetch content:\n\t${err}")
        StdoutErr(err) -> ServerErr("Stdout error logging request:\n\t${err}")

# Here we use AppError to ensure all errors must be handled within our application.
handle_req! : Request => Result Response AppError
handle_req! = |req|
    # Log the date, time, method, and url to stdout
    log_request!(req)?

    # Read environment variable
    url = read_env_var!("TARGET_URL")?

    # Fetch content of url
    content = fetch_content!(url)?

    # Respond with the website content
    response_with_code!(200, content)

log_request! : Request => Result {} [StdoutErr Str]
log_request! = |req|
    datetime = Utc.to_iso_8601(Utc.now!({}))

    Stdout.line!("${datetime} ${Inspect.to_str(req.method)} ${req.uri}")
    |> Result.map_err(|err| StdoutErr(Inspect.to_str(err)))

read_env_var! : Str => Result Str [EnvVarNotSet Str]
read_env_var! = |env_var_name|
    Env.var!(env_var_name)
    |> Result.map_err(|_| EnvVarNotSet(env_var_name))

fetch_content! : Str => Result Str [FetchErr Str]
fetch_content! = |url|
    Http.get_utf8!(url)
    |> Result.map_err(|err| FetchErr(Inspect.to_str(err)))

# Respond with the given status code and body
response_with_code! : U16, Str => Result Response *
response_with_code! = |code, body|
    Ok(
        {
            status: code,
            headers: [],
            body: Str.to_utf8(body),
        },
    )
