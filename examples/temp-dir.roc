app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Env
import pf.Path
import http.Response

# To run this example: check the root README.md

## Returns the default temp dir

Model : {}
Action : {}
Result : {}

program = { init!, transition, respond!, shutdown! }

init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, model: {} })

transition = Server.no_transition

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _state| {
    temp_dir_str = Path.display(Env.temp_dir!())

    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("The temp dir path is ${temp_dir_str}"))))
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
