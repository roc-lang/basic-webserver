app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Path
import pf.Server
import http.Response

# To run this example: check the root README.md

Model : Str
Action : [GetContents]
Result : [Contents(Str)]

program = { init!, transition, respond!, shutdown! }

init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = ||
    match Path.read_utf8!(Path.utf8("examples/file-read.roc")) {
        Ok(contents) => Ok({ config: Server.default_config, model: "Source code of current program:\n\n${contents}" })
        Err(_) => Err(Exit(1))
    }

transition : Action, Model -> { model : Model, result : Result }
transition = |GetContents, model| { model, result: Contents(model) }

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, state| {
    Contents(contents) = state.apply!(GetContents) ? |_| ServerErr("Server is stopping")
    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(contents))))
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
