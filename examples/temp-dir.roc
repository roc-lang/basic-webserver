app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Env

# To run this example: check the README.md in this folder

## Returns the default temp dir
##
## !! requires --linker=legacy
## for example: `roc build examples/temp-dir.roc --linker=legacy`

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model| {
    temp_dir_str = Env.temp_dir!({})

    Ok({ status: 200, headers: [], body: Str.to_utf8("The temp dir path is ${temp_dir_str}") })
}
