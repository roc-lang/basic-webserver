app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sleep
import pf.Stdout
import http.Response

# To run this example: check the root README.md

Model : {}
Action : {}
Result : {}

program = { init!, transition, respond!, shutdown! }

init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, model: {} })

transition = Server.no_transition

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, _state| {
    Stdout.line!("Sleeping for 1 second...")
        ? |err| ServerErr("Failed to write to stdout: ${Str.inspect(err)}")
    Sleep.millis!(1000)

    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("Response delayed by 1 second"))))
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
