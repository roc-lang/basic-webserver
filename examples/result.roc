app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Http

# To run this example: check the README.md in this folder

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    match check_file!("good") {
        Ok(Good) => Ok({ status: 200, headers: [], body: Str.to_utf8("GOOD") })
        Ok(Bad) => Ok({ status: 200, headers: [], body: Str.to_utf8("BAD") })
        Err(IOError) => Ok({ status: 500, headers: [], body: Str.to_utf8("ERROR: IoError when executing checkFile!.") })
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
