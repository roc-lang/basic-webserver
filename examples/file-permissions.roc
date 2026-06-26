app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Http
import pf.File

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| {
    result = || {
        file = "LICENSE"

        is_executable = File.is_executable!(file)?

        is_readable = File.is_readable!(file)?

        is_writable = File.is_writable!(file)?

        Stdout.line!("${file} file permissions:\n    Executable: ${Str.inspect(is_executable)}\n    Readable: ${Str.inspect(is_readable)}\n    Writable: ${Str.inspect(is_writable)}")?

        Ok({})
    }

    match result() {
        Ok(_) => Ok({})
        Err(err) => {
            _ = Stderr.line!("Error reading file permissions: ${Str.inspect(err)}")
            Err(Exit(1))
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok({ status: 200, headers: [], body: Str.to_utf8("See example in init! function.") })
