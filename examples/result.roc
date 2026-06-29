app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Http
import http.Response

# To run this example: check the README.md in this folder

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    match check_file!("good") {
        Ok(Good) => Ok(Response.from_status(200).with_body(Str.to_utf8("GOOD")))
        Ok(Bad) => Ok(Response.from_status(200).with_body(Str.to_utf8("BAD")))
        Err(IOError) => Ok(Response.from_status(500).with_body(Str.to_utf8("ERROR: IoError when executing checkFile!.")))
    }

# imagine this function does some IO operation
# and returns a Try, succeeding with a tag either Good or Bad,
# or failing with an IOError
check_file! : Str => Try([Good, Bad], [IOError])
check_file! = |str|
    if str == "good" {
        Ok(Good)
    } else if str == "bad" {
        Ok(Bad)
    } else {
        Err(IOError)
    }
