app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.File
import pf.Http
import http.Response

# To run this example: check the README.md in this folder

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    match File.read_utf8!("examples/file-read.roc") {
        Ok(contents) => Ok(Response.from_status(200).with_body(Str.to_utf8(contents)))
        Err(err) => Err(ServerErr("Failed to read file: ${Str.inspect(err)}"))
    }
