# This example demonstrates error handling and fetching content from another website.
app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Stdout
import pf.Http
import pf.Env
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

AppError : [
    EnvVarNotSet(Str),
    FetchErr(Str),
    StdoutErr(Str),
]

# Here we use AppError to ensure all errors must be handled within our application.
respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _|
    match handle_req!(req) {
        Ok(response) => Ok(response)
        Err(app_err) => Err(map_app_err(app_err))
    }

map_app_err : AppError -> [ServerErr(Str), ..]
map_app_err = |app_err|
    match app_err {
        EnvVarNotSet(env_var_name) => ServerErr("Environment variable \"${env_var_name}\" was not set.")
        FetchErr(err) => ServerErr("Failed to fetch content:\n\t${err}")
        StdoutErr(err) => ServerErr("Stdout error logging request:\n\t${err}")
    }

handle_req! : Http.Request => Try(Http.Response, AppError)
handle_req! = |req| {
    # Log the method and url to stdout
    log_request!(req)?

    # Read environment variable
    url = read_env_var!("TARGET_URL")?

    # Fetch content of url
    content = fetch_content!(url)?

    # Respond with the website content
    Ok(response_with_code(200, content))
}

log_request! : Http.Request => Try({}, [StdoutErr(Str), ..])
log_request! = |req|
    Ok(Stdout.line!("${Str.inspect(req.method())} ${req.uri()}") ? |err| StdoutErr(Str.inspect(err)))

read_env_var! : Str => Try(Str, [EnvVarNotSet(Str), ..])
read_env_var! = |env_var_name|
    Ok(Env.var!(env_var_name) ? |_| EnvVarNotSet(env_var_name))

fetch_content! : Str => Try(Str, [FetchErr(Str), ..])
fetch_content! = |url|
    Ok(Http.get_utf8!(url) ? |err| FetchErr(Str.inspect(err)))

# Respond with the given status code and body
response_with_code : U16, Str -> Http.Response
response_with_code = |code, body|
    Response.from_status(code).with_body(Str.to_utf8(body))
