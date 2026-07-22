app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Stdout
import http.Response

Model : U64
Action : [Add(U64)]
Result : U64

program = { init!, transition, respond!, shutdown! }

init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, model: 0 })

transition : Action, Model -> { model : Model, result : Result }
transition = |Add(amount), model| {
    next = model + amount
    { model: next, result: next }
}

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, state| {
    after_first = state.apply!(Add(1)) ? |_| ServerErr("Server stopped before the first state update")
    after_second = state.apply!(Add(2)) ? |_| ServerErr("Server stopped before the second state update")

    if after_first != 1 or after_second != 3 {
        return Err(ServerErr("State updates returned unexpected values"))
    }

    response = Response.from_status(200).with_body(Str.to_utf8("updates=${after_second.to_str()}"))
    Ok(Server.stop_after(response))
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |reason, model|
    match reason {
        ApplicationRequested if model == 3 => {
            Stdout.line!("shutdown hook: ApplicationRequested, final model: 3") ? |_| Exit(1)
            Ok({})
        }
        _ => {
            Stdout.line!("shutdown mismatch: reason=${Str.inspect(reason)}, model=${model.to_str()}") ?? {}
            Err(Exit(1))
        }
    }
