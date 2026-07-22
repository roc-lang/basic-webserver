app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Server
import http.Response

# To run this example: check the root README.md

Model : [DebugPrintMode, NonDebugMode]
Action : [GetMode]
Result : [Mode(Model)]

program = { init!, transition, respond!, shutdown! }

init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = ||
    match Env.var_str!("DEBUG") {
        Ok("1") => Ok({ config: Server.default_config, model: DebugPrintMode })
        _ => Ok({ config: Server.default_config, model: NonDebugMode })
    }

transition : Action, Model -> { model : Model, result : Result }
transition = |GetMode, model| { model, result: Mode(model) }

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, state| {
    Mode(model) = state.apply!(GetMode) ? |_| ServerErr("Server is stopping")
    match model {
        DebugPrintMode => {
            Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(Str.inspect(Env.dict!())))))
        }
        NonDebugMode => Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("DEBUG var not set"))))
    }
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
