# This example demonstrates error handling and fetching content from another website.
app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Http
import pf.OsStr
import pf.Server
import pf.Url
import pf.Env
import pf.Utc
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

AppError : [
    EnvVarNotSet(Str),
    FetchErr(Str),
    StdoutErr(Str),
]

# Here we use AppError to ensure all errors must be handled within our application.

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, _state|
    match handle_req!(req) {
        Ok(response) => Ok(Server.respond(response))
        Err(app_err) => Err(map_app_err(app_err))
    }

map_app_err : AppError -> [ServerErr(Str), ..]
map_app_err = |app_err|
    match app_err {
        EnvVarNotSet(env_var_name) => ServerErr("Environment variable \"${env_var_name}\" was not set.")
        FetchErr(err) => ServerErr("Failed to fetch content:\n\t${err}")
        StdoutErr(err) => ServerErr("Stdout error logging request:\n\t${err}")
    }

handle_req! : Server.Request => Try(Response.Response, AppError)
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

log_request! : Server.Request => Try({}, [StdoutErr(Str), ..])
log_request! = |req| {
    datetime = Utc.to_iso_8601(Utc.now!())

    Ok(Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.target()}") ? |err| StdoutErr(Str.inspect(err)))
}

read_env_var! : Str => Try(Str, [EnvVarNotSet(Str), ..])
read_env_var! = |env_var_name|
    Ok(Env.var_str!(OsStr.from_str(env_var_name)) ? |_| EnvVarNotSet(env_var_name))

fetch_content! : Str => Try(Str, [FetchErr(Str), ..])
fetch_content! = |url_str| {
    url = Url.parse(url_str) ? |err| FetchErr("Invalid URL: ${Str.inspect(err)}")
    Ok(Http.get_utf8!(url) ? |err| FetchErr(Str.inspect(err)))
}

# Respond with the given status code and body
response_with_code : U16, Str -> Response.Response
response_with_code = |code, body|
    Response.from_status(code).with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
