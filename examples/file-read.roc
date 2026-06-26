app [Model, program] { pf: platform "../platform/main.roc" }

import pf.File
import pf.Http

# To run this example: check the README.md in this folder

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    match File.read_utf8!("examples/file-read.roc") {
        Ok(contents) => Ok({ status: 200, headers: [], body: Str.to_utf8(contents) })
        Err(err) => Err(ServerErr("Failed to read file: ${Str.inspect(err)}"))
    }
