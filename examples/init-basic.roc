app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Server
import pf.Utc
import http.Response

# To run this example: check the root README.md

# Model is produced by `init!`.
Model : Str
Action : [GetGift]
Result : [Gift(Str)]

program = { init!, transition, respond!, shutdown! }

# With `init!` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this example it is just `Ok("🎁")`.
init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, model: "🎁" })

transition : Action, Model -> { model : Model, result : Result }
transition = |GetGift, model| { model, result: Gift(model) }

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, state| {
    Gift(gift) = state.apply!(GetGift) ? |_| ServerErr("Server is stopping")
    # Log request datetime, method and url
    datetime = Utc.to_iso_8601(Utc.now!())

    Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.target()}")
        ? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("<b>init gave me ${gift}</b>"))))
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
