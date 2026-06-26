app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Http

# To run this example: check the README.md in this folder

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    match Env.var!("HOME") {
        Ok(value) => Ok({ status: 200, headers: [], body: Str.to_utf8("HOME=${value}") })
        Err(VarNotFound(name)) => Ok({ status: 200, headers: [], body: Str.to_utf8("env var not found: ${name}") })
    }
