app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Stdout

# To run this example: check the README.md in this folder

## Echo server: logs the request method/uri and replies with the request body.

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _model| {
    _ = Stdout.line!("${Str.inspect(req.method)} ${req.uri}")
    Ok({ status: 200, headers: [], body: req.body })
}
